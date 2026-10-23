import AuthenticationServices
import Foundation
import UIKit

/// What happened in the payer's bank. The result screen never trusts this alone: it reads the server's status.
enum AuthorisationOutcome: Equatable, Sendable {
    case completed
    case cancelled
    case failed(String)
}

struct AuthorisationRequest: Equatable, Sendable {
    let paymentId: String
    let providerPaymentId: String?
    let resourceToken: String
    let authorisationUrl: URL?
    let returnURL: URL
}

/// Takes the payer through bank authorisation (docs/SPEC.md section 6): the TrueLayer SDK in a real build, a hosted
/// web page as a fallback, an instant stand-in in MockMode.
@MainActor
protocol PaymentAuthoriser: AnyObject {
    func authorise(_ request: AuthorisationRequest) async -> AuthorisationOutcome
    /// The bank sent the user back (quid://return/payment). Returns true when it was consumed.
    func handleReturn(url: URL) -> Bool
}

/// MockMode: resolves after a short pause, as if the bank approved. The mock backend advances the payment by age.
@MainActor
final class MockPaymentAuthoriser: PaymentAuthoriser {
    var outcome: AuthorisationOutcome = .completed
    var delay: TimeInterval = 0.4
    private(set) var requests: [AuthorisationRequest] = []

    func authorise(_ request: AuthorisationRequest) async -> AuthorisationOutcome {
        requests.append(request)
        if delay > 0 {
            try? await Task.sleep(for: .seconds(delay))
        }
        // Approving at the mock bank is what starts a mock payment moving; a cancel leaves it waiting.
        if outcome == .completed {
            MockServer.shared.withStateLock { MockFixtures.approve(paymentId: request.paymentId) }
        }
        return outcome
    }

    func handleReturn(url: URL) -> Bool {
        false
    }
}

/// Fallback: TrueLayer's hosted payment page in an ASWebAuthenticationSession; the bank returns through our URL scheme.
@MainActor
final class WebPaymentAuthoriser: PaymentAuthoriser {
    private var session: ASWebAuthenticationSession?
    private let anchor = WindowAnchorProvider()

    func authorise(_ request: AuthorisationRequest) async -> AuthorisationOutcome {
        guard let url = request.authorisationUrl else {
            return .failed("Your bank's payment page wasn't available. Try again in a moment.")
        }
        return await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: request.returnURL.scheme) { _, error in
                Task { @MainActor [weak self] in self?.session = nil }
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(returning: .cancelled)
                } else if error != nil {
                    continuation.resume(returning: .failed("Couldn't open your bank's payment page."))
                } else {
                    continuation.resume(returning: .completed)
                }
            }
            session.presentationContextProvider = anchor
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                self.session = nil
                continuation.resume(returning: .failed("Couldn't open your bank's payment page."))
            }
        }
    }

    func handleReturn(url: URL) -> Bool {
        // ASWebAuthenticationSession consumes the callback itself.
        false
    }
}

/// The key window, for sheets presented by system frameworks.
final class WindowAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            WindowAnchorProvider.keyWindow() ?? ASPresentationAnchor()
        }
    }

    @MainActor
    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// The view controller to present on: the deepest presented controller of the key window.
    @MainActor
    static func topViewController() -> UIViewController? {
        var top = keyWindow()?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
