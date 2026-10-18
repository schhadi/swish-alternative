import SwiftUI

/// Shown when there is no session. Phase 1 replaces "Get started" with the phone-number onboarding.
struct WelcomeView: View {
    @Environment(AppEnvironment.self) private var appEnvironment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 20) {
                Text("Quid")
                    .font(.quid(.extrabold, size: 44, relativeTo: .largeTitle))
                    .tracking(-2)
                    .foregroundStyle(Color.quidAccentText)
                Text("Pay anyone in the UK by phone number. Your bank moves the money; we never touch it.")
                    .font(.quidTitle3)
                    .foregroundStyle(Color.quidInk)
                VStack(alignment: .leading, spacing: 14) {
                    WelcomeFeatureRow(systemImage: "person.2", text: "Pick a friend from your contacts")
                    WelcomeFeatureRow(systemImage: "faceid", text: "Approve in your own bank's app")
                    WelcomeFeatureRow(systemImage: "person.3", text: "Collect for a club, society or flat")
                }
                .padding(.top, 4)
            }
            Spacer()
            VStack(spacing: 12) {
                QuidButton(title: "Get started") {}
                    .disabled(true)
                Text("Signing up with your phone number arrives in Phase 1.")
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                    .multilineTextAlignment(.center)
                QuidButton(title: "Explore the demo", style: .secondary) {
                    appEnvironment.enterDemoMode()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.quidBackground)
    }
}

private struct WelcomeFeatureRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.quidAccentText)
                .frame(width: 36, height: 36)
                .background(Color.quidSuccessTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            Text(text)
                .font(.quidBody)
                .foregroundStyle(Color.quidInk)
        }
    }
}

#Preview("Welcome") {
    WelcomeView()
        .environment(AppEnvironment.demo())
}
