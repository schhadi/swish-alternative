import SwiftUI

/// Paid / Pending / Failed pill. Radius 999, tinted background, no border.
struct StatusPill: View {
    enum Tone {
        case success, pending, failure, neutral
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.quidCaption)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
            .lineLimit(1)
    }

    private var foreground: Color {
        switch tone {
        case .success: return .quidSuccessText
        case .pending: return .quidPendingText
        case .failure: return .quidFailureText
        case .neutral: return .quidMuted
        }
    }

    private var background: Color {
        switch tone {
        case .success: return .quidSuccessTint
        case .pending: return .quidPendingTint
        case .failure: return .quidFailureTint
        case .neutral: return .quidSurfaceSecondary
        }
    }
}
