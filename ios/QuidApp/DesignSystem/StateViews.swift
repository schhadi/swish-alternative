import SwiftUI

/// Empty state inside a card: icon tile, title, one-line explanation.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.quidAccentText)
                .frame(width: 56, height: 56)
                .background(Color.quidSuccessTint, in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.quidHeadline)
                .foregroundStyle(Color.quidInk)
            Text(message)
                .font(.quidSubheadline)
                .foregroundStyle(Color.quidMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Error state with a retry button. The message comes from `AppError.userMessage`.
struct ErrorStateView: View {
    let error: AppError
    let retry: () async -> Void
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.quidFailureText)
                .frame(width: 56, height: 56)
                .background(Color.quidFailureTint, in: Circle())
                .accessibilityHidden(true)
            Text("Couldn't load")
                .font(.quidHeadline)
                .foregroundStyle(Color.quidInk)
            Text(error.userMessage)
                .font(.quidSubheadline)
                .foregroundStyle(Color.quidMuted)
                .multilineTextAlignment(.center)
            QuidButton(title: "Try again", style: .secondary, isLoading: isRetrying) {
                Task {
                    isRetrying = true
                    await retry()
                    isRetrying = false
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Full-screen centred spinner for first loads.
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(Color.quidAccentText)
            Text("Loading")
                .font(.quidFootnote)
                .foregroundStyle(Color.quidMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
