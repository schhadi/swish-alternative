import Foundation
import Observation

/// A request addressed to the user: pay it through the Pay flow, or decline it.
@MainActor
@Observable
final class IncomingRequestViewModel {
    private(set) var request: PaymentRequestDTO
    private(set) var isDeclining = false
    private(set) var error: AppError?

    private let api: APIClient

    init(api: APIClient, request: PaymentRequestDTO) {
        self.api = api
        self.request = request
    }

    var isOpen: Bool { request.status == .pending }

    func refresh() async {
        do {
            request = try await api.send(API.request(id: request.id))
            error = nil
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    func decline() async {
        guard isOpen, !isDeclining else { return }
        isDeclining = true
        defer { isDeclining = false }
        do {
            request = try await api.send(API.declineRequest(id: request.id))
            error = nil
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            error = appError
            // Someone else's change (paid, expired) explains the refusal; show the request as it now is.
            if appError.code == "request_not_pending" { await refresh() }
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    /// "Decline Priya's request for £18?"
    nonisolated static func declineQuestion(for request: PaymentRequestDTO) -> String {
        "Decline \(request.requester.firstName)'s request for \(Money(minor: request.amountMinor).formatted())?"
    }

    nonisolated static let declineExplanation = "They'll see that you declined. Nothing is paid."
}
