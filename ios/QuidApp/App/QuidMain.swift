import SwiftUI

// Named QuidMain (not QuidApp) so the type never shadows the module name in `QuidApp.Something` lookups.
@main
struct QuidMain: App {
    @State private var appEnvironment = AppEnvironment.bootstrap()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .tint(Color.quidAccent)
        }
    }
}
