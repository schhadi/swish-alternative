import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Screen: Equatable {
        case welcome, onboarding, loadingProfile, profileError, main
    }

    private var screen: Screen {
        if appEnvironment.onboardingInProgress { return .onboarding }
        if !appEnvironment.session.isSignedIn { return .welcome }
        if appEnvironment.profile != nil {
            return appEnvironment.pendingOnboardingStep == nil ? .main : .onboarding
        }
        if appEnvironment.profileError != nil { return .profileError }
        return .loadingProfile
    }

    var body: some View {
        Group {
            switch screen {
            case .welcome:
                WelcomeView()
            case .onboarding:
                OnboardingFlowView(environment: appEnvironment)
            case .loadingProfile:
                LoadingView()
                    .background(Color.quidBackground)
            case .profileError:
                profileErrorView
            case .main:
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: screen)
        .task(id: appEnvironment.session.token) {
            if appEnvironment.session.isSignedIn, !appEnvironment.hasLoadedProfile {
                await appEnvironment.loadProfile()
            }
        }
        // Appearance proxies are static: re-apply so navigation bars created from now on use the new text size.
        // Existing bars keep their size until they are recreated; see docs/DECISIONS.md #19.
        .onChange(of: dynamicTypeSize) {
            QuidAppearance.configure()
        }
    }

    private var profileErrorView: some View {
        VStack(spacing: 16) {
            Spacer()
            if let error = appEnvironment.profileError {
                ErrorStateView(error: error) { await appEnvironment.loadProfile() }
            }
            QuidButton(title: "Sign out", style: .secondary) {
                Task { await appEnvironment.signOut() }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.quidBackground)
    }
}
