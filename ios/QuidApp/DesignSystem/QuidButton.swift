import SwiftUI

/// Full-width action button: height 58, radius 18, no gradients or shadows.
struct QuidButton: View {
    enum Style: Equatable {
        case primary, secondary, destructive
        /// For full-bleed tinted screens: filled with the screen's ink, labelled in the screen's background colour.
        case onTint(fill: Color, text: Color)
    }

    let title: String
    var systemImage: String? = nil
    var style: Style = .primary
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(QuidButtonStyle(style: style).foreground)
                } else {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: 16, weight: .bold))
                    }
                    Text(title)
                }
            }
            .font(.quidHeadline)
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(QuidButtonStyle(style: style))
        .disabled(isLoading)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isLoading ? .updatesFrequently : [])
    }
}

struct QuidButtonStyle: ButtonStyle {
    let style: QuidButton.Style
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(background(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    var foreground: Color {
        switch style {
        case .primary: return .quidOnAccent
        case .secondary: return .quidInk
        case .destructive: return .quidFailureText
        case .onTint(_, let text): return text
        }
    }

    private func background(pressed: Bool) -> Color {
        switch style {
        case .primary: return pressed ? .quidAccentPressed : .quidAccent
        case .secondary: return pressed ? .quidSurfaceSecondaryPressed : .quidSurfaceSecondary
        case .destructive: return pressed ? .quidFailureTint.opacity(0.7) : .quidFailureTint
        case .onTint(let fill, _): return pressed ? fill.opacity(0.85) : fill
        }
    }
}

/// Small pill action ("Nudge", "Pay", "Remind"). Visually 36pt, 44pt hit target.
struct QuidPillButton: View {
    enum Style {
        case accent, neutral
    }

    let title: String
    var style: Style = .accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.quidFootnote)
                .foregroundStyle(style == .accent ? Color.quidOnAccent : Color.quidInk)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(style == .accent ? Color.quidAccent : Color.quidSurfaceSecondary, in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
