import Foundation
import Observation

@MainActor
@Observable
final class MeViewModel {
    private(set) var me: MeDTO?
    private(set) var error: AppError?
    private(set) var isLoading = false
    private(set) var isDeleting = false

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            me = try await api.send(API.me())
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    /// Hard-deletes bank details and phone hash server-side. Returns true when the session should end.
    func deleteAccount() async -> Bool {
        isDeleting = true
        defer { isDeleting = false }
        do {
            _ = try await api.send(API.deleteAccount())
            return true
        } catch let appError as AppError {
            error = appError
            return false
        } catch {
            self.error = .unknown(error.localizedDescription)
            return false
        }
    }

    /// "+447700900001" -> "+44 7700 900001"
    static func formattedPhone(_ e164: String?) -> String {
        guard let e164 else { return "" }
        guard e164.hasPrefix("+44"), e164.count == 13 else { return e164 }
        let digits = e164.dropFirst(3)
        return "+44 \(digits.prefix(4)) \(digits.dropFirst(4))"
    }
}
