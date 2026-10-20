import Contacts
import Foundation

/// Where the contact picker reads the address book from: the real one, or canned contacts in MockMode and tests.
protocol ContactSource: AnyObject {
    var authorizationStatus: CNAuthorizationStatus { get }
    func requestAccess() async throws -> Bool
    func fetchUKPhones() async throws -> [ContactPhone]
}

extension ContactsService: ContactSource {}

/// Demo contacts: the four people in MockFixtures.people plus two who are not on Quid. No permission prompt.
final class MockContactSource: ContactSource {
    var authorizationStatus: CNAuthorizationStatus = .authorized
    var accessGranted = true

    static let contacts: [(name: String, phone: String)] = [
        ("Priya Patel", "+447700900002"),
        ("Tom Whitfield", "+447700900003"),
        ("Amara Osei", "+447700900004"),
        ("Jonas Berg", "+447700900005"),
        ("Nadia Hussain", "+447700900010"),
        ("Ben Carter", "+447700900011"),
    ]

    func requestAccess() async throws -> Bool {
        authorizationStatus = accessGranted ? .authorized : .denied
        return accessGranted
    }

    func fetchUKPhones() async throws -> [ContactPhone] {
        MockContactSource.contacts.enumerated().map { index, entry in
            ContactPhone(contactId: "mock-\(index)", displayName: entry.name, phoneE164: entry.phone, hash: PhoneHasher.clientHash(entry.phone))
        }
    }
}
