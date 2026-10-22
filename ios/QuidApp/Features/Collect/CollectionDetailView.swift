import SwiftUI
import UIKit

/// Treasurer view of one collection (docs/SPEC.md section 8, screen 7): progress, the pay link and its QR code,
/// who has paid, Remind per person and "Remind all unpaid", and closing it.
struct CollectionDetailView: View {
    @State private var viewModel: CollectionDetailViewModel
    @State private var showingQR = false
    @State private var confirmingClose = false
    @State private var copied = false

    init(api: APIClient, collection: CollectionSummaryDTO, justCreated: Bool = false) {
        _viewModel = State(initialValue: CollectionDetailViewModel(api: api, collection: collection, justCreated: justCreated))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.justCreated {
                    createdBanner
                }
                summaryCard
                if let notice = viewModel.notice {
                    noticeLine(notice)
                }
                if viewModel.isOpen, viewModel.linkURL != nil {
                    linkCard
                }
                if let error = viewModel.error, viewModel.members.isEmpty {
                    ErrorStateView(error: error) { await viewModel.load() }
                } else if viewModel.isAwaitingFirstLoad && viewModel.members.isEmpty {
                    LoadingView()
                        .frame(height: 160)
                } else {
                    Picker("Show", selection: $viewModel.filter) {
                        ForEach(MemberFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("collection.filter")
                    membersCard
                }
            }
            .padding(16)
        }
        .background(Color.quidBackground)
        .safeAreaInset(edge: .bottom) {
            if viewModel.isOpen && viewModel.unpaidCount > 0 {
                VStack(spacing: 6) {
                    QuidButton(title: "Remind all unpaid", systemImage: "bell", style: .secondary, isLoading: viewModel.isRemindingAll) {
                        Task { await viewModel.remindAll() }
                    }
                    .disabled(viewModel.dueReminderCount == 0)
                    .accessibilityIdentifier("collection.remindAll")
                    if viewModel.dueReminderCount == 0 {
                        Text(viewModel.hasRemindableUnpaid
                            ? "Everyone unpaid on Quid was reminded in the last day."
                            : "Nobody unpaid uses Quid. Send them the pay link instead.")
                            .font(.quidFootnote)
                            .foregroundStyle(Color.quidMuted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.quidBackground)
            }
        }
        .navigationTitle(viewModel.collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isOpen {
                    Menu {
                        Button("Close collection", systemImage: "lock", role: .destructive) {
                            confirmingClose = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("More")
                    .accessibilityIdentifier("collection.more")
                }
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showingQR) {
            if let url = viewModel.linkURL {
                QRCodeSheet(
                    url: url,
                    title: "Pay \(viewModel.organisationName.isEmpty ? "us" : viewModel.organisationName)",
                    subtitle: "\(Money(minor: viewModel.collection.amountPerPersonMinor).formatted()) · \(viewModel.collection.title)"
                )
            }
        }
        .confirmationDialog("Close \(viewModel.collection.title)?", isPresented: $confirmingClose, titleVisibility: .visible) {
            Button("Close collection", role: .destructive) {
                Task { await viewModel.close() }
            }
        } message: {
            Text("The link stops taking payments. Payments already at the bank still count.")
        }
        .onChange(of: viewModel.notice) {
            guard let notice = viewModel.notice else { return }
            AccessibilityNotification.Announcement(notice).post()
        }
    }

    private var createdBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Collection created")
                    .font(.quidHeadline)
                Text("Share the link or show the QR code. People on the list who use Quid can also pay from the app.")
                    .font(.quidFootnote)
            }
        }
        .foregroundStyle(Color.quidSuccessText)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.quidSuccessTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("collection.created")
    }

    private var summaryCard: some View {
        QuidCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if !viewModel.organisationName.isEmpty {
                        Text(viewModel.organisationName)
                            .font(.quidFootnote)
                            .foregroundStyle(Color.quidMuted)
                    }
                    if !viewModel.isOpen {
                        StatusPill(text: "Closed", tone: .neutral)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    AmountText(money: viewModel.collected, style: .large)
                    Text("of \(viewModel.target.formatted(compact: true))")
                        .font(.quidBody)
                        .foregroundStyle(Color.quidMuted)
                }
                ProgressView(value: Double(viewModel.paidCount), total: Double(max(viewModel.memberCount, 1)))
                    .tint(Color.quidAccentText)
                Text(progressLine)
                    .font(.quidSubheadline)
                    .foregroundStyle(Color.quidMuted)
                    .accessibilityIdentifier("collection.progress")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var progressLine: String {
        var parts = [
            "\(viewModel.paidCount) of \(viewModel.memberCount) paid",
            "\(Money(minor: viewModel.collection.amountPerPersonMinor).formatted(compact: true)) each",
        ]
        if let dueAt = viewModel.collection.dueAt {
            parts.append(dueAt.quidDueDescription)
        }
        return parts.joined(separator: " · ")
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
        .accessibilityIdentifier("collection.notice")
    }

    @ViewBuilder
    private var linkCard: some View {
        if let url = viewModel.linkURL {
            QuidCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pay link")
                        .font(.quidHeadline)
                        .foregroundStyle(Color.quidInk)
                    Text(url.absoluteString)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.quidInk)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    HStack(spacing: 10) {
                        QuidPillButton(title: copied ? "Copied" : "Copy", style: .neutral) {
                            UIPasteboard.general.string = url.absoluteString
                            copied = true
                            AccessibilityNotification.Announcement("Link copied").post()
                        }
                        .accessibilityIdentifier("collection.copy")
                        QuidPillButton(title: "Show QR", style: .neutral) {
                            showingQR = true
                        }
                        .accessibilityIdentifier("collection.showQR")
                        ShareLink(item: url, message: Text("Pay \(Money(minor: viewModel.collection.amountPerPersonMinor).formatted()) for \(viewModel.collection.title)")) {
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
                        .accessibilityIdentifier("collection.share")
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var membersCard: some View {
        if viewModel.filteredMembers.isEmpty {
            EmptyStateView(
                systemImage: viewModel.filter == .unpaid ? "checkmark.circle" : "person.2",
                title: emptyTitle,
                message: emptyMessage
            )
        } else {
            QuidCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredMembers.enumerated()), id: \.element.id) { index, member in
                        CollectionMemberRow(
                            member: member,
                            canRemind: viewModel.canRemind(member),
                            isOpen: viewModel.isOpen,
                            isBusy: viewModel.busyMemberIds.contains(member.id)
                        ) {
                            Task { await viewModel.remind(member) }
                        }
                        if index < viewModel.filteredMembers.count - 1 {
                            QuidDivider().padding(.leading, 68)
                        }
                    }
                }
            }
        }
    }

    private var emptyTitle: String {
        if viewModel.members.isEmpty { return "Nobody on the list yet" }
        return viewModel.filter == .unpaid ? "Everyone has paid" : "Nobody has paid yet"
    }

    private var emptyMessage: String {
        if viewModel.members.isEmpty { return "Share the link: people who pay from it are added here." }
        return viewModel.filter == .unpaid ? "Nothing left to chase." : "Payments show up here as soon as the bank sends them."
    }
}

struct CollectionMemberRow: View {
    let member: CollectionMemberDTO
    var canRemind = false
    var isOpen = true
    var isBusy = false
    let onRemind: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: member.displayName, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.displayName)
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("collection.member.\(member.id)")
    }

    @ViewBuilder
    private var trailing: some View {
        if member.status == .paid {
            StatusPill(text: "Paid", tone: .success)
        } else if isBusy {
            ProgressView().tint(Color.quidAccentText).frame(minHeight: 44)
        } else if canRemind {
            QuidPillButton(title: "Remind", style: .neutral, action: onRemind)
                .accessibilityLabel("Remind \(member.displayName)")
                .accessibilityIdentifier("collection.remind.\(member.id)")
        } else if isOpen && (member.isOnQuid ?? false) {
            StatusPill(text: "Reminded", tone: .neutral)
        }
    }

    private var subtitle: String {
        if member.status == .paid, let paidAt = member.paidAt {
            return "Paid \(paidAt.quidInlineDescription)"
        }
        if member.isOnQuid == false {
            return "Not on Quid · can pay from the link"
        }
        switch member.remindCount {
        case 0: return "Not paid yet"
        case 1: return "Not paid yet · reminded once"
        default: return "Not paid yet · reminded \(member.remindCount) times"
        }
    }
}
