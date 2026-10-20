import Contacts
import Foundation

/// One phone number from the address book, already normalised and hashed.
struct ContactPhone: Identifiable, Hashable, Sendable {
    let contactId: String
    let displayName: String
    let phoneE164: String
    let hash: String

    var id: String { "\(contactId):\(phoneE164)" }
}

/// Reads the address book. The system permission prompt is only ever triggered from the first Pay tap (Phase 2);
/// Phase 1 ships the explainer screen and this reader.
final class ContactsService {
    private let store = CNContactStore()

    var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    func requestAccess() async throws -> Bool {
        try await store.requestAccess(for: .contacts)
    }

    /// Every UK number in the address book, deduplicated by number, with the client hash ready for lookup.
    /// Runs off the main actor: a large address book must not freeze the picker.
    func fetchUKPhones() async throws -> [ContactPhone] {
        let store = store
        return try await Task.detached(priority: .userInitiated) {
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName
            var seen = Set<String>()
            var result: [ContactPhone] = []
            try store.enumerateContacts(with: request) { contact, _ in
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                guard !name.isEmpty else { return }
                for number in contact.phoneNumbers {
                    guard let e164 = UKPhone.normalise(number.value.stringValue), !seen.contains(e164) else { continue }
                    seen.insert(e164)
                    result.append(ContactPhone(contactId: contact.identifier, displayName: name, phoneE164: e164, hash: PhoneHasher.clientHash(e164)))
                }
            }
            return result
        }.value
    }
}
