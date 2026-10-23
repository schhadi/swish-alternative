import SwiftUI

/// Title, amount each, due date and the list of people; then the new collection's treasurer view.
struct CreateCollectionView: View {
    @State private var viewModel: CreateCollectionViewModel
    @State private var picker: ContactPickerViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?
    let onCreated: (CollectionDetailDTO) async -> Void

    private enum Field: Hashable {
        case title, amount, name
    }

    init(environment: AppEnvironment, organisation: OrganisationDTO, onCreated: @escaping (CollectionDetailDTO) async -> Void) {
        _viewModel = State(initialValue: CreateCollectionViewModel(environment: environment, organisation: organisation))
        _picker = State(initialValue: ContactPickerViewModel(contactSource: environment.contactSource, api: environment.api))
        self.onCreated = onCreated
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            form
                .navigationDestination(for: CreateCollectionViewModel.Step.self) { _ in
                    ContactPickerView(
                        viewModel: picker,
                        isSelected: { viewModel.isSelected($0) },
                        onToggle: { viewModel.toggle($0) }
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { viewModel.path.removeAll() }
                                .font(.quidSubheadline)
                                .accessibilityIdentifier("collection.people.done")
                        }
                    }
                }
        }
        .tint(Color.quidAccentText)
        .onChange(of: viewModel.created) {
            guard let created = viewModel.created else { return }
            Task {
                await onCreated(created)
                dismiss()
            }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("For \(viewModel.organisation.name)")
                    .font(.quidSubheadline)
                    .foregroundStyle(Color.quidMuted)
                QuidFieldGroup(label: "What's it for?", trailing: "\(viewModel.title.count)/\(CreateCollectionViewModel.titleMaxLength)") {
                    TextField("Trip deposit", text: $viewModel.title)
                        .focused($focus, equals: .title)
                        .submitLabel(.next)
                        .quidField(isHighlighted: focus == .title)
                        .accessibilityIdentifier("collection.title")
                }
                QuidFieldGroup(label: "Amount each") {
                    HStack(spacing: 4) {
                        Text("£")
                            .font(.quidHeadline)
                            .foregroundStyle(Color.quidMuted)
                        AmountTextField(initialText: viewModel.amountText, placeholder: "30", alignment: .leading) { viewModel.setAmountText($0) }
                            .focused($focus, equals: .amount)
                            .accessibilityLabel("Amount each")
                            .accessibilityIdentifier("collection.amount")
                    }
                    .quidField(isHighlighted: focus == .amount)
                }
                if let problem = viewModel.amountProblem {
                    QuidErrorLine(message: problem)
                }
                VStack(spacing: 0) {
                    Toggle("Due date", isOn: $viewModel.hasDueDate)
                        .font(.quidHeadline)
                        .tint(Color.quidAccent)
                        .frame(minHeight: 52)
                    if viewModel.hasDueDate {
                        DatePicker("Due", selection: $viewModel.dueDate, in: Date()..., displayedComponents: .date)
                            .font(.quidBody)
                            .frame(minHeight: 52)
                            .accessibilityIdentifier("collection.dueDate")
                    }
                }
                .padding(.horizontal, 16)
                .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.quidHairline, lineWidth: 1))

                peopleSection

                if let error = viewModel.error {
                    QuidErrorLine(message: error.userMessage)
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.quidBackground)
        .safeAreaInset(edge: .bottom) {
            QuidButton(title: viewModel.submitTitle, isLoading: viewModel.isSubmitting) {
                focus = nil
                Task { await viewModel.submit() }
            }
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("collection.create")
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.quidBackground)
        }
        .navigationTitle("New collection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
                    .font(.quidSubheadline)
                    .accessibilityIdentifier("collection.cancel")
            }
        }
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuidSectionHeader(title: viewModel.members.isEmpty ? "Who should pay" : "Who should pay · \(viewModel.members.count)", size: .small)
            Text("Add people so you can see who has paid. Anyone with the link can pay too.")
                .font(.quidFootnote)
                .foregroundStyle(Color.quidMuted)
            QuidButton(title: "Add people on Quid", systemImage: "person.crop.circle.badge.plus", style: .secondary) {
                focus = nil
                viewModel.path.append(.people)
            }
            .accessibilityIdentifier("collection.addFromContacts")
            HStack(spacing: 10) {
                TextField("Add someone by name", text: $viewModel.newName)
                    .focused($focus, equals: .name)
                    .submitLabel(.done)
                    .onSubmit { viewModel.addName() }
                    .quidField(isHighlighted: focus == .name)
                    .accessibilityIdentifier("collection.newName")
                QuidPillButton(title: "Add", style: .neutral) { viewModel.addName() }
                    .disabled(viewModel.newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("collection.addName")
            }
            if let message = viewModel.memberMessage {
                QuidErrorLine(message: message)
            }
            if !viewModel.members.isEmpty {
                QuidCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.members.enumerated()), id: \.element.id) { index, member in
                            HStack(spacing: 12) {
                                Avatar(name: member.displayName, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.displayName)
                                        .font(.quidHeadline)
                                        .foregroundStyle(Color.quidInk)
                                        .quidLineLimit(1)
                                    Text(member.userId == nil ? "Pays from the link" : "On Quid")
                                        .font(.quidFootnote)
                                        .foregroundStyle(Color.quidMuted)
                                }
                                Spacer(minLength: 8)
                                Button {
                                    viewModel.remove(member)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(Color.quidMuted)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(member.displayName)")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            if index < viewModel.members.count - 1 {
                                QuidDivider().padding(.leading, 64)
                            }
                        }
                    }
                }
                if viewModel.amountMinor > 0 {
                    Text("\(viewModel.target.formatted(compact: true)) in total from \(viewModel.members.count) \(viewModel.members.count == 1 ? "person" : "people")")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
                }
            }
        }
    }
}
