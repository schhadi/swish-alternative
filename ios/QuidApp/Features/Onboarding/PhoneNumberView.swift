import SwiftUI

struct PhoneNumberView: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        OnboardingPage(
            title: "What's your number?",
            subtitle: "We'll text you a code to sign in. UK mobiles only for now."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                QuidFieldGroup(label: "Mobile number") {
                    TextField("07700 900123", text: $viewModel.phoneInput)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($isFocused)
                        .submitLabel(.send)
                        .onSubmit { Task { await viewModel.submitPhone() } }
                        .quidField(isHighlighted: isFocused)
                        .accessibilityLabel("Mobile number")
                        .accessibilityIdentifier("onboarding.phone")
                }
                if let error = viewModel.error {
                    QuidErrorLine(message: error.userMessage)
                }
            }
        } footer: {
            QuidButton(title: "Send code", isLoading: viewModel.isSubmitting) {
                Task { await viewModel.submitPhone() }
            }
            .disabled(!viewModel.phoneIsValid)
            .accessibilityIdentifier("onboarding.sendCode")
            Text(PhoneNumberView.legalNotice)
                .font(.quidFootnote)
                .foregroundStyle(Color.quidMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .toolbar {
            if viewModel.canCancel {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { viewModel.cancel() }
                        .font(.quidSubheadline)
                }
            }
        }
        .onAppear { isFocused = true }
    }

    /// Markdown links open the two documents in Safari; the link colour is the flow's tint.
    private static let legalNotice: AttributedString = {
        let markdown = "By continuing you agree to our [Terms of use](\(AppConfig.termsURL.absoluteString)) and [Privacy policy](\(AppConfig.privacyURL.absoluteString))."
        return (try? AttributedString(markdown: markdown)) ?? AttributedString("By continuing you agree to our Terms of use and Privacy policy.")
    }()
}
