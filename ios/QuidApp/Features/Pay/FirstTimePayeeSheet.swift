import SwiftUI

/// Shown once per new payee (docs/SPEC.md section 7): the name their bank holds, and a reminder that transfers are final.
struct FirstTimePayeeSheet: View {
    let response: PaymentCreateResponseDTO
    let onPay: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Avatar(name: response.payee.displayName, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("First time paying \(response.payee.displayName)?")
                        .font(.quidTitle3)
                        .foregroundStyle(Color.quidInk)
                    Text(Money(minor: response.payment.amountMinor).formatted())
                        .font(.quidSubheadline)
                        .foregroundStyle(Color.quidMuted)
                }
            }
            QuidCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Their bank holds this account as")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
                    Text("\u{201C}\(response.payee.accountHolderName ?? response.payee.displayName)\u{201D}")
                        .font(.quidHeadline)
                        .foregroundStyle(Color.quidInk)
                    Text("\(response.payee.bankName) · \(response.payee.copStatus.label)")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
                }
            }
            Text("Only pay people you know. A bank transfer can't be reversed once your bank has sent it.")
                .font(.quidFootnote)
                .foregroundStyle(Color.quidMuted)
            Spacer(minLength: 0)
            QuidButton(title: "Pay \(Money(minor: response.payment.amountMinor).formatted(compact: true))", action: onPay)
                .accessibilityIdentifier("pay.firstTime.confirm")
            QuidButton(title: "Cancel", style: .secondary, action: onCancel)
                .accessibilityIdentifier("pay.firstTime.cancel")
        }
        .padding(24)
        .background(Color.quidBackground)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
    }
}
