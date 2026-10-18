import SwiftUI

/// What Confirmation of Payee said. MATCH continues, CLOSE_MATCH offers the bank's name, NO_MATCH sends the user back.
struct CopResultView: View {
    @Bindable var bankLink: BankLinkViewModel
    let onContinue: () async -> Void
    let onUseSuggested: () async -> Void
    let onEdit: () -> Void
    var onSkip: (() -> Void)? = nil

    var body: some View {
        Group {
            switch bankLink.result?.copStatus {
            case .match:
                ResultPage(
                    systemImage: "checkmark",
                    tone: .success,
                    title: "Verified with your bank",
                    message: "\(bankLink.result?.bankAccount?.bankName ?? "Your bank") confirmed this account is held in the name \(bankLink.trimmedName). You're set up to get paid.",
                    primaryTitle: "Continue",
                    primaryIdentifier: "cop.continue",
                    isLoading: false,
                    primary: { Task { await onContinue() } }
                )
            case .closeMatch:
                ResultPage(
                    systemImage: "person.text.rectangle",
                    tone: .pending,
                    title: "Nearly there",
                    message: "Your bank has this account in the name \u{201C}\(bankLink.result?.suggestedAccountHolderName ?? "")\u{201D}. Use that name so payments to you aren't held up?",
                    primaryTitle: "Use \u{201C}\(bankLink.result?.suggestedAccountHolderName ?? "that name")\u{201D}",
                    primaryIdentifier: "cop.useSuggested",
                    isLoading: bankLink.isSubmitting,
                    primary: { Task { await onUseSuggested() } },
                    secondaryTitle: "Edit details",
                    secondary: onEdit
                )
            case .noMatch, .unchecked, .none:
                ResultPage(
                    systemImage: "xmark",
                    tone: .failure,
                    title: "That name doesn't match",
                    message: "Your bank says this account isn't held in that name, so we haven't saved anything. Check the sort code, the account number and the exact name on your statement, then try again.",
                    primaryTitle: "Edit details",
                    primaryIdentifier: "cop.edit",
                    isLoading: false,
                    primary: onEdit,
                    secondaryTitle: onSkip == nil ? nil : "I'll do this later",
                    secondary: onSkip
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.quidBackground)
    }
}

private struct ResultPage: View {
    let systemImage: String
    let tone: StatusPill.Tone
    let title: String
    let message: String
    let primaryTitle: String
    let primaryIdentifier: String
    let isLoading: Bool
    let primary: () -> Void
    var secondaryTitle: String? = nil
    var secondary: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(foreground)
                    .frame(width: 72, height: 72)
                    .background(background, in: Circle())
                    .accessibilityHidden(true)
                Text(title)
                    .font(.quidTitle)
                    .foregroundStyle(Color.quidInk)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.quidBody)
                    .foregroundStyle(Color.quidMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            Spacer()
            VStack(spacing: 12) {
                QuidButton(title: primaryTitle, isLoading: isLoading, action: primary)
                    .accessibilityIdentifier(primaryIdentifier)
                if let secondaryTitle, let secondary {
                    QuidButton(title: secondaryTitle, style: .secondary, action: secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
        }
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
