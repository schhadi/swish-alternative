import SwiftUI

/// Organisations the user belongs to and their collections, as cards. Treasurer tools arrive in Phase 4.
struct CollectView: View {
    @State private var viewModel: CollectViewModel
    @State private var placeholder: PhasePlaceholder?

    init(api: APIClient) {
        _viewModel = State(initialValue: CollectViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = viewModel.error, viewModel.organisations.isEmpty {
                    ErrorStateView(error: error) { await viewModel.load() }
                        .padding(16)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if viewModel.isLoading && viewModel.organisations.isEmpty {
                    LoadingView()
                } else if viewModel.organisations.isEmpty {
                    VStack(spacing: 16) {
                        EmptyStateView(
                            systemImage: "person.3",
                            title: "No organisations yet",
                            message: "Collect money for a society, sports club or flat. Set one up and share a link or QR code."
                        )
                        QuidButton(title: "Create an organisation", systemImage: "plus") {
                            placeholder = .createCollection
                        }
                    }
                    .padding(16)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    content
                }
            }
            .background(Color.quidBackground)
            .navigationTitle("Collect")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        placeholder = .createCollection
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New collection")
                }
            }
            .navigationDestination(for: CollectionSummaryDTO.self) { collection in
                CollectionDetailView(api: viewModel.api, collection: collection)
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
        .sheet(item: $placeholder) { PhasePlaceholderSheet(placeholder: $0) }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(viewModel.organisations) { organisation in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(organisation.name)
                                .font(.quidTitle3)
                                .foregroundStyle(Color.quidInk)
                            StatusPill(
                                text: organisation.role == .treasurer ? "Treasurer" : organisation.kind.label,
                                tone: .neutral
                            )
                        }
                        .frame(minHeight: 28)
                        .accessibilityElement(children: .combine)
                        if organisation.collections.isEmpty {
                            QuidCard {
                                Text("No collections yet")
                                    .font(.quidSubheadline)
                                    .foregroundStyle(Color.quidMuted)
                            }
                        } else {
                            QuidCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(organisation.collections.enumerated()), id: \.element.id) { index, collection in
                                        NavigationLink(value: collection) {
                                            CollectionRow(collection: collection)
                                        }
                                        .buttonStyle(.plain)
                                        if index < organisation.collections.count - 1 {
                                            QuidDivider().padding(.leading, 16)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }
}

struct CollectionRow: View {
    let collection: CollectionSummaryDTO

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(collection.title)
                        .font(.quidHeadline)
                        .foregroundStyle(Color.quidInk)
                    if collection.status == .closed {
                        StatusPill(text: "Closed", tone: .neutral)
                    }
                }
                Text(subtitle)
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                ProgressView(value: Double(collection.paidCount), total: Double(max(collection.memberCount, 1)))
                    .tint(Color.quidAccentText)
                Text("\(collection.paidCount) of \(collection.memberCount) paid")
                    .font(.quidCaption)
                    .foregroundStyle(Color.quidMuted)
            }
            QuidChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        var parts = ["\(Money(minor: collection.amountPerPersonMinor).formatted(compact: true)) each"]
        if let dueAt = collection.dueAt {
            parts.append(dueAt.quidDueDescription)
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Collect") {
    CollectView(api: .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken)))
        .environment(AppEnvironment.demo())
}
