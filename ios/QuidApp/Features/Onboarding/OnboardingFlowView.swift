import SwiftUI

/// Phone -> code -> name -> bank -> CoP result -> contacts explainer. Resumes at whatever step is still outstanding.
struct OnboardingFlowView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var viewModel: OnboardingViewModel

    init(environment: AppEnvironment) {
        _viewModel = State(initialValue: OnboardingViewModel(environment: environment))
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            stepView(viewModel.rootStep)
                .navigationDestination(for: OnboardingStep.self) { step in
                    stepView(step)
                }
        }
        .tint(Color.quidAccentText)
        // Keeps RootView on this flow while the session appears mid-way (after the code is verified).
        .onAppear { appEnvironment.startOnboarding() }
    }

    @ViewBuilder
    private func stepView(_ step: OnboardingStep) -> some View {
        switch step {
        case .phone:
            PhoneNumberView(viewModel: viewModel)
        case .code:
            OTPCodeView(viewModel: viewModel)
        case .name:
            DisplayNameView(viewModel: viewModel)
        case .bank:
            BankAccountFormView(
                viewModel: viewModel.bankLink,
                mode: .onboarding,
                onSubmit: { await viewModel.submitBank() },
                onSkip: { viewModel.skipBank() }
            )
            .navigationBarBackButtonHidden(true)
        case .copResult:
            CopResultView(
                bankLink: viewModel.bankLink,
                onContinue: { await viewModel.continueAfterBank() },
                onUseSuggested: { await viewModel.acceptSuggestedBankName() },
                onEdit: { viewModel.editBankDetails() },
                onSkip: { viewModel.skipBank() }
            )
            .navigationBarBackButtonHidden(true)
        case .contacts:
            ContactsExplainerView { await viewModel.finish() }
                .navigationBarBackButtonHidden(true)
        }
    }
}

#Preview("Onboarding") {
    OnboardingFlowView(environment: AppEnvironment.demo(signedIn: false))
        .environment(AppEnvironment.demo(signedIn: false))
}
