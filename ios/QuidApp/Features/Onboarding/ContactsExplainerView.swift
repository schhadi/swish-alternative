import SwiftUI

/// Explains how contacts are used. The system permission prompt itself is only shown on the first Pay tap (Phase 2).
struct ContactsExplainerView: View {
    let onContinue: () async -> Void
    @State private var isFinishing = false

    var body: some View {
        OnboardingPage(
            title: "Find friends on Quid",
            subtitle: "To pay someone you just pick them from your contacts. Here's how we keep that private."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ExplainerRow(systemImage: "iphone", text: "Your contacts stay on your phone. We never upload your address book.")
                ExplainerRow(systemImage: "number", text: "To see who's on Quid we send scrambled versions of numbers (hashes), never the numbers themselves.")
                ExplainerRow(systemImage: "hand.raised", text: "We'll ask for permission the first time you tap Pay. You can say no and still get paid.")
            }
        } footer: {
            QuidButton(title: "Continue", isLoading: isFinishing) {
                Task {
                    isFinishing = true
                    await onContinue()
                    isFinishing = false
                }
            }
            .accessibilityIdentifier("onboarding.finish")
        }
    }
}

private struct ExplainerRow: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
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
        .accessibilityElement(children: .combine)
    }
}
