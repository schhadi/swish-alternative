import SwiftUI

/// Sort code, account number, name on the account and the bank. Used in onboarding and from Home / Me.
struct BankAccountFormView: View {
    /// onboarding: first link with a skip; link: first link from Home or Me; change: replacing an existing account.
    enum Mode {
        case onboarding, link, change
    }

    @Bindable var viewModel: BankLinkViewModel
    let mode: Mode
    let onSubmit: () async -> Void
    var onSkip: (() -> Void)? = nil

    @State private var showProviderPicker = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case sortCode, accountNumber, name
    }

    var body: some View {
        OnboardingPage(
            title: mode == .change ? "Change your bank account" : "Link your bank account",
            subtitle: "The account you'll receive money into. We confirm the name with your bank before saving anything."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                QuidFieldGroup(label: "Your bank") {
                    Button {
                        showProviderPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            ProviderTile(name: viewModel.selectedProvider?.displayName)
                            Text(viewModel.selectedProvider?.displayName ?? "Choose your bank")
                                .font(.quidBody)
                                .foregroundStyle(viewModel.selectedProvider == nil ? Color.quidMuted : Color.quidInk)
                            Spacer()
                            QuidChevron()
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: 56)
                        .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.quidHairline, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Your bank, \(viewModel.selectedProvider?.displayName ?? "not chosen")")
                    .accessibilityIdentifier("bank.provider")
                }

                QuidFieldGroup(label: "Sort code") {
                    TextField("00-00-00", text: sortCodeBinding)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .sortCode)
                        .quidField(isHighlighted: focusedField == .sortCode)
                        .accessibilityLabel("Sort code")
                        .accessibilityIdentifier("bank.sortCode")
                }

                QuidFieldGroup(label: "Account number", trailing: "\(viewModel.accountNumber.count)/8") {
                    TextField("12345678", text: $viewModel.accountNumber)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .accountNumber)
                        .quidField(isHighlighted: focusedField == .accountNumber)
                        .accessibilityLabel("Account number")
                        .accessibilityIdentifier("bank.accountNumber")
                }

                QuidFieldGroup(label: "Name on the account") {
                    TextField("Exactly as your bank has it", text: $viewModel.accountHolderName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .quidField(isHighlighted: focusedField == .name)
                        .accessibilityLabel("Name on the account")
                        .accessibilityIdentifier("bank.name")
                }

                if let error = viewModel.error {
                    QuidErrorLine(message: error.userMessage)
                }

                Text("Your details are encrypted and only used to send money to you. Nobody, including other Quid users, can see them.")
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
            }
        } footer: {
            QuidButton(title: "Verify with your bank", systemImage: "checkmark.shield", isLoading: viewModel.isSubmitting) {
                Task { await onSubmit() }
            }
            .disabled(!viewModel.isValid)
            .accessibilityIdentifier("bank.verify")
            if mode == .onboarding, let onSkip {
                // Frame and hit shape inside the label so the whole 44pt row is tappable.
                Button {
                    onSkip()
                } label: {
                    Text("I'll do this later")
                        .font(.quidSubheadline)
                        .foregroundStyle(Color.quidAccentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bank.skip")
            }
        }
        .sheet(isPresented: $showProviderPicker) {
            ProviderPickerSheet(viewModel: viewModel)
        }
        .task { await viewModel.loadProviders() }
    }

    /// Shows 00-00-00 while the model keeps digits only.
    private var sortCodeBinding: Binding<String> {
        Binding(
            get: { viewModel.formattedSortCode },
            set: { viewModel.sortCode = $0 }
        )
    }
}

/// Initials tile standing in for a bank logo until Phase 2 brings real ones.
struct ProviderTile: View {
    let name: String?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(name == nil ? Color.quidSurfaceSecondary : Color.quidSuccessTint)
            if let name {
                Text(Avatar.initials(for: name))
                    .font(.quid(.bold, size: 12, relativeTo: .caption))
                    .foregroundStyle(Color.quidAccentText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            } else {
                Image(systemName: "building.columns")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.quidMuted)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }
}

/// Searchable list of banks. Choosing one preselects it when the payer authorises in Phase 2.
struct ProviderPickerSheet: View {
    @Bindable var viewModel: BankLinkViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [ProviderDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return viewModel.providers }
        return viewModel.providers.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoadingProviders && viewModel.providers.isEmpty {
                    LoadingView()
                } else if let error = viewModel.providersError, viewModel.providers.isEmpty {
                    ErrorStateView(error: error) { await viewModel.loadProviders() }
                        .padding(16)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if filtered.isEmpty {
                                EmptyStateView(systemImage: "magnifyingglass", title: "No banks match", message: "Try a shorter name, or continue without choosing one.")
                            } else {
                                QuidCard(padding: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, provider in
                                            Button {
                                                viewModel.selectedProvider = provider
                                                dismiss()
                                            } label: {
                                                HStack(spacing: 12) {
                                                    ProviderTile(name: provider.displayName)
                                                    Text(provider.displayName)
                                                        .font(.quidBody)
                                                        .foregroundStyle(Color.quidInk)
                                                    Spacer()
                                                    if provider.id == viewModel.selectedProvider?.id {
                                                        Image(systemName: "checkmark")
                                                            .font(.system(size: 15, weight: .bold))
                                                            .foregroundStyle(Color.quidAccentText)
                                                    }
                                                }
                                                .padding(.horizontal, 16)
                                                .frame(minHeight: 52)
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("bank.provider.\(provider.id)")
                                            if index < filtered.count - 1 {
                                                QuidDivider().padding(.leading, 60)
                                            }
                                        }
                                    }
                                }
                            }
                            Button {
                                viewModel.selectedProvider = nil
                                dismiss()
                            } label: {
                                Text("My bank isn't listed")
                                    .font(.quidSubheadline)
                                    .foregroundStyle(Color.quidAccentText)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                    }
                }
            }
            .background(Color.quidBackground)
            .navigationTitle("Your bank")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Search banks")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.quidSubheadline)
                }
            }
        }
        .presentationDetents([.large])
    }
}
