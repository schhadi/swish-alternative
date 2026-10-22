import SwiftUI

/// Who is being asked, the bill (keypad) or each person's amount, an optional share for the user, and a title.
struct RequestAmountView: View {
    @Bindable var viewModel: RequestViewModel
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case title
        case person(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    Picker("How to split", selection: $viewModel.mode) {
                        ForEach(RequestViewModel.Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("request.mode")
                    switch viewModel.mode {
                    case .equal:
                        equalSection
                    case .custom:
                        customSection
                    }
                    if let message = viewModel.inlineMessage {
                        QuidErrorLine(message: message)
                            .padding(.horizontal, 4)
                    }
                    titleField
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            if viewModel.mode == .equal && focus == nil {
                AmountKeypad { key in viewModel.press(key) }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.quidBackground)
        .safeAreaInset(edge: .bottom) {
            QuidButton(title: viewModel.submitTitle, systemImage: "arrow.down.left", isLoading: viewModel.isSubmitting) {
                focus = nil
                Task { await viewModel.submit() }
            }
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("request.submit")
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Color.quidBackground)
        }
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeOut(duration: 0.2), value: focus)
        .animation(.easeOut(duration: 0.2), value: viewModel.mode)
        .onChange(of: viewModel.inlineMessage) {
            guard let message = viewModel.inlineMessage else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: -12) {
                ForEach(viewModel.people.prefix(3)) { person in
                    Avatar(name: person.displayName, size: 40)
                        .overlay(Circle().stroke(Color.quidBackground, lineWidth: 2))
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Asking \(viewModel.namesLine)")
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                Text(viewModel.people.count == 1 ? "1 person" : "\(viewModel.people.count) people")
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Equal

    private var equalSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("£" + (viewModel.totalText.isEmpty ? "0" : viewModel.totalText))
                    .font(.quid(.extrabold, size: 56, relativeTo: .largeTitle))
                    .tracking(-2)
                    .foregroundStyle(viewModel.enteredTotalMinor == 0 ? Color.quidMuted : Color.quidInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.12), value: viewModel.totalText)
                    .accessibilityLabel(viewModel.includeMe ? "Total bill" : "Total to ask for")
                    .accessibilityValue(Money(minor: viewModel.enteredTotalMinor).formatted())
                    .accessibilityIdentifier("request.total")
                Text(viewModel.summaryLine ?? (viewModel.includeMe ? "Enter the whole bill" : "Enter the total to ask for"))
                    .font(.quidSubheadline)
                    .foregroundStyle(Color.quidMuted)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("request.summary")
            }
            Toggle(isOn: $viewModel.includeMe) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Include me")
                        .font(.quidHeadline)
                        .foregroundStyle(Color.quidInk)
                    Text("You paid the bill and are paying a share too")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
                }
            }
            .tint(Color.quidAccent)
            .padding(.horizontal, 16)
            .frame(minHeight: 60)
            .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.quidHairline, lineWidth: 1))
            .accessibilityIdentifier("request.includeMe")
        }
    }

    // MARK: - Custom

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuidCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.people.enumerated()), id: \.element.id) { index, person in
                        HStack(spacing: 12) {
                            Avatar(name: person.displayName, size: 40)
                            Text(person.displayName)
                                .font(.quidHeadline)
                                .foregroundStyle(Color.quidInk)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            HStack(spacing: 2) {
                                Text("£")
                                    .font(.quidHeadline)
                                    .foregroundStyle(Color.quidMuted)
                                TextField("0.00", text: Binding(
                                    get: { viewModel.amountText(for: person.userId) },
                                    set: { viewModel.setAmountText($0, for: person.userId) }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.quidHeadline)
                                .focused($focus, equals: .person(person.userId))
                                .frame(minWidth: 72, maxWidth: 110)
                                .accessibilityLabel("Amount for \(person.displayName)")
                                .accessibilityIdentifier("request.amount.\(person.userId)")
                            }
                            .padding(.horizontal, 10)
                            .frame(minHeight: 44)
                            .background(Color.quidSurfaceSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        if index < viewModel.people.count - 1 {
                            QuidDivider().padding(.leading, 68)
                        }
                    }
                }
            }
            HStack {
                Text("Total")
                    .font(.quidSubheadline)
                    .foregroundStyle(Color.quidMuted)
                Spacer()
                Text(Money(minor: viewModel.requestedMinor).formatted())
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
            }
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Title

    private var titleField: some View {
        QuidFieldGroup(label: "What's it for?", trailing: "\(viewModel.title.count)/\(RequestViewModel.titleMaxLength)") {
            TextField("Pizza night", text: $viewModel.title)
                .focused($focus, equals: .title)
                .submitLabel(.done)
                .quidField(isHighlighted: focus == .title)
                .accessibilityLabel("What's it for? Shown to everyone you ask")
                .accessibilityIdentifier("request.title")
        }
    }
}
