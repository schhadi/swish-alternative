import SwiftUI

struct DisplayNameView: View {
    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var isFocused: Bool

    var body: some View {
        OnboardingPage(
            title: "What should we call you?",
            subtitle: "Friends see this name when you pay or request money, so use the one they know."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                QuidFieldGroup(label: "Your name") {
                    TextField("Sam Okafor", text: $viewModel.displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                        .submitLabel(.continue)
                        .onSubmit { Task { await viewModel.submitName() } }
                        .quidField(isHighlighted: isFocused)
                        .accessibilityLabel("Your name")
                        .accessibilityIdentifier("onboarding.name")
                }
                if let error = viewModel.error {
                    QuidErrorLine(message: error.userMessage)
                }
            }
        } footer: {
            QuidButton(title: "Continue", isLoading: viewModel.isSubmitting) {
                Task { await viewModel.submitName() }
            }
            .disabled(!viewModel.nameIsValid)
            .accessibilityIdentifier("onboarding.nameContinue")
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { isFocused = true }
    }
}
