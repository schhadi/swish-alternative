import SwiftUI

/// White card on the app background. Radius 20, no shadow.
struct QuidCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// One-pixel hairline, used between rows inside cards.
struct QuidDivider: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.quidHairline)
            .frame(height: 1 / displayScale)
    }
}

/// Section title with an optional trailing text action ("See all").
struct QuidSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.quidTitle3)
                .foregroundStyle(Color.quidInk)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.quidSubheadline)
                    .tint(Color.quidAccentText)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Label/value row for receipts and detail screens.
struct DetailRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.quidSubheadline)
                .foregroundStyle(Color.quidMuted)
            Spacer(minLength: 12)
            Text(value)
                .font(monospaced ? .system(.subheadline, design: .monospaced).weight(.semibold) : .quidSubheadline)
                .foregroundStyle(Color.quidInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
