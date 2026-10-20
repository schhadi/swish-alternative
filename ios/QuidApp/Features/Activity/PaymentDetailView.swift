import SwiftUI

/// Receipt for one payment. The post-payment result screen (Phase 2) reuses these rows.
struct PaymentDetailView: View {
    let payment: PaymentDTO
    let currentUserId: String

    private var direction: PaymentDirection {
        payment.direction(for: currentUserId)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Avatar(name: payment.counterparty.displayName, size: 72)
                    AmountText(money: Money(minor: payment.amountMinor, currency: payment.currency), style: .hero)
                    Text(direction == .sent ? "to \(payment.counterparty.displayName)" : "from \(payment.counterparty.displayName)")
                        .font(.quidBody)
                        .foregroundStyle(Color.quidMuted)
                    StatusPill(text: payment.status.pillText, tone: payment.status.pillTone)
                }
                .padding(.top, 16)
                .accessibilityElement(children: .combine)

                if let reason = payment.status.failureMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.circle")
                            .accessibilityHidden(true)
                        Text(reason)
                    }
                    .font(.quidSubheadline)
                    .foregroundStyle(Color.quidFailureText)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.quidFailureTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else if !payment.status.isFinal {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "clock")
                            .accessibilityHidden(true)
                        Text("Waiting for the bank to confirm. We'll update this automatically.")
                    }
                    .font(.quidSubheadline)
                    .foregroundStyle(Color.quidPendingText)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.quidPendingTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                QuidCard(padding: 0) {
                    VStack(spacing: 0) {
                        DetailRow(label: "Reference", value: payment.reference)
                        QuidDivider().padding(.leading, 16)
                        DetailRow(label: direction == .sent ? "Sent" : "Received", value: payment.createdAt.quidReceiptDescription)
                        if let settledAt = payment.settledAt {
                            QuidDivider().padding(.leading, 16)
                            DetailRow(label: "Settled", value: settledAt.quidReceiptDescription)
                        }
                        QuidDivider().padding(.leading, 16)
                        DetailRow(label: "Via", value: "\(payment.bankName ?? "Bank") · Faster Payments")
                        QuidDivider().padding(.leading, 16)
                        DetailRow(label: "Status", value: payment.status.pillText)
                        QuidDivider().padding(.leading, 16)
                        DetailRow(label: "Payment ID", value: payment.id, monospaced: true)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.quidBackground)
        .navigationTitle("Payment")
        .navigationBarTitleDisplayMode(.inline)
    }
}
