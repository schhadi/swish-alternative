import SwiftUI

/// Preview-only catalogue of the design system. Open this file's canvas in Xcode to check light and dark.
struct DesignSystemGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Quid design system")
                    .font(.quidLargeTitle)
                    .foregroundStyle(Color.quidInk)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Title · ExtraBold 28").font(.quidTitle)
                    Text("Title 2 · Bold 22").font(.quidTitle2)
                    Text("Headline · Bold 17").font(.quidHeadline)
                    Text("Body · SemiBold 17").font(.quidBody)
                    Text("Footnote · SemiBold 13").font(.quidFootnote).foregroundStyle(Color.quidMuted)
                }
                .foregroundStyle(Color.quidInk)

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    AmountText(money: Money(minor: 1_250_00), style: .hero)
                    AmountText(money: Money(minor: -3_50), style: .inline)
                    AmountText(money: Money(minor: 6_00), style: .inline, explicitPlus: true, color: .quidSuccessText)
                }

                HStack(spacing: 8) {
                    StatusPill(text: "Paid", tone: .success)
                    StatusPill(text: "Pending", tone: .pending)
                    StatusPill(text: "Failed", tone: .failure)
                    StatusPill(text: "Treasurer", tone: .neutral)
                }

                HStack(spacing: 12) {
                    ForEach(["Sam Okafor", "Priya Patel", "Tom Whitfield", "Amara Osei", "Jonas Berg", "Leila Haddad"], id: \.self) { name in
                        Avatar(name: name, size: 44)
                    }
                }

                QuidButton(title: "Pay £12 with Monzo", systemImage: "faceid") {}
                QuidButton(title: "Request", style: .secondary) {}
                QuidButton(title: "Delete account", style: .destructive) {}
                QuidButton(title: "Working", isLoading: true) {}
                HStack {
                    QuidPillButton(title: "Nudge") {}
                    QuidPillButton(title: "Remind", style: .neutral) {}
                }

                QuidSectionHeader(title: "Section header", actionTitle: "See all", action: {})
                QuidSectionHeader(title: "Small header", size: .small)
                QuidCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Card").font(.quidHeadline).foregroundStyle(Color.quidInk)
                        Text("Radius 20, white on the app background, hairline dividers inside.")
                            .font(.quidSubheadline)
                            .foregroundStyle(Color.quidMuted)
                        QuidDivider()
                        DetailRow(label: "Reference", value: "From Sam")
                    }
                }

                EmptyStateView(systemImage: "clock", title: "Empty state", message: "Explains what will show up here and how.")
                ErrorStateView(error: .offline) {}
            }
            .padding(16)
        }
        .background(Color.quidBackground)
    }
}

#Preview("Design system · light") {
    DesignSystemGallery()
}

#Preview("Design system · dark") {
    DesignSystemGallery()
        .preferredColorScheme(.dark)
}
