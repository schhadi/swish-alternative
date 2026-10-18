import SwiftUI

/// Layout shared by every onboarding step: big title, one-line explanation, content, footer pinned above the keyboard.
struct OnboardingPage<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.quidTitle)
                        .foregroundStyle(Color.quidInk)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.quidBody)
                        .foregroundStyle(Color.quidMuted)
                }
                content()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.quidBackground)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                footer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color.quidBackground)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
