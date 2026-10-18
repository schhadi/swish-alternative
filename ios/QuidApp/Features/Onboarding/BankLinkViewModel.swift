import Foundation
import Observation

/// Links the account the user receives into. Shared by onboarding and by "Change bank account" on the Me tab.
@MainActor
@Observable
final class BankLinkViewModel {
    /// Digits only; the view formats them as 00-00-00.
    var sortCode = "" {
        didSet {
            // Guarded self-assignment; see OnboardingViewModel.code and docs/DECISIONS.md #52.
            let cleaned = String(sortCode.filter(\.isNumber).prefix(6))
            if cleaned != sortCode { sortCode = cleaned }
        }
    }
    /// Digits only, 8 of them.
    var accountNumber = "" {
        didSet {
            let cleaned = String(accountNumber.filter(\.isNumber).prefix(8))
            if cleaned != accountNumber { accountNumber = cleaned }
        }
    }
    var accountHolderName = ""
    var selectedProvider: ProviderDTO?

    private(set) var providers: [ProviderDTO] = []
    private(set) var providersError: AppError?
    private(set) var isLoadingProviders = false
    private(set) var isSubmitting = false
    private(set) var error: AppError?
    /// The last Confirmation of Payee outcome. Cleared when the user edits the details again.
    private(set) var result: BankAccountLinkResponseDTO?

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    var trimmedName: String {
        accountHolderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        sortCode.count == 6 && accountNumber.count == 8 && trimmedName.count >= 2 && trimmedName.count <= 70
    }

    var formattedSortCode: String {
        let digits = Array(sortCode)
        return stride(from: 0, to: digits.count, by: 2)
            .map { String(digits[$0..<min($0 + 2, digits.count)]) }
            .joined(separator: "-")
    }

    func loadProviders() async {
        guard providers.isEmpty else { return }
        isLoadingProviders = true
        defer { isLoadingProviders = false }
        do {
            providers = try await api.send(API.providers()).providers
            providersError = nil
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            providersError = appError
        } catch {
            providersError = .unknown(error.localizedDescription)
        }
    }

    /// Runs Confirmation of Payee. Returns true when the backend answered (any CoP status); the answer is in `result`.
    @discardableResult
    func submit() async -> Bool {
        guard isValid, !isSubmitting else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let request = BankAccountRequest(
                sortCode: sortCode,
                accountNumber: accountNumber,
                accountHolderName: trimmedName,
                providerId: selectedProvider?.id
            )
            result = try await api.send(API.linkBankAccount(request))
            error = nil
            return true
        } catch is CancellationError {
            return false
        } catch let appError as AppError {
            error = appError
            return false
        } catch {
            self.error = .unknown(error.localizedDescription)
            return false
        }
    }

    /// CLOSE_MATCH: take the bank's version of the name and verify again.
    @discardableResult
    func acceptSuggestedName() async -> Bool {
        guard let suggested = result?.suggestedAccountHolderName else { return false }
        accountHolderName = suggested
        return await submit()
    }

    func editAgain() {
        result = nil
        error = nil
    }
}
