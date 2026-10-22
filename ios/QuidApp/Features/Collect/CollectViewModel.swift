import Foundation
import Observation

@MainActor
@Observable
final class CollectViewModel {
    private(set) var organisations: [OrganisationDTO] = []
    /// Collections the user is on the list of (to pay, or paid).
    private(set) var dues: [CollectionDueDTO] = []
    private(set) var error: AppError?
    private(set) var isLoading = false

    /// True once any load has succeeded. Views use it to tell "not loaded yet" from "loaded and empty".
    private(set) var hasLoaded = false

    /// Placeholders are shown while this is true: nothing loaded yet and nothing failed (covers the first frame
    /// before `.task` starts, the load itself, and a load cancelled by leaving the screen).
    var isAwaitingFirstLoad: Bool {
        !hasLoaded && error == nil
    }

    let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    /// Organisations the user can create collections for.
    var treasurerOrganisations: [OrganisationDTO] {
        organisations.filter { $0.role == .treasurer }
    }

    var isEmpty: Bool {
        organisations.isEmpty && dues.isEmpty
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let organisationsTask = api.send(API.organisations())
            async let duesTask = api.send(API.collectionsDue())
            let (organisations, dues) = try await (organisationsTask, duesTask)
            self.organisations = organisations.organisations
            self.dues = dues.collections
            error = nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }
}

enum MemberFilter: String, CaseIterable, Identifiable {
    case unpaid = "Unpaid"
    case paid = "Paid"
    case all = "All"

    var id: String { rawValue }
}

@MainActor
@Observable
final class CollectionDetailViewModel {
    var filter: MemberFilter = .unpaid
    private(set) var collection: CollectionSummaryDTO
    private(set) var organisationName: String = ""
    private(set) var members: [CollectionMemberDTO] = []
    private(set) var error: AppError?
    private(set) var isLoading = false
    /// True once any load has succeeded. Views use it to tell "not loaded yet" from "loaded and empty".
    private(set) var hasLoaded = false
    /// One line after a reminder, "Remind all" or closing: what happened, or why nothing did.
    private(set) var notice: String?
    private(set) var busyMemberIds: Set<String> = []
    private(set) var isRemindingAll = false
    private(set) var isClosing = false
    let justCreated: Bool

    private let api: APIClient

    /// Placeholders are shown while this is true: nothing loaded yet and nothing failed.
    var isAwaitingFirstLoad: Bool {
        !hasLoaded && error == nil
    }

    init(api: APIClient, collection: CollectionSummaryDTO, justCreated: Bool = false) {
        self.api = api
        self.collection = collection
        self.justCreated = justCreated
    }

    var isOpen: Bool { collection.status == .open }

    var linkURL: URL? {
        collection.link.flatMap(URL.init(string:))
    }

    /// Unpaid, on Quid and not reminded in the last 24 hours.
    func canRemind(_ member: CollectionMemberDTO, at now: Date = Date()) -> Bool {
        guard isOpen, member.status == .unpaid, member.isOnQuid ?? false else { return false }
        guard let next = member.nextReminderAt else { return true }
        return next <= now
    }

    var dueReminderCount: Int {
        members.filter { canRemind($0) }.count
    }

    /// Someone unpaid could ever be reminded: they use Quid. People added by name can only be sent the link.
    var hasRemindableUnpaid: Bool {
        members.contains { $0.status == .unpaid && ($0.isOnQuid ?? false) }
    }

    private func apply(_ detail: CollectionDetailDTO) {
        collection = detail.collection
        organisationName = detail.organisationName
        members = detail.members
        hasLoaded = true
    }

    func remind(_ member: CollectionMemberDTO) async {
        guard !busyMemberIds.contains(member.id) else { return }
        busyMemberIds.insert(member.id)
        defer { busyMemberIds.remove(member.id) }
        await sendReminders(memberIds: [member.id])
    }

    /// "Remind all unpaid": everyone unpaid on Quid who wasn't reminded in the last day.
    func remindAll() async {
        guard !isRemindingAll else { return }
        isRemindingAll = true
        defer { isRemindingAll = false }
        await sendReminders(memberIds: nil)
    }

    private func sendReminders(memberIds: [String]?) async {
        do {
            let result = try await api.send(API.remindCollection(id: collection.id, memberIds: memberIds))
            apply(result.detail)
            notice = CollectionDetailViewModel.summary(of: result)
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            notice = appError.userMessage
        } catch {
            notice = error.localizedDescription
        }
    }

    nonisolated static func summary(of result: CollectionReminderResultDTO) -> String {
        let names = result.reminded.compactMap { id in result.detail.members.first { $0.id == id }?.displayName }
        let notOnQuid = result.skipped.filter { $0.reason == "not_on_quid" }.count
        let tooSoon = result.skipped.filter { $0.reason == "too_soon" }.count
        var parts: [String] = []
        if names.isEmpty {
            parts.append(tooSoon > 0 ? "Everyone you can remind was reminded in the last day." : "Nobody to remind.")
        } else {
            parts.append("Reminded \(NameList.firstNames(names)).")
        }
        if notOnQuid > 0 {
            parts.append(notOnQuid == 1 ? "1 person isn't on Quid: send them the link." : "\(notOnQuid) people aren't on Quid: send them the link.")
        }
        return parts.joined(separator: " ")
    }

    /// Stops new payments; payments already at the bank still count.
    func close() async {
        guard isOpen, !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        do {
            apply(try await api.send(API.closeCollection(id: collection.id)))
            notice = "Collection closed. The link no longer takes payments."
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            notice = appError.userMessage
        } catch {
            notice = error.localizedDescription
        }
    }

    var paidCount: Int {
        members.isEmpty ? collection.paidCount : members.filter { $0.status == .paid }.count
    }

    var memberCount: Int {
        members.isEmpty ? collection.memberCount : members.count
    }

    var unpaidCount: Int {
        memberCount - paidCount
    }

    var collected: Money {
        Money(minor: paidCount * collection.amountPerPersonMinor)
    }

    var target: Money {
        Money(minor: memberCount * collection.amountPerPersonMinor)
    }

    var filteredMembers: [CollectionMemberDTO] {
        switch filter {
        case .unpaid: return members.filter { $0.status == .unpaid }
        case .paid: return members.filter { $0.status == .paid }
        case .all: return members
        }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            apply(try await api.send(API.collection(orgId: collection.orgId, collectionId: collection.id)))
            error = nil
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }
}
