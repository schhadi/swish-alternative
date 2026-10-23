import SwiftUI

/// A split the user created: title, progress and whether anyone is left to pay.
struct SplitSummaryRow: View {
    let split: SplitDTO

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.quidAccentText)
                .frame(width: 44, height: 44)
                .background(Color.quidSuccessTint, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(split.title)
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                    .quidLineLimit(1)
                Text("\(split.progressLine) · \(split.createdAt.quidRelativeDescription)")
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                    .quidLineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money(minor: split.requestedMinor).formatted())
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                StatusPill(text: split.statusText, tone: split.statusTone)
            }
            QuidChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(split.title). Asked for \(Money(minor: split.requestedMinor).formatted()). \(split.progressLine). \(split.statusText)")
        .accessibilityAddTraits(.isButton)
    }
}

/// A request addressed to the user: who asked, what for, how much and its state.
struct IncomingRequestRow: View {
    let request: PaymentRequestDTO

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: request.requester.displayName, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(request.requester.displayName)
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                    .quidLineLimit(1)
                Text("\(request.title) · \(request.createdAt.quidRelativeDescription)")
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                    .quidLineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money(minor: request.amountMinor).formatted())
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                StatusPill(text: request.status.pillText, tone: request.status.pillTone)
            }
            QuidChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(request.requester.displayName) asked for \(Money(minor: request.amountMinor).formatted()). \(request.title). \(request.status.pillText)")
        .accessibilityAddTraits(.isButton)
    }
}
