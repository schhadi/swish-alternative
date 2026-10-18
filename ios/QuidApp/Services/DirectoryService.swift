import Foundation

/// A contact who is on Quid, joined with what the directory knows.
struct MatchedContact: Identifiable, Hashable, Sendable {
    let contact: ContactPhone
    let userId: String
    let registeredName: String

    var id: String { contact.id }
}

/// Asks the backend which contacts are registered. Sends client hashes only, in batches the server accepts.
struct DirectoryService {
    static let batchSize = 1000

    let api: APIClient

    func lookup(hashes: [String]) async throws -> [RegisteredContactDTO] {
        let unique = Array(Set(hashes)).sorted()
        var registered: [RegisteredContactDTO] = []
        var start = 0
        while start < unique.count {
            let end = min(start + DirectoryService.batchSize, unique.count)
            let batch = Array(unique[start..<end])
            registered += try await api.send(API.directoryLookup(hashes: batch)).registered
            start = end
        }
        return registered
    }

    /// Registered contacts first, by display name; unregistered ones are not returned here.
    func match(_ contacts: [ContactPhone]) async throws -> [MatchedContact] {
        let registered = try await lookup(hashes: contacts.map(\.hash))
        let byHash = Dictionary(registered.map { ($0.hash, $0) }, uniquingKeysWith: { first, _ in first })
        return contacts.compactMap { contact in
            guard let entry = byHash[contact.hash] else { return nil }
            return MatchedContact(contact: contact, userId: entry.userId, registeredName: entry.displayName)
        }
        .sorted { $0.contact.displayName.localizedCaseInsensitiveCompare($1.contact.displayName) == .orderedAscending }
    }
}
