import Foundation
import Observation

/// Someone the user has paid or been paid by recently.
struct RecentContact: Identifiable, Hashable {
    let id: String
    let displayName: String
    let isRegistered: Bool

    var firstName: String {
        String(displayName.split(whereSeparator: { $0.isWhitespace }).first ?? Substring(displayName))
    }
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var me: MeDTO?
    private(set) var payments: [PaymentDTO] = []
    private(set) var incomingRequests: [PaymentRequestDTO] = []
    /// Collections the user is on the list of and still owes (open and unpaid).
    private(set) var collectionDues: [CollectionDueDTO] = []
    /// Why the last Decline didn't go through; shown under the requests.
    private(set) var requestError: String?
    private(set) var decliningIds: Set<String> = []
    private(set) var error: AppError?
    private(set) var isLoading = false

    /// True once any load has succeeded. Views use it to tell "not loaded yet" from "loaded and empty".
    private(set) var hasLoaded = false

    /// Placeholders are shown while this is true: nothing loaded yet and nothing failed (covers the first frame
    /// before `.task` starts, the load itself, and a load cancelled by leaving the screen).
    var isAwaitingFirstLoad: Bool {
        !hasLoaded && error == nil
    }

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    var currentUserId: String {
        me?.user.id ?? ""
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        switch hour {
        case 5..<12: timeOfDay = "Good morning"
        case 12..<18: timeOfDay = "Good afternoon"
        default: timeOfDay = "Good evening"
        }
        if let first = me?.user.displayName.split(whereSeparator: { $0.isWhitespace }).first {
            return "\(timeOfDay), \(first)"
        }
        return timeOfDay
    }

    /// Newest first, registered contacts before unregistered ones, collections excluded.
    var recentContacts: [RecentContact] {
        var seen = Set<String>()
        var registered: [RecentContact] = []
        var unregistered: [RecentContact] = []
        for payment in payments where payment.collectionId == nil {
            let key = payment.counterparty.userId ?? payment.counterparty.displayName
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let contact = RecentContact(
                id: key,
                displayName: payment.counterparty.displayName,
                isRegistered: payment.counterparty.userId != nil
            )
            if contact.isRegistered {
                registered.append(contact)
            } else {
                unregistered.append(contact)
            }
        }
        return Array((registered + unregistered).prefix(8))
    }

    var recentPayments: [PaymentDTO] {
        Array(payments.prefix(5))
    }

    /// Declines a request addressed to the user and drops it from Home.
    func decline(_ request: PaymentRequestDTO) async {
        guard !decliningIds.contains(request.id) else { return }
        decliningIds.insert(request.id)
        defer { decliningIds.remove(request.id) }
        do {
            _ = try await api.send(API.declineRequest(id: request.id))
            incomingRequests.removeAll { $0.id == request.id }
            requestError = nil
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            requestError = appError.userMessage
            if appError.code == "request_not_pending" {
                // Paid or expired in the meantime: show the list as it now is.
                if let fresh = try? await api.send(API.incomingRequests()) {
                    incomingRequests = fresh.requests.filter { $0.status == .pending }
                }
            }
        } catch {
            requestError = error.localizedDescription
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let meTask = api.send(API.me())
            async let sentTask = api.send(API.payments(role: .sent))
            async let receivedTask = api.send(API.payments(role: .received))
            async let requestsTask = api.send(API.incomingRequests())
            async let duesTask = api.send(API.collectionsDue())
            let (me, sent, received, requests, dues) = try await (meTask, sentTask, receivedTask, requestsTask, duesTask)
            self.me = me
            self.payments = (sent.payments + received.payments).sorted { $0.createdAt > $1.createdAt }
            self.incomingRequests = requests.requests.filter { $0.status == .pending }
            self.collectionDues = dues.collections.filter(\.isPayable)
            self.error = nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            self.error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }
}
