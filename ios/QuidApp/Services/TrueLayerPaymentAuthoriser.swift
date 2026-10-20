#if canImport(TrueLayerSDK)
import Foundation
import TrueLayerSDK
import UIKit

/// The preferred path (docs/SPEC.md section 6): TrueLayer's SDK presents the bank selection and consent screens and
/// hands the user to their banking app. API verified against the SDK's public interface (TrueLayer-iOS-SDK 4.1.9).
@MainActor
final class TrueLayerPaymentAuthoriser: PaymentAuthoriser {
    private let environment: TrueLayer.Environment
    private var configured = false
    private var inFlight: TrueLayer.Payments.Models.SinglePayment.Context?
    private var finish: ((AuthorisationOutcome) -> Void)?

    init(environment: AppConfig.TrueLayerEnvironment) {
        self.environment = environment == .live ? .production : .sandbox
    }

    func authorise(_ request: AuthorisationRequest) async -> AuthorisationOutcome {
        guard let providerPaymentId = request.providerPaymentId else {
            return .failed("This payment hasn't reached the bank yet. Try again in a moment.")
        }
        if !configured {
            await TrueLayer.Payments.manager.configure(environment: environment)
            configured = true
        }
        guard let presenter = WindowAnchorProvider.topViewController() else {
            return .failed("Couldn't open your bank's screen.")
        }
        let context = TrueLayer.Payments.Models.SinglePayment.Context(
            identifier: providerPaymentId,
            token: request.resourceToken,
            redirectURL: request.returnURL,
            preferences: .init(
                presentationStyle: .present(on: presenter, style: .automatic),
                preferredCountryCode: "GB",
                // Quid shows its own result screen driven by the server's status.
                shouldShowResultScreen: false
            )
        )
        inFlight = context
        return await withCheckedContinuation { continuation in
            var resumed = false
            finish = { outcome in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: outcome)
            }
            start(context)
        }
    }

    /// The SDK's own documentation recommends re-invoking processSinglePayment with the same context when the bank
    /// sends the user back, because some banks need a further step that the SDK then presents.
    func handleReturn(url: URL) -> Bool {
        guard let context = inFlight else { return false }
        start(context)
        return true
    }

    private func start(_ context: TrueLayer.Payments.Models.SinglePayment.Context) {
        TrueLayer.Payments.manager.processSinglePayment(context: context) { [weak self] (result: Result<TrueLayer.Payments.Models.SinglePayment.State, TrueLayer.Payments.Models.SinglePayment.Error>) in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let outcome = TrueLayerPaymentAuthoriser.outcome(for: result)
                self.inFlight = nil
                self.finish?(outcome)
                self.finish = nil
            }
        }
    }

    private static func outcome(for result: Result<TrueLayer.Payments.Models.SinglePayment.State, TrueLayer.Payments.Models.SinglePayment.Error>) -> AuthorisationOutcome {
        switch result {
        case .success:
            return .completed
        case .failure(let error):
            switch error {
            case .userCanceled, .userCanceledAtProvider:
                return .cancelled
            default:
                return .failed("The payment didn't go through. Nothing has been sent.")
            }
        }
    }
}
#endif
