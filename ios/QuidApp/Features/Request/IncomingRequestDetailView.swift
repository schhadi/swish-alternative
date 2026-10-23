import SwiftUI

/// One request addressed to the user (docs/SPEC.md section 8, screen 6): who, how much, what for, and Pay / Decline
/// while it is open. Reached from Activity and from a split's shared link.
struct IncomingRequestDetailView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var viewModel: IncomingRequestViewModel
    @State private var isPaying = false
    @State private var confirmingDecline = false

    init(api: APIClient, request: PaymentRequestDTO) {
        _viewModel = State(initialValue: IncomingRequestViewModel(api: api, request: request))
    }

    private var request: PaymentRequestDTO { viewModel.request }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Avatar(name: request.requester.displayName, size: 72)
                    Text("\(request.requester.displayName) asked you for")
                        .font(.quidBody)
                        .foregroundStyle(Color.quidMuted)
                        .multilineTextAlignment(.center)
                    AmountText(money: Money(minor: request.amountMinor), style: .hero)
                    Text(request.title)
                        .font(.quidHeadline)
                        .foregroundStyle(Color.quidInk)
                        .multilineTextAlignment(.center)
                    StatusPill(text: request.status.pillText, tone: request.status.pillTone)
                        .accessibilityIdentifier("request.status")
                }
                .padding(.top, 16)
                .accessibilityElement(children: .combine)

                if let note = request.note, !note.isEmpty {
                    Text("\u{201C}\(note)\u{201D}")
                        .font(.quidBody)
                        .foregroundStyle(Color.quidInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                QuidCard(padding: 0) {
                    VStack(spacing: 0) {
                        DetailRow(label: "Reference", value: request.reference)
                        QuidDivider().padding(.leading, 16)
                        DetailRow(label: "Asked", value: request.createdAt.quidReceiptDescription)
                        QuidDivider().padding(.leading, 16)
                        statusRow
                    }
                }

                if let error = viewModel.error {
                    QuidErrorLine(message: error.userMessage)
                }

                if viewModel.isOpen {
                    VStack(spacing: 12) {
                        QuidButton(title: "Pay \(Money(minor: request.amountMinor).formatted(compact: true))", systemImage: "arrow.up.right") {
                            isPaying = true
                        }
                        .accessibilityIdentifier("request.pay")
                        QuidButton(title: "Decline", style: .secondary, isLoading: viewModel.isDeclining) {
                            confirmingDecline = true
                        }
                        .accessibilityIdentifier("request.decline")
                    }
                }
            }
            .padding(16)
        }
        .background(Color.quidBackground)
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .fullScreenCover(isPresented: $isPaying) {
            PayFlowView(environment: appEnvironment, target: nil, request: request) {
                await viewModel.refresh()
            }
            .environment(appEnvironment)
        }
        .confirmationDialog(
            IncomingRequestViewModel.declineQuestion(for: request),
            isPresented: $confirmingDecline,
            titleVisibility: .visible
        ) {
            Button("Decline request", role: .destructive) {
                Task { await viewModel.decline() }
            }
        } message: {
            Text(IncomingRequestViewModel.declineExplanation)
        }
    }

    private var statusRow: some View {
        switch request.status {
        case .pending:
            return DetailRow(label: "Expires", value: request.expiresAt.formatted(.dateTime.day().month(.abbreviated)))
        case .paid:
            return DetailRow(label: "Paid", value: request.paidAt?.quidReceiptDescription ?? "Paid")
        case .declined:
            return DetailRow(label: "Declined", value: request.declinedAt?.quidReceiptDescription ?? "Declined")
        case .expired:
            return DetailRow(label: "Expired", value: request.expiresAt.quidReceiptDescription)
        case .cancelled:
            return DetailRow(label: "Cancelled", value: request.cancelledAt?.quidReceiptDescription ?? "Cancelled by \(request.requester.displayName)")
        }
    }
}
