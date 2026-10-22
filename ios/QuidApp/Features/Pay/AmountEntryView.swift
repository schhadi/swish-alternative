import SwiftUI

/// Big amount, keypad, quick pills, reference, "Pay from" row and the one button that starts the payment.
struct AmountEntryView: View {
    @Bindable var viewModel: PayViewModel
    @FocusState private var referenceFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    amount
                    // Right under the amount, so it is in view on small phones while the keypad stays put.
                    if let message = viewModel.inlineMessage {
                        QuidErrorLine(message: message)
                            .padding(.horizontal, 4)
                    }
                    if viewModel.isPayingRequest {
                        requestDetails
                    } else {
                        quickAmounts
                        referenceField
                    }
                    payFromRow
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            if !referenceFocused && !viewModel.isPayingRequest {
                AmountKeypad { key in viewModel.press(key) }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Color.quidBackground)
        .safeAreaInset(edge: .bottom) {
            QuidButton(title: viewModel.payButtonTitle, systemImage: "arrow.up.right", isLoading: viewModel.isSubmitting || viewModel.isAuthorising) {
                referenceFocused = false
                Task { await viewModel.submit() }
            }
            .disabled(!viewModel.canPay)
            .accessibilityIdentifier("pay.submit")
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(Color.quidBackground)
        }
        .navigationTitle(viewModel.isPayingRequest ? "Pay request" : "Pay")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeOut(duration: 0.2), value: referenceFocused)
        .onChange(of: viewModel.inlineMessage) {
            guard let message = viewModel.inlineMessage else { return }
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            if let target = viewModel.target {
                Avatar(name: target.displayName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("To \(target.displayName)")
                        .font(.quidHeadline)
                        .foregroundStyle(Color.quidInk)
                    if let request = viewModel.request {
                        Text("Asked you for \(Money(minor: request.amountMinor).formatted())")
                            .font(.quidFootnote)
                            .foregroundStyle(Color.quidMuted)
                    } else if let bank = target.bankName {
                        Text("\(bank) · verified with their bank")
                            .font(.quidFootnote)
                            .foregroundStyle(Color.quidMuted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var amount: some View {
        Text(viewModel.amountDisplay)
            .font(.quid(.extrabold, size: 56, relativeTo: .largeTitle))
            .tracking(-2)
            .foregroundStyle(viewModel.amountMinor == 0 ? Color.quidMuted : Color.quidInk)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, minHeight: 80)
            .contentTransition(.numericText())
            .animation(.easeOut(duration: 0.12), value: viewModel.amountDisplay)
            .accessibilityLabel("Amount")
            .accessibilityValue(Money(minor: viewModel.amountMinor).formatted())
            .accessibilityIdentifier("pay.amount")
    }

    private var quickAmounts: some View {
        HStack(spacing: 10) {
            ForEach(PayViewModel.quickAmountsMinor, id: \.self) { minor in
                Button {
                    viewModel.setQuickAmount(minor)
                } label: {
                    Text(Money(minor: minor).formatted(compact: true))
                        .font(.quidSubheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(viewModel.amountMinor == minor ? Color.quidOnAccent : Color.quidInk)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(viewModel.amountMinor == minor ? Color.quidAccent : Color.quidSurfaceSecondary, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pay.quick.\(minor)")
            }
        }
    }

    private var referenceField: some View {
        QuidFieldGroup(label: "Reference", trailing: "\(viewModel.reference.count)/\(PayViewModel.referenceMaxLength)") {
            TextField("What's it for?", text: $viewModel.reference)
                .focused($referenceFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .quidField(isHighlighted: referenceFocused)
                .accessibilityLabel("Reference, shows on both bank statements")
                .accessibilityIdentifier("pay.reference")
        }
    }

    /// Paying a request: what it is for and the reference it sets, neither of which can be changed here.
    @ViewBuilder
    private var requestDetails: some View {
        if let request = viewModel.request {
            QuidCard(padding: 0) {
                VStack(spacing: 0) {
                    DetailRow(label: "For", value: request.title)
                    if let note = request.note, !note.isEmpty {
                        QuidDivider().padding(.leading, 16)
                        DetailRow(label: "Note", value: note)
                    }
                    QuidDivider().padding(.leading, 16)
                    DetailRow(label: "Reference", value: request.reference)
                    QuidDivider().padding(.leading, 16)
                    DetailRow(label: "Expires", value: request.expiresAt.formatted(.dateTime.day().month(.abbreviated)))
                }
            }
            .accessibilityIdentifier("pay.requestDetails")
        }
    }

    private var payFromRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.columns")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.quidAccentText)
                .frame(width: 36, height: 36)
                .background(Color.quidSuccessTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pay from")
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                Text(viewModel.myBankName ?? "Choose your bank when you pay")
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 56)
        .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.quidHairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// 0-9, decimal point and delete. Keys are 56pt tall and labelled for VoiceOver.
struct AmountKeypad: View {
    let onPress: (PayViewModel.KeypadKey) -> Void

    private let rows: [[PayViewModel.KeypadKey]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.point, .digit(0), .delete],
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            onPress(key)
                        } label: {
                            keyLabel(key)
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(KeypadButtonStyle())
                        .accessibilityLabel(accessibilityLabel(key))
                        .accessibilityIdentifier("pay.key.\(identifier(key))")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Amount keypad")
    }

    @ViewBuilder
    private func keyLabel(_ key: PayViewModel.KeypadKey) -> some View {
        switch key {
        case .digit(let digit):
            Text(String(digit)).font(.quid(.bold, size: 26, relativeTo: .title2))
        case .point:
            Text(".").font(.quid(.bold, size: 26, relativeTo: .title2))
        case .delete:
            Image(systemName: "delete.left").font(.title2.weight(.semibold))
        }
    }

    private func accessibilityLabel(_ key: PayViewModel.KeypadKey) -> String {
        switch key {
        case .digit(let digit): return String(digit)
        case .point: return "Decimal point"
        case .delete: return "Delete"
        }
    }

    private func identifier(_ key: PayViewModel.KeypadKey) -> String {
        switch key {
        case .digit(let digit): return String(digit)
        case .point: return "point"
        case .delete: return "delete"
        }
    }
}

private struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.quidInk)
            .background(configuration.isPressed ? Color.quidSurfaceSecondary : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
