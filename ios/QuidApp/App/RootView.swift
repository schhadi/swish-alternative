import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        Group {
            if appEnvironment.session.isSignedIn {
                MainTabView()
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appEnvironment.session.isSignedIn)
    }
}
