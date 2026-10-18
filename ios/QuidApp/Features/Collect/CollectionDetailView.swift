import SwiftUI

/// Treasurer view of one collection: progress, who has paid, who hasn't. Reminders, link and QR arrive in Phase 4.
struct CollectionDetailView: View {
    @State private var viewModel: CollectionDetailViewModel
    @State private var placeholder: PhasePlaceholder?

    init(api: APIClient, collection: CollectionSummaryDTO) {
        _viewModel = State(initialValue: CollectionDetailViewModel(api: api, collection: collection))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryCard
                if let error = viewModel.error, viewModel.members.isEmpty {
                    ErrorStateView(error: error) { await viewModel.load() }
                } else if viewModel.isLoading && viewModel.members.isEmpty {
                    LoadingView()
                        .frame(height: 160)
                } else {
                    Picker("Show", selection: $viewModel.filter) {
                        ForEach(MemberFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    membersCard
                }
            }
            .padding(16)
        }
        .background(Color.quidBackground)
        .navigationTitle(viewModel.collection.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Remind all") {
                    placeholder = .remind
                }
                .font(.quidSubheadline)
                .disabled(viewModel.unpaidCount == 0)
            }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(item: $placeholder) { PhasePlaceholderSheet(placeholder: $0) }
    }

    private var summaryCard: some View {
        QuidCard {
            VStack(alignment: .leading, spacing: 12) {
                if !viewModel.organisationName.isEmpty {
                    Text(viewModel.organisationName)
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
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

    @ViewBuilder
    private var membersCard: some View {
        if viewModel.filteredMembers.isEmpty {
            EmptyStateView(
                systemImage: viewModel.filter == .unpaid ? "checkmark.circle" : "person.2",
                title: viewModel.filter == .unpaid ? "Everyone has paid" : "Nobody here yet",
                message: viewModel.filter == .unpaid ? "Nothing left to chase." : "Members will appear here once they're added."
            )
        } else {
            QuidCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredMembers.enumerated()), id: \.element.id) { index, member in
                        CollectionMemberRow(member: member) {
                            placeholder = .remind
                        }
                        if index < viewModel.filteredMembers.count - 1 {
                            QuidDivider().padding(.leading, 68)
                        }
                    }
                }
            }
        }
    }
}

struct CollectionMemberRow: View {
    let member: CollectionMemberDTO
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
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if member.status == .paid {
                StatusPill(text: "Paid", tone: .success)
            } else {
                QuidPillButton(title: "Remind", style: .neutral, action: onRemind)
                    .accessibilityLabel("Remind \(member.displayName)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var subtitle: String {
        if member.status == .paid, let paidAt = member.paidAt {
            return "Paid \(paidAt.quidRelativeDescription)"
        }
        switch member.remindCount {
        case 0: return "Not paid yet"
        case 1: return "Reminded once"
        default: return "Reminded \(member.remindCount) times"
        }
    }
}
