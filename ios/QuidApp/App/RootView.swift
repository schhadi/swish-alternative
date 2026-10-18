import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Bumped when the text size changes so navigation bars are recreated with re-scaled Manrope fonts.
    @State private var chromeGeneration = 0

    var body: some View {
        Group {
            if appEnvironment.session.isSignedIn {
                MainTabView()
                    .id(chromeGeneration)
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appEnvironment.session.isSignedIn)
        .onChange(of: dynamicTypeSize) {
            QuidAppearance.configure()
            chromeGeneration += 1
        }
    }
}
