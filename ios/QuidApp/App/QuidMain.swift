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
                .preferredColorScheme(Self.forcedColorScheme)
        }
    }

    /// `-dark-mode` or `-light-mode` at launch fixes the appearance (the accessibility audit UI tests use them).
    private static var forcedColorScheme: ColorScheme? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-dark-mode") { return .dark }
        if arguments.contains("-light-mode") { return .light }
        return nil
    }
}
