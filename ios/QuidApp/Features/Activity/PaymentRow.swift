import SwiftUI

/// One payment in a list: avatar, name, reference · time, signed amount, status pill when not paid.
struct PaymentRow: View {
    let payment: PaymentDTO
    let currentUserId: String

    private var direction: PaymentDirection {
        payment.direction(for: currentUserId)
    }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: payment.counterparty.displayName, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(payment.counterparty.displayName)
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                    .lineLimit(1)
                Text("\(payment.reference) · \(payment.createdAt.quidRelativeDescription)")
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                AmountText(
                    money: payment.signedMoney(for: currentUserId),
                    style: .inline,
                    explicitPlus: direction == .received,
                    color: direction == .received ? Color.quidSuccessText : Color.quidInk
                )
                if payment.status.pillTone != .success {
                    StatusPill(text: payment.status.pillText, tone: payment.status.pillTone)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let amount = Money(minor: payment.amountMinor, currency: payment.currency).formatted()
        let verb = direction == .sent ? "Sent \(amount) to" : "Received \(amount) from"
        return "\(verb) \(payment.counterparty.displayName). \(payment.reference). \(payment.status.pillText). \(payment.createdAt.quidRelativeDescription)"
    }

    /// Redacted stand-in while the first load is running.
    static var placeholder: PaymentRow {
        PaymentRow(
            payment: PaymentDTO(
                id: "placeholder",
                payerUserId: "me",
                payeeUserId: "someone",
                collectionId: nil,
                requestId: nil,
                amountMinor: 1250,
                currency: "GBP",
                reference: "Reference",
                status: .settled,
                failureReason: nil,
                createdAt: Date(),
                updatedAt: Date(),
                settledAt: nil,
                counterparty: CounterpartyDTO(userId: "someone", displayName: "Someone Someone"),
                bankName: nil
            ),
            currentUserId: "me"
        )
    }
}
