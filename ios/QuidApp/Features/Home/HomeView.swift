import SwiftUI

/// Greeting + linked bank, two big buttons, recent contacts, activity. Nav bar hidden; the greeting is the title.
struct HomeView: View {
    @State private var viewModel: HomeViewModel
    @State private var placeholder: PhasePlaceholder?
    @ScaledMetric(relativeTo: .footnote) private var contactTileWidth: CGFloat = 72
    let showActivity: () -> Void

    init(api: APIClient, showActivity: @escaping () -> Void) {
        _viewModel = State(initialValue: HomeViewModel(api: api))
        self.showActivity = showActivity
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    actionButtons
                    if !viewModel.incomingRequests.isEmpty {
                        incomingRequestsSection
                    }
                    recentContactsSection
                    activitySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color.quidBackground)
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.load() }
            .task { await viewModel.load() }
            .navigationDestination(for: PaymentDTO.self) { payment in
                PaymentDetailView(payment: payment, currentUserId: viewModel.currentUserId)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(item: $placeholder) { PhasePlaceholderSheet(placeholder: $0) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.greeting)
                .font(.quidTitle)
                .foregroundStyle(Color.quidInk)
                .redacted(reason: viewModel.isAwaitingFirstLoad && viewModel.me == nil ? .placeholder : [])
            bankLine
        }
    }

    @ViewBuilder
    private var bankLine: some View {
        if let bank = viewModel.me?.bankAccount {
            HStack(spacing: 6) {
                Image(systemName: "building.columns")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text("\(bank.bankName) · \(bank.copStatus.label)")
            }
            .font(.quidSubheadline)
            .foregroundStyle(Color.quidMuted)
            .accessibilityElement(children: .combine)
            if let until = bank.coolingOffUntil, until > Date() {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock")
                        .accessibilityHidden(true)
                    Text("You changed your bank account. You can receive payments again from \(until.quidReceiptDescription).")
                }
                .font(.quidFootnote)
                .foregroundStyle(Color.quidPendingText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.quidPendingTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        } else if viewModel.me != nil {
            Text("No bank account linked yet")
                .font(.quidSubheadline)
                .foregroundStyle(Color.quidMuted)
        } else if viewModel.isAwaitingFirstLoad {
            Text("Loading your account")
                .font(.quidSubheadline)
                .foregroundStyle(Color.quidMuted)
                .redacted(reason: .placeholder)
        } else if let error = viewModel.error {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Couldn't load your account. \(error.userMessage)")
            }
            .font(.quidSubheadline)
            .foregroundStyle(Color.quidFailureText)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 12) {
            QuidButton(title: "Pay", systemImage: "arrow.up.right") {
                placeholder = .pay
            }
            QuidButton(title: "Request", systemImage: "arrow.down.left", style: .secondary) {
                placeholder = .request
            }
        }
    }

    // MARK: - Incoming requests

    private var incomingRequestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuidSectionHeader(title: "Requests for you")
            ForEach(viewModel.incomingRequests) { request in
                IncomingRequestCard(
                    request: request,
                    onPay: { placeholder = .pay },
                    onDecline: { placeholder = .declineRequest }
                )
            }
        }
    }

    // MARK: - Recent contacts

    private var recentContactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuidSectionHeader(title: "Recent")
            if viewModel.isAwaitingFirstLoad && viewModel.recentContacts.isEmpty {
                HStack(spacing: 16) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: 8) {
                            Circle().fill(Color.quidSurfaceSecondary).frame(width: 56, height: 56)
                            Capsule().fill(Color.quidSurfaceSecondary).frame(width: 44, height: 10)
                        }
                    }
                }
                .accessibilityHidden(true)
            } else if viewModel.recentContacts.isEmpty {
                let failedFirstLoad = !viewModel.hasLoaded && viewModel.error != nil
                Text(failedFirstLoad ? "Couldn't load your recent contacts." : "People you pay will show up here.")
                    .font(.quidSubheadline)
                    .foregroundStyle(failedFirstLoad ? Color.quidFailureText : Color.quidMuted)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(viewModel.recentContacts) { contact in
                            Button {
                                placeholder = .pay
                            } label: {
                                VStack(spacing: 8) {
                                    ZStack(alignment: .bottomTrailing) {
                                        Avatar(name: contact.displayName, size: 56)
                                        if contact.isRegistered {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundStyle(Color.quidAccentText, Color.quidBackground)
                                                .offset(x: 2, y: 2)
                                        }
                                    }
                                    Text(contact.firstName)
                                        .font(.quidFootnote)
                                        .foregroundStyle(Color.quidInk)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(width: contactTileWidth)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Pay \(contact.displayName)")
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuidSectionHeader(
                title: "Activity",
                actionTitle: viewModel.payments.isEmpty ? nil : "See all",
                action: showActivity
            )
            if let error = viewModel.error, viewModel.payments.isEmpty {
                ErrorStateView(error: error) { await viewModel.load() }
            } else if viewModel.isAwaitingFirstLoad && viewModel.payments.isEmpty {
                QuidCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            PaymentRow.placeholder
                            if index < 2 {
                                QuidDivider().padding(.leading, 72)
                            }
                        }
                    }
                }
                .redacted(reason: .placeholder)
                .accessibilityHidden(true)
            } else if viewModel.payments.isEmpty {
                EmptyStateView(
                    systemImage: "arrow.left.arrow.right",
                    title: "No payments yet",
                    message: "Pay a friend or request money and it will show up here."
                )
            } else {
                QuidCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.recentPayments.enumerated()), id: \.element.id) { index, payment in
                            NavigationLink(value: payment) {
                                PaymentRow(payment: payment, currentUserId: viewModel.currentUserId)
                            }
                            .buttonStyle(.plain)
                            if index < viewModel.recentPayments.count - 1 {
                                QuidDivider().padding(.leading, 72)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A request addressed to me: Pay prefills the Pay flow, Decline declines it (both Phase 3).
struct IncomingRequestCard: View {
    let request: PaymentRequestDTO
    let onPay: () -> Void
    let onDecline: () -> Void

    var body: some View {
        QuidCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Avatar(name: request.requester.displayName, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(request.requester.displayName) asked for \(Money(minor: request.amountMinor).formatted())")
                            .font(.quidHeadline)
                            .foregroundStyle(Color.quidInk)
                        Text(subtitle)
                            .font(.quidFootnote)
                            .foregroundStyle(Color.quidMuted)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    QuidPillButton(title: "Pay \(Money(minor: request.amountMinor).formatted(compact: true))", action: onPay)
                    QuidPillButton(title: "Decline", style: .neutral, action: onDecline)
                    Spacer()
                }
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = [request.splitTitle ?? request.reference]
        if let note = request.note, !note.isEmpty {
            parts.append(note)
        }
        parts.append("Expires \(request.expiresAt.formatted(.dateTime.day().month(.abbreviated)))")
        return parts.joined(separator: " · ")
    }
}

#Preview("Home") {
    HomeView(api: .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken)), showActivity: {})
        .environment(AppEnvironment.demo())
}
