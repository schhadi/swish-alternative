import SwiftUI

/// Every payment, grouped by day in cards, with search and a Sent / Received filter.
struct ActivityView: View {
    @State private var viewModel: ActivityViewModel

    init(api: APIClient) {
        _viewModel = State(initialValue: ActivityViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = viewModel.error, viewModel.payments.isEmpty {
                    ErrorStateView(error: error) { await viewModel.load() }
                        .padding(16)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if viewModel.isAwaitingFirstLoad && viewModel.payments.isEmpty {
                    LoadingView()
                } else if viewModel.payments.isEmpty {
                    EmptyStateView(
                        systemImage: "clock",
                        title: "No activity yet",
                        message: "Payments you send and receive will appear here."
                    )
                    .padding(16)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    content
                }
            }
            .background(Color.quidBackground)
            .navigationTitle("Activity")
            .navigationDestination(for: PaymentDTO.self) { payment in
                PaymentDetailView(payment: payment, currentUserId: viewModel.currentUserId)
            }
            .searchable(text: $viewModel.searchText, prompt: "Search names or references")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Filter", selection: $viewModel.filter) {
                    ForEach(ActivityFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.sections.isEmpty {
                    EmptyStateView(systemImage: emptyStateImage, title: emptyStateTitle, message: emptyStateMessage)
                }

                ForEach(viewModel.sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        QuidSectionHeader(title: section.title, size: .small)
                        QuidCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(section.payments.enumerated()), id: \.element.id) { index, payment in
                                    NavigationLink(value: payment) {
                                        PaymentRow(payment: payment, currentUserId: viewModel.currentUserId)
                                    }
                                    .buttonStyle(.plain)
                                    if index < section.payments.count - 1 {
                                        QuidDivider().padding(.leading, 72)
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

    private var isSearching: Bool {
        !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyStateImage: String {
        isSearching ? "magnifyingglass" : "tray"
    }

    private var emptyStateTitle: String {
        if isSearching { return "No matches" }
        switch viewModel.filter {
        case .sent: return "Nothing sent yet"
        case .received: return "Nothing received yet"
        case .all: return "No activity yet"
        }
    }

    private var emptyStateMessage: String {
        if isSearching {
            return "Nothing matches \u{201C}\(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}."
        }
        switch viewModel.filter {
        case .sent: return "Payments you send will appear here."
        case .received: return "Payments you receive will appear here."
        case .all: return "Payments you send and receive will appear here."
        }
    }
}

#Preview("Activity") {
    ActivityView(api: .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken)))
        .environment(AppEnvironment.demo())
}
