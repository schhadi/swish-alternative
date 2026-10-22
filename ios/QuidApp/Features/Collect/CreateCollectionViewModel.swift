import Foundation
import Observation

/// A new collection for one organisation: title, amount each, an optional due date and who should pay, from
/// contacts on Quid or by name. Anyone with the link can pay too, so the list may be empty.
@MainActor
@Observable
final class CreateCollectionViewModel {
    struct Member: Identifiable, Hashable {
        let id: String
        /// Set for people on Quid (they can be reminded and pay in the app); nil for people added by name.
        let userId: String?
        let displayName: String
    }

    enum Step: Hashable {
        case people
    }

    static let titleMaxLength = 60
    static let maxMembers = 200
    static let fallbackPerPersonLimitMinor = 25000

    let organisation: OrganisationDTO
    var path: [Step] = []
    var title = "" {
        didSet {
            let clipped = String(title.prefix(CreateCollectionViewModel.titleMaxLength))
            if clipped != title { title = clipped }
        }
    }
    /// As typed: "30", "12.5". Cleaned by the field as you type.
    private(set) var amountText = ""
    var hasDueDate = true
    var dueDate: Date
    var newName = ""
    private(set) var members: [Member] = []
    private(set) var memberMessage: String?
    private(set) var isSubmitting = false
    private(set) var error: AppError?
    private(set) var created: CollectionDetailDTO?

    private let environment: AppEnvironment
    private var nameCounter = 0

    init(environment: AppEnvironment, organisation: OrganisationDTO, now: Date = Date()) {
        self.environment = environment
        self.organisation = organisation
        dueDate = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
    }

    var api: APIClient { environment.api }

    var perPersonLimitMinor: Int {
        environment.profile?.limits.perPaymentMinor ?? CreateCollectionViewModel.fallbackPerPersonLimitMinor
    }

    var amountMinor: Int {
        PayViewModel.minor(from: amountText)
    }

    func setAmountText(_ raw: String) {
        error = nil
        let cleaned = PayViewModel.sanitisedAmount(raw)
        if cleaned != amountText { amountText = cleaned }
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var amountProblem: String? {
        amountMinor > perPersonLimitMinor
            ? "Each person can pay up to \(Money(minor: perPersonLimitMinor).formatted(compact: true)), the most anyone can send in one payment."
            : nil
    }

    var canSubmit: Bool {
        !trimmedTitle.isEmpty && amountMinor > 0 && amountProblem == nil && !isSubmitting
    }

    var submitTitle: String {
        amountMinor > 0 ? "Create · \(Money(minor: amountMinor).formatted(compact: true)) each" : "Create collection"
    }

    var target: Money {
        Money(minor: amountMinor * members.count)
    }

    // MARK: - People

    func isSelected(_ userId: String) -> Bool {
        members.contains { $0.userId == userId }
    }

    func toggle(_ contact: RegisteredContactDTO) {
        memberMessage = nil
        if let index = members.firstIndex(where: { $0.userId == contact.userId }) {
            members.remove(at: index)
            return
        }
        guard members.count < CreateCollectionViewModel.maxMembers else {
            memberMessage = "A collection can have up to \(CreateCollectionViewModel.maxMembers) people."
            return
        }
        members.append(Member(id: "user-\(contact.userId)", userId: contact.userId, displayName: contact.displayName))
    }

    /// Adds someone who isn't on Quid. They pay from the link; their name is how the list matches the payment.
    func addName() {
        memberMessage = nil
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        guard !name.isEmpty else { return }
        guard name.count <= 60 else {
            memberMessage = "Keep names to 60 characters."
            return
        }
        guard !members.contains(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) else {
            memberMessage = "\(name) is already on the list."
            return
        }
        guard members.count < CreateCollectionViewModel.maxMembers else {
            memberMessage = "A collection can have up to \(CreateCollectionViewModel.maxMembers) people."
            return
        }
        nameCounter += 1
        members.append(Member(id: "name-\(nameCounter)", userId: nil, displayName: name))
        newName = ""
    }

    func remove(_ member: Member) {
        members.removeAll { $0.id == member.id }
    }

    // MARK: - Creating

    func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let body = CreateCollectionRequest(
            title: trimmedTitle,
            amountPerPersonMinor: amountMinor,
            dueAt: hasDueDate ? Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: dueDate) ?? dueDate : nil,
            members: members.map { CreateCollectionRequest.Member(userId: $0.userId, displayName: $0.userId == nil ? $0.displayName : nil) }
        )
        do {
            created = try await api.send(API.createCollection(orgId: organisation.id, body))
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
