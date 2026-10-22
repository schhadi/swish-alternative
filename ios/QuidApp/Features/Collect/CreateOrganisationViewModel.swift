import Foundation
import Observation

/// Sets up an organisation and the account it collects into. The bank checks the name first, as for a personal
/// account: only a match creates it; a close match offers the bank's version of the name.
@MainActor
@Observable
final class CreateOrganisationViewModel {
    static let nameMaxLength = 60

    var name = "" {
        didSet {
            let clipped = String(name.prefix(CreateOrganisationViewModel.nameMaxLength))
            if clipped != name { name = clipped }
        }
    }
    var kind: OrgKind = .club
    /// Digits only; the view formats them as 00-00-00.
    var sortCode = "" {
        didSet {
            let cleaned = String(sortCode.filter(\.isNumber).prefix(6))
            if cleaned != sortCode { sortCode = cleaned }
        }
    }
    var accountNumber = "" {
        didSet {
            let cleaned = String(accountNumber.filter(\.isNumber).prefix(8))
            if cleaned != accountNumber { accountNumber = cleaned }
        }
    }
    var accountHolderName = ""
    var selectedProvider: ProviderDTO?

    private(set) var providers: [ProviderDTO] = []
    private(set) var isSubmitting = false
    private(set) var error: AppError?
    /// The last bank check that did not match. Cleared when the details change or on success.
    private(set) var result: CreateOrganisationResponseDTO?
    private(set) var created: OrganisationDTO?

    private let api: APIClient

    init(api: APIClient) {
        self.api = api
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedHolder: String { accountHolderName.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isValid: Bool {
        trimmedName.count >= 2 && sortCode.count == 6 && accountNumber.count == 8 && trimmedHolder.count >= 2 && trimmedHolder.count <= 70
    }

    var formattedSortCode: String {
        let digits = Array(sortCode)
        return stride(from: 0, to: digits.count, by: 2)
            .map { String(digits[$0..<min($0 + 2, digits.count)]) }
            .joined(separator: "-")
    }

    func loadProviders() async {
        guard providers.isEmpty else { return }
        providers = (try? await api.send(API.providers()).providers) ?? []
    }

    func submit() async {
        guard isValid, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let request = CreateOrganisationRequest(
                name: trimmedName,
                kind: kind,
                bankAccount: BankAccountRequest(sortCode: sortCode, accountNumber: accountNumber, accountHolderName: trimmedHolder, providerId: selectedProvider?.id)
            )
            let response = try await api.send(API.createOrganisation(request))
            error = nil
            if response.copStatus == .match, let organisation = response.organisation {
                result = nil
                created = organisation
            } else {
                result = response
            }
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    /// CLOSE_MATCH: take the bank's version of the name and check again.
    func acceptSuggestedName() async {
        guard let suggested = result?.suggestedAccountHolderName else { return }
        accountHolderName = suggested
        await submit()
    }

    func editAgain() {
        result = nil
        error = nil
    }
}
