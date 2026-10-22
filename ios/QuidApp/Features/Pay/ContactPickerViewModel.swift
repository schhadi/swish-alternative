import Contacts
import Foundation
import Observation

/// Address-book contacts matched against the directory. Hashes leave the phone, numbers never do.
@MainActor
@Observable
final class ContactPickerViewModel {
    enum Permission: Equatable {
        case undetermined, denied, granted
    }

    struct Entry: Identifiable, Hashable {
        let contact: ContactPhone
        let registered: RegisteredContactDTO?

        var id: String { contact.id }
        var isRegistered: Bool { registered != nil }
    }

    var searchText = ""
    private(set) var permission: Permission
    private(set) var entries: [Entry] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var error: AppError?
    /// This user's invite link, shared from the Invite buttons. Nil until loaded; the buttons wait for it.
    private(set) var invite: InviteDTO?

    private let contactSource: any ContactSource
    private let directory: DirectoryService
    private let api: APIClient

    init(contactSource: any ContactSource, api: APIClient) {
        self.contactSource = contactSource
        self.api = api
        directory = DirectoryService(api: api)
        permission = ContactPickerViewModel.permission(for: contactSource.authorizationStatus)
    }

    var inviteURL: URL? {
        invite.flatMap { URL(string: $0.url) }
    }

    var registered: [Entry] {
        filtered.filter(\.isRegistered)
    }

    var others: [Entry] {
        filtered.filter { !$0.isRegistered }
    }

    private var filtered: [Entry] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.contact.displayName.localizedCaseInsensitiveContains(query) || $0.contact.phoneE164.contains(query.filter(\.isNumber)) && !query.filter(\.isNumber).isEmpty }
    }

    func requestAccess() async {
        do {
            let granted = try await contactSource.requestAccess()
            permission = granted ? .granted : .denied
        } catch {
            permission = ContactPickerViewModel.permission(for: contactSource.authorizationStatus)
        }
        if permission == .granted {
            await load()
        }
    }

    func load() async {
        guard permission == .granted, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let contacts = try await contactSource.fetchUKPhones()
            let registered = try await directory.lookup(hashes: contacts.map(\.hash))
            let byHash = Dictionary(registered.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
            entries = contacts
                .map { Entry(contact: $0, registered: byHash[$0.hash]) }
                .sorted { $0.contact.displayName.localizedCaseInsensitiveCompare($1.contact.displayName) == .orderedAscending }
            error = nil
            hasLoaded = true
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
        if invite == nil, entries.contains(where: { !$0.isRegistered }) {
            await loadInvite()
        }
    }

    /// Failure is quiet: the Invite buttons stay disabled and the next load tries again.
    func loadInvite() async {
        invite = try? await api.send(API.invite())
    }

    static func permission(for status: CNAuthorizationStatus) -> Permission {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        // iOS 18 adds "limited" access, which still allows reading the contacts the user shared.
        @unknown default: return .granted
        }
    }
}
