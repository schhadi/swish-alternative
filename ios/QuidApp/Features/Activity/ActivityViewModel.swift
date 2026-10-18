import Foundation
import Observation

enum ActivityFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case sent = "Sent"
    case received = "Received"

    var id: String { rawValue }
}

struct ActivitySection: Identifiable {
    let id: Date
    let title: String
    let payments: [PaymentDTO]
}

@MainActor
@Observable
final class ActivityViewModel {
    var searchText = ""
    var filter: ActivityFilter = .all
    private(set) var me: MeDTO?
    private(set) var payments: [PaymentDTO] = []
    private(set) var error: AppError?
    private(set) var isLoading = false

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    var currentUserId: String {
        me?.user.id ?? ""
    }

    var filteredPayments: [PaymentDTO] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return payments.filter { payment in
            let direction = payment.direction(for: currentUserId)
            if filter == .sent && direction != .sent { return false }
            if filter == .received && direction != .received { return false }
            if query.isEmpty { return true }
            return payment.counterparty.displayName.lowercased().contains(query)
                || payment.reference.lowercased().contains(query)
        }
    }

    var sections: [ActivitySection] {
        ActivityViewModel.sections(for: filteredPayments)
    }

    /// Groups by calendar day, newest day first, newest payment first within a day.
    nonisolated static func sections(for payments: [PaymentDTO], calendar: Calendar = .current) -> [ActivitySection] {
        let grouped = Dictionary(grouping: payments) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            ActivitySection(
                id: day,
                title: day.quidSectionTitle,
                payments: (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let meTask = api.send(API.me())
            async let sentTask = api.send(API.payments(role: .sent))
            async let receivedTask = api.send(API.payments(role: .received))
            let (me, sent, received) = try await (meTask, sentTask, receivedTask)
            self.me = me
            self.payments = (sent.payments + received.payments).sorted { $0.createdAt > $1.createdAt }
            self.error = nil
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            self.error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }
}
