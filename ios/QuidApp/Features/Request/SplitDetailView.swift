import SwiftUI
import UIKit

/// Total, progress, who has paid, Nudge per person, the shareable link and "Remind everyone unpaid"
/// (docs/SPEC.md section 8, screen 5).
struct SplitDetailView: View {
    @State private var viewModel: SplitDetailViewModel
    @State private var copied = false
    @State private var confirmingCancel = false
    let onDone: (() -> Void)?

    init(api: APIClient, split: SplitDTO, justCreated: Bool = false, onDone: (() -> Void)? = nil) {
        _viewModel = State(initialValue: SplitDetailViewModel(api: api, split: split, justCreated: justCreated))
        self.onDone = onDone
    }

    private var split: SplitDTO { viewModel.split }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.justCreated {
                    sentBanner
                }
                summaryCard
                if let notice = viewModel.notice {
                    noticeLine(notice)
                }
                peopleSection
                linkCard
                if let error = viewModel.error {
                    QuidErrorLine(message: error.userMessage)
                }
            }
            .padding(16)
        }
        .background(Color.quidBackground)
        .safeAreaInset(edge: .bottom) {
            if !split.isComplete {
                VStack(spacing: 6) {
                    QuidButton(title: "Remind everyone unpaid", systemImage: "bell", style: .secondary, isLoading: viewModel.isRemindingAll) {
                        Task { await viewModel.remindAll() }
                    }
                    .disabled(viewModel.dueReminderCount == 0)
                    .accessibilityIdentifier("split.remindAll")
                    if viewModel.dueReminderCount == 0 {
                        Text("Everyone unpaid has been nudged in the last day.")
                            .font(.quidFootnote)
                            .foregroundStyle(Color.quidMuted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Color.quidBackground)
            }
        }
        .navigationTitle(split.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    if viewModel.openCount > 0 {
                        Menu {
                            Button("Cancel open requests", systemImage: "xmark.circle", role: .destructive) {
                                confirmingCancel = true
                            }
                            .accessibilityIdentifier("split.cancelOpen")
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("More")
                        .accessibilityIdentifier("split.more")
                    }
                    if let onDone {
                        Button("Done", action: onDone)
                            .font(.quidSubheadline)
                            .accessibilityIdentifier("split.done")
                    }
                }
            }
        }
        .confirmationDialog("Cancel the open requests in \u{201C}\(split.title)\u{201D}?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel open requests", role: .destructive) {
                Task { await viewModel.cancelOpenRequests() }
            }
            .accessibilityIdentifier("split.cancelOpen.confirm")
            Button("Keep them", role: .cancel) {}
        } message: {
            Text(SplitDetailViewModel.cancelExplanation)
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .onChange(of: viewModel.notice) {
            guard let notice = viewModel.notice else { return }
            AccessibilityNotification.Announcement(notice).post()
        }
    }

    private var sentBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(split.shareCount == 1 ? "Request sent" : "\(split.shareCount) requests sent")
                    .font(.quidHeadline)
                Text("\(NameList.firstNames(split.shares.map(\.displayName))) can pay from Quid. You'll see it here as they do.")
                    .font(.quidFootnote)
            }
        }
        .foregroundStyle(Color.quidSuccessText)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.quidSuccessTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("split.sent")
    }

    private var summaryCard: some View {
        QuidCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(split.title)
                    .font(.quidTitle2)
                    .foregroundStyle(Color.quidInk)
                    .accessibilityIdentifier("split.title")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    AmountText(money: Money(minor: split.paidMinor), style: .large)
                    Text("of \(Money(minor: split.requestedMinor).formatted()) received")
                        .font(.quidBody)
                        .foregroundStyle(Color.quidMuted)
                }
                ProgressView(value: viewModel.progress)
                    .tint(Color.quidAccentText)
                    .accessibilityHidden(true)
                Text("\(split.progressLine) · asked \(split.createdAt.quidInlineDescription)")
                    .font(.quidSubheadline)
                    .foregroundStyle(Color.quidMuted)
                    .accessibilityIdentifier("split.progress")
                if split.creatorShareMinor > 0 {
                    Text("Your share of the \(Money(minor: split.totalMinor).formatted()) bill: \(Money(minor: split.creatorShareMinor).formatted())")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func noticeLine(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "bell")
                .accessibilityHidden(true)
            Text(notice)
            Spacer(minLength: 0)
        }
        .font(.quidSubheadline)
        .foregroundStyle(Color.quidInk)
        .padding(14)
        .background(Color.quidSurfaceSecondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("split.notice")
    }

    private var peopleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuidSectionHeader(title: "People", size: .small)
            QuidCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(split.shares.enumerated()), id: \.element.id) { index, share in
                        SplitShareRow(
                            share: share,
                            isBusy: viewModel.busyRequestIds.contains(share.requestId)
                        ) {
                            Task { await viewModel.nudge(share) }
                        }
                        if index < split.shares.count - 1 {
                            QuidDivider().padding(.leading, 68)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var linkCard: some View {
        if let url = split.linkURL {
            VStack(alignment: .leading, spacing: 8) {
                QuidSectionHeader(title: "Share link", size: .small)
                QuidCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Post it in your group chat. It opens this split in Quid for everyone you asked.")
                            .font(.quidFootnote)
                            .foregroundStyle(Color.quidMuted)
                        Text(split.link)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Color.quidInk)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityLabel("Link address")
                            .accessibilityValue(split.link)
                        HStack(spacing: 10) {
                            QuidPillButton(title: copied ? "Copied" : "Copy link", style: .neutral) {
                                UIPasteboard.general.string = split.link
                                copied = true
                                AccessibilityNotification.Announcement("Link copied").post()
                            }
                            .accessibilityIdentifier("split.copy")
                            ShareLink(item: url, message: Text("Pay your share of \u{201C}\(split.title)\u{201D} on Quid")) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.quidFootnote)
                                    .foregroundStyle(Color.quidOnAccent)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 36)
                                    .background(Color.quidAccent, in: Capsule())
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("split.share")
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

/// One person in a split: amount, state, and a Nudge button while they haven't paid.
struct SplitShareRow: View {
    let share: SplitShareDTO
    let isBusy: Bool
    let onNudge: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: share.displayName, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(share.displayName)
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                    .quidLineLimit(1)
                Text(subtitle)
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                    .quidLineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(Money(minor: share.amountMinor).formatted())
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                    .accessibilityLabel(Money(minor: share.amountMinor).spokenDescription)
                trailing
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("split.share.\(share.userId)")
    }

    @ViewBuilder
    private var trailing: some View {
        if share.status == .pending {
            if isBusy {
                ProgressView().tint(Color.quidAccentText).frame(minHeight: 44)
            } else if share.canNudge() {
                QuidPillButton(title: "Nudge", style: .neutral, action: onNudge)
                    .accessibilityLabel("Nudge \(share.displayName)")
                    .accessibilityIdentifier("split.nudge.\(share.userId)")
            } else {
                StatusPill(text: "Nudged", tone: .neutral)
            }
        } else {
            StatusPill(text: share.status.pillText, tone: share.status.pillTone)
        }
    }

    private var subtitle: String {
        switch share.status {
        case .paid:
            return share.paidAt.map { "Paid \($0.quidInlineDescription)" } ?? "Paid"
        case .declined:
            return "Declined"
        case .expired:
            return "Expired without paying"
        case .cancelled:
            return share.cancelledAt.map { "You cancelled this \($0.quidInlineDescription)" } ?? "You cancelled this"
        case .pending:
            if let reminded = share.lastRemindedAt {
                return "Not paid yet · nudged \(reminded.quidInlineDescription)"
            }
            return "Not paid yet"
        }
    }
}
