import SwiftUI

/// Full-bleed Paid / Pending / Failed screen driven by the server's status (docs/SPEC.md section 8, screen 4).
struct PaymentResultView: View {
    @Bindable var viewModel: PayViewModel
    @State private var placeholder: PhasePlaceholder?

    private var kind: PayResultKind { viewModel.resultKind }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                statusBlock
                    .padding(.top, 24)
                if let payment = viewModel.payment {
                    receipt(payment)
                }
                actions
            }
            .padding(20)
        }
        .background(background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $placeholder) { PhasePlaceholderSheet(placeholder: $0) }
        .onDisappear { viewModel.stopPolling() }
        // The title and copy change in place when the poll catches up with the bank; VoiceOver hears the outcome.
        .onChange(of: kind) {
            AccessibilityNotification.Announcement("\(title). \(message)").post()
        }
        .accessibilityIdentifier("pay.result")
    }

    private var statusBlock: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ink.opacity(0.14))
                    .frame(width: 84, height: 84)
                switch kind {
                case .paid:
                    Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(ink)
                case .pending:
                    ProgressView().tint(ink).scaleEffect(1.4)
                case .failed:
                    Image(systemName: "xmark").font(.system(size: 34, weight: .bold)).foregroundStyle(ink)
                }
            }
            .accessibilityHidden(true)
            Text(title)
                .font(.quidTitle)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("pay.result.title")
            if let payment = viewModel.payment {
                AmountText(money: Money(minor: payment.amountMinor, currency: payment.currency), style: .hero, color: ink)
                Text("to \(payment.counterparty.displayName)")
                    .font(.quidBody)
                    .foregroundStyle(ink)
            }
            Text(message)
                .font(.quidSubheadline)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func receipt(_ payment: PaymentDTO) -> some View {
        QuidCard(padding: 0) {
            VStack(spacing: 0) {
                DetailRow(label: "Sent", value: payment.createdAt.quidReceiptDescription)
                QuidDivider().padding(.leading, 16)
                DetailRow(label: "Reference", value: payment.reference)
                QuidDivider().padding(.leading, 16)
                DetailRow(label: "Via", value: "\(payment.bankName ?? viewModel.myBankName ?? "Your bank") · Faster Payments")
                QuidDivider().padding(.leading, 16)
                DetailRow(label: "Status", value: payment.status.pillText)
                if let settledAt = payment.settledAt {
                    QuidDivider().padding(.leading, 16)
                    DetailRow(label: "Settled", value: settledAt.quidReceiptDescription)
                }
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 12) {
            switch kind {
            case .paid:
                QuidButton(title: "Split this with others", style: .secondary) { placeholder = .request }
                    .accessibilityIdentifier("pay.split")
                QuidButton(title: "Done", style: .onTint(fill: ink, text: background)) { viewModel.done() }
                    .accessibilityIdentifier("pay.done")
            case .pending:
                QuidButton(title: "Done", style: .onTint(fill: ink, text: background)) { viewModel.done() }
                    .accessibilityIdentifier("pay.done")
            case .failed:
                QuidButton(title: "Try again", style: .onTint(fill: ink, text: background)) { viewModel.tryAgain() }
                    .accessibilityIdentifier("pay.tryAgain")
                QuidButton(title: "Done", style: .secondary) { viewModel.done() }
                    .accessibilityIdentifier("pay.done")
            }
        }
    }

    private var title: String {
        switch kind {
        case .paid: return "Paid"
        case .pending: return "Pending"
        case .failed: return "Failed"
        }
    }

    private var message: String {
        switch kind {
        case .paid:
            return "Your bank has sent it. It normally arrives within seconds."
        case .pending:
            return viewModel.pollingTimedOut
                ? "Still waiting for your bank. We'll let you know when it goes through; it stays in Activity meanwhile."
                : "Waiting for your bank to confirm. This usually takes a few seconds."
        case .failed(let reason):
            return reason
        }
    }

    /// Paid is the accent green with white ink (contrast 6.5:1); the others use the tint-and-text pairs from the design system.
    private var background: Color {
        switch kind {
        case .paid: return .quidAccent
        case .pending: return .quidPendingTint
        case .failed: return .quidFailureTint
        }
    }

    private var ink: Color {
        switch kind {
        case .paid: return .quidOnAccent
        case .pending: return .quidPendingText
        case .failed: return .quidFailureText
        }
    }
}
