import Foundation
import Observation

@MainActor
@Observable
final class CollectViewModel {
    private(set) var organisations: [OrganisationDTO] = []
    private(set) var error: AppError?
    private(set) var isLoading = false

    let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            organisations = try await api.send(API.organisations()).organisations
            error = nil
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

    private let api: APIClient

    init(api: APIClient, collection: CollectionSummaryDTO) {
        self.api = api
        self.collection = collection
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
            let detail = try await api.send(API.collection(orgId: collection.orgId, collectionId: collection.id))
            collection = detail.collection
            organisationName = detail.organisationName
            members = detail.members
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }
}
