import SwiftUI

/// Six-box code entry over a hidden text field, so SMS autofill and VoiceOver both work.
struct OTPCodeView: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        OnboardingPage(
            title: "Enter the code",
            subtitle: "We texted a 6-digit code to \(viewModel.maskedPhone)."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    TextField("", text: $viewModel.code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($isFocused)
                        .frame(width: 1, height: 1)
                        .opacity(0.02)
                        .accessibilityLabel("Verification code")
                        .accessibilityValue(viewModel.code.isEmpty ? "empty" : "\(viewModel.code.count) of 6 digits entered")
                        .accessibilityIdentifier("onboarding.code")
                    HStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { index in
                            CodeBox(
                                digit: digit(at: index),
                                isActive: isFocused && index == min(viewModel.code.count, 5),
                                isError: viewModel.error != nil && viewModel.code.isEmpty
                            )
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { isFocused = true }
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.isLocked {
                    QuidErrorLine(message: "Too many attempts. Request a new code to carry on.")
                } else if let error = viewModel.error {
                    QuidErrorLine(message: error.userMessage)
                }

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let availableAt = viewModel.resendAvailableAt, availableAt > context.date {
                        let seconds = Int(availableAt.timeIntervalSince(context.date).rounded(.up))
                        Text("Resend code in \(seconds)s")
                            .font(.quidSubheadline)
                            .foregroundStyle(Color.quidMuted)
                            .monospacedDigit()
                    } else {
                        Button {
                            Task { await viewModel.resendCode() }
                        } label: {
                            Text(viewModel.isLocked ? "Request a new code" : "Resend code")
                                .font(.quidSubheadline)
                                .foregroundStyle(Color.quidAccentText)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isSubmitting)
                        .accessibilityIdentifier("onboarding.resend")
                    }
                }
            }
        } footer: {
            QuidButton(title: "Continue", isLoading: viewModel.isSubmitting) {
                Task { await viewModel.submitCode() }
            }
            .disabled(viewModel.code.count != 6 || viewModel.isLocked)
            .accessibilityIdentifier("onboarding.continue")
        }
        .onAppear { isFocused = true }
        .onChange(of: viewModel.code) {
            if viewModel.code.count == 6, !viewModel.isSubmitting, !viewModel.isLocked {
                Task { await viewModel.submitCode() }
            }
        }
    }

    private func digit(at index: Int) -> String {
        let digits = Array(viewModel.code)
        return index < digits.count ? String(digits[index]) : ""
    }
}

private struct CodeBox: View {
    let digit: String
    let isActive: Bool
    let isError: Bool

    var body: some View {
        Text(digit)
            .font(.quid(.extrabold, size: 24, relativeTo: .title2))
            .foregroundStyle(Color.quidInk)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: isActive ? 2 : 1)
            )
            .animation(.easeOut(duration: 0.12), value: isActive)
    }

    private var borderColor: Color {
        if isError { return .quidFailureText }
        return isActive ? .quidAccentText : .quidHairline
    }
}
