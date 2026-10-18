import SwiftUI

/// Text-field chrome: 56pt, surface fill, hairline border, radius 14. No shadows.
struct QuidFieldModifier: ViewModifier {
    var isHighlighted = false

    func body(content: Content) -> some View {
        content
            .font(.quidBody)
            .foregroundStyle(Color.quidInk)
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isHighlighted ? Color.quidAccentText : Color.quidHairline, lineWidth: isHighlighted ? 2 : 1)
            )
    }
}

extension View {
    func quidField(isHighlighted: Bool = false) -> some View {
        modifier(QuidFieldModifier(isHighlighted: isHighlighted))
    }
}

/// Small label above a field, with an optional trailing hint such as "6/8".
struct QuidFieldGroup<Content: View>: View {
    let label: String
    var trailing: String? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 4)
            content()
        }
    }
}

/// One-line inline error under a field or form.
struct QuidErrorLine: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(message)
        }
        .font(.quidSubheadline)
        .foregroundStyle(Color.quidFailureText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("form.error")
    }
}
