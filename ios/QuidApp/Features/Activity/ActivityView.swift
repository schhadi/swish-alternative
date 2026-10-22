import SwiftUI

/// Every payment, grouped by day in cards, with search and a Sent / Received filter.
struct ActivityView: View {
    @State private var viewModel: ActivityViewModel
    private let api: APIClient

    init(api: APIClient) {
        self.api = api
        _viewModel = State(initialValue: ActivityViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let error = viewModel.error, !viewModel.hasAnything {
                    ErrorStateView(error: error) { await viewModel.load() }
                        .padding(16)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if viewModel.isAwaitingFirstLoad && !viewModel.hasAnything {
                    LoadingView()
                } else if !viewModel.hasAnything {
                    EmptyStateView(
                        systemImage: "clock",
                        title: "No activity yet",
                        message: "Payments and requests you send and receive will appear here."
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
            .navigationDestination(for: SplitDTO.self) { split in
                SplitDetailView(api: api, split: split)
            }
            .navigationDestination(for: PaymentRequestDTO.self) { request in
                IncomingRequestDetailView(api: api, request: request)
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
                .accessibilityIdentifier("activity.filter")

                if viewModel.filter == .requests {
                    requestsContent
                } else {
                    paymentsContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var paymentsContent: some View {
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

    /// The user's splits (with progress) and the requests addressed to them, each opening its detail.
    @ViewBuilder
    private var requestsContent: some View {
        if viewModel.filteredSplits.isEmpty && viewModel.filteredIncoming.isEmpty {
            EmptyStateView(
                systemImage: isSearching ? "magnifyingglass" : "arrow.down.left",
                title: isSearching ? "No matches" : "No requests yet",
                message: isSearching
                    ? "Nothing matches \u{201C}\(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}."
                    : "Ask friends for money with Request on Home. Requests sent to you show up here too."
            )
        }
        if !viewModel.filteredSplits.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                QuidSectionHeader(title: "You asked", size: .small)
                QuidCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.filteredSplits.enumerated()), id: \.element.id) { index, split in
                            NavigationLink(value: split) {
                                SplitSummaryRow(split: split)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("activity.split.\(split.id)")
                            if index < viewModel.filteredSplits.count - 1 {
                                QuidDivider().padding(.leading, 72)
                            }
                        }
                    }
                }
            }
        }
        if !viewModel.filteredIncoming.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                QuidSectionHeader(title: "Asked of you", size: .small)
                QuidCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.filteredIncoming.enumerated()), id: \.element.id) { index, request in
                            NavigationLink(value: request) {
                                IncomingRequestRow(request: request)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("activity.request.\(request.id)")
                            if index < viewModel.filteredIncoming.count - 1 {
                                QuidDivider().padding(.leading, 72)
                            }
                        }
                    }
                }
            }
        }
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
        case .all, .requests: return "No activity yet"
        }
    }

    private var emptyStateMessage: String {
        if isSearching {
            return "Nothing matches \u{201C}\(viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}."
        }
        switch viewModel.filter {
        case .sent: return "Payments you send will appear here."
        case .received: return "Payments you receive will appear here."
        case .all, .requests: return "Payments you send and receive will appear here."
        }
    }
}

#Preview("Activity") {
    ActivityView(api: .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken)))
        .environment(AppEnvironment.demo())
}
