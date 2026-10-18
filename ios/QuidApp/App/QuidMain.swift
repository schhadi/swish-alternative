import SwiftUI

// Named QuidMain (not QuidApp) so the type never shadows the module name in `QuidApp.Something` lookups.
@main
struct QuidMain: App {
    @State private var appEnvironment = AppEnvironment.bootstrap()

    init() {
        QuidAppearance.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                // Appearance-aware accent for system chrome (tab bar, back buttons, toggles) so dark mode keeps contrast.
                .tint(Color.quidAccentText)
        }
    }
}
