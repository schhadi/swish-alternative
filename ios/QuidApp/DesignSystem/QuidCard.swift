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

/// Section title with an optional trailing text action ("See all"). The action keeps a 44pt hit target.
struct QuidSectionHeader: View {
    enum Size {
        /// Manrope Bold 20 in ink — Home sections.
        case large
        /// Manrope SemiBold 13 in muted — day headers, settings groups.
        case small
    }

    let title: String
    var size: Size = .large
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center) {
            Text(title)
                .font(size == .large ? .quidTitle3 : .quidFootnote)
                .foregroundStyle(size == .large ? Color.quidInk : Color.quidMuted)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.quidSubheadline)
                        .foregroundStyle(Color.quidAccentText)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: size == .large ? 44 : 24)
        .padding(.horizontal, size == .small ? 4 : 0)
    }
}

/// Trailing disclosure indicator for rows that push a screen (Lists draw this for free; cards do not).
struct QuidChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.quidMuted.opacity(0.7))
            .accessibilityHidden(true)
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
