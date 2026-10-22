import SwiftUI

/// Name, kind and the account an organisation collects into, checked with the bank before anything is created.
struct CreateOrganisationView: View {
    @State private var viewModel: CreateOrganisationViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    let onCreated: (OrganisationDTO) async -> Void

    private enum Field: Hashable {
        case name, holder, sortCode, accountNumber
    }

    init(api: APIClient, onCreated: @escaping (OrganisationDTO) async -> Void) {
        _viewModel = State(initialValue: CreateOrganisationViewModel(api: api))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Collect for a society, sports club or flat. Payments go straight into the organisation's account; Quid never holds the money.")
                        .font(.quidSubheadline)
                        .foregroundStyle(Color.quidMuted)
                    QuidFieldGroup(label: "Name", trailing: "\(viewModel.name.count)/\(CreateOrganisationViewModel.nameMaxLength)") {
                        TextField("SOAS Hockey Club", text: $viewModel.name)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .quidField(isHighlighted: focus == .name)
                            .accessibilityIdentifier("org.name")
                    }
                    Picker("Kind", selection: $viewModel.kind) {
                        ForEach(OrgKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("org.kind")

                    QuidSectionHeader(title: "Account it collects into", size: .small)
                    QuidFieldGroup(label: "Name on the account") {
                        TextField("As the bank has it", text: $viewModel.accountHolderName)
                            .focused($focus, equals: .holder)
                            .textContentType(.name)
                            .quidField(isHighlighted: focus == .holder)
                            .accessibilityIdentifier("org.holder")
                    }
                    HStack(alignment: .top, spacing: 12) {
                        QuidFieldGroup(label: "Sort code") {
                            TextField("00-00-00", text: Binding(get: { viewModel.formattedSortCode }, set: { viewModel.sortCode = $0 }))
                                .keyboardType(.numberPad)
                                .focused($focus, equals: .sortCode)
                                .quidField(isHighlighted: focus == .sortCode)
                                .accessibilityIdentifier("org.sortCode")
                        }
                        QuidFieldGroup(label: "Account number") {
                            TextField("8 digits", text: $viewModel.accountNumber)
                                .keyboardType(.numberPad)
                                .focused($focus, equals: .accountNumber)
                                .quidField(isHighlighted: focus == .accountNumber)
                                .accessibilityIdentifier("org.accountNumber")
                        }
                    }
                    if !viewModel.providers.isEmpty {
                        HStack {
                            Text("Bank")
                                .font(.quidSubheadline)
                                .foregroundStyle(Color.quidMuted)
                            Spacer()
                            Picker("Bank", selection: $viewModel.selectedProvider) {
                                Text("Choose").tag(ProviderDTO?.none)
                                ForEach(viewModel.providers) { provider in
                                    Text(provider.displayName).tag(Optional(provider))
                                }
                            }
                            .tint(Color.quidAccentText)
                        }
                    }
                    resultCard
                    if let error = viewModel.error {
                        QuidErrorLine(message: error.userMessage)
                    }
                    Text("We check the name with the bank so people paying in see who they're paying.")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.quidBackground)
            .safeAreaInset(edge: .bottom) {
                QuidButton(title: "Check and create", isLoading: viewModel.isSubmitting) {
                    focus = nil
                    Task { await viewModel.submit() }
                }
                .disabled(!viewModel.isValid)
                .accessibilityIdentifier("org.create")
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.quidBackground)
            }
            .navigationTitle("New organisation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.quidSubheadline)
                }
            }
            .task { await viewModel.loadProviders() }
            .onChange(of: viewModel.sortCode) { viewModel.editAgain() }
            .onChange(of: viewModel.accountNumber) { viewModel.editAgain() }
            .onChange(of: viewModel.created) {
                guard let created = viewModel.created else { return }
                Task {
                    await onCreated(created)
                    dismiss()
                }
            }
        }
        .tint(Color.quidAccentText)
    }

    @ViewBuilder
    private var resultCard: some View {
        if let result = viewModel.result {
            switch result.copStatus {
            case .closeMatch:
                VStack(alignment: .leading, spacing: 12) {
                    Text("The bank has this account as \u{201C}\(result.suggestedAccountHolderName ?? "")\u{201D}.")
                        .font(.quidHeadline)
                        .foregroundStyle(Color.quidPendingText)
                    Text("Use the bank's version so people paying in see the right name.")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidPendingText)
                    QuidButton(title: "Use this name", style: .secondary, isLoading: viewModel.isSubmitting) {
                        Task { await viewModel.acceptSuggestedName() }
                    }
                    .accessibilityIdentifier("org.useSuggested")
                }
                .padding(16)
                .background(Color.quidPendingTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            case .noMatch, .unchecked:
                QuidErrorLine(message: "The name doesn't match this account. Check the details with whoever runs the account.")
            case .match:
                EmptyView()
            }
        }
    }
}
