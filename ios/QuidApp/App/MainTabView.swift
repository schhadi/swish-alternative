import SwiftUI

enum AppTab: Hashable {
    case home, activity, collect, me
}

/// Home · Activity · Collect · Me
struct MainTabView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(api: appEnvironment.api, showActivity: { selectedTab = .activity })
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            ActivityView(api: appEnvironment.api)
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.activity)

            CollectView(api: appEnvironment.api)
                .tabItem { Label("Collect", systemImage: "person.3.fill") }
                .tag(AppTab.collect)

            MeView(api: appEnvironment.api)
                .tabItem { Label("Me", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.me)
        }
    }
}
