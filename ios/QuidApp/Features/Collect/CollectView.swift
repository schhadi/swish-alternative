import SwiftUI

/// Organisations the user belongs to and their collections. Treasurer tools arrive in Phase 4.
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
                    list
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

    private var list: some View {
        List {
            ForEach(viewModel.organisations) { organisation in
                Section {
                    if organisation.collections.isEmpty {
                        Text("No collections yet")
                            .font(.quidSubheadline)
                            .foregroundStyle(Color.quidMuted)
                            .listRowBackground(Color.quidSurface)
                    }
                    ForEach(organisation.collections) { collection in
                        NavigationLink(value: collection) {
                            CollectionRow(collection: collection)
                        }
                        .listRowBackground(Color.quidSurface)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text(organisation.name)
                            .font(.quidHeadline)
                            .foregroundStyle(Color.quidInk)
                        StatusPill(text: organisation.role == .treasurer ? "Treasurer" : organisation.kind.label, tone: .neutral)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.quidBackground)
    }
}

struct CollectionRow: View {
    let collection: CollectionSummaryDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(collection.title)
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                Spacer()
                if collection.status == .closed {
                    StatusPill(text: "Closed", tone: .neutral)
                }
            }
            Text(subtitle)
                .font(.quidFootnote)
                .foregroundStyle(Color.quidMuted)
            ProgressView(value: Double(collection.paidCount), total: Double(max(collection.memberCount, 1)))
                .tint(Color.quidAccent)
            Text("\(collection.paidCount) of \(collection.memberCount) paid")
                .font(.quidCaption)
                .foregroundStyle(Color.quidMuted)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
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
