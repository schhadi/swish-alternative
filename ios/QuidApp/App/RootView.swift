import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if appEnvironment.session.isSignedIn {
                MainTabView()
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appEnvironment.session.isSignedIn)
        // Appearance proxies are static: re-apply so navigation bars created from now on use the new text size.
        // Existing bars keep their size until they are recreated; see docs/DECISIONS.md #19.
        .onChange(of: dynamicTypeSize) {
            QuidAppearance.configure()
        }
    }
}
