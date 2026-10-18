import SwiftUI

/// Every payment, grouped by day, with search and a Sent / Received filter.
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
                } else if viewModel.isLoading && viewModel.payments.isEmpty {
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
                    list
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

    private var list: some View {
        List {
            Section {
                Picker("Filter", selection: $viewModel.filter) {
                    ForEach(ActivityFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if viewModel.sections.isEmpty {
                Section {
                    Text("Nothing matches \u{201C}\(viewModel.searchText)\u{201D}.")
                        .font(.quidSubheadline)
                        .foregroundStyle(Color.quidMuted)
                        .listRowBackground(Color.quidSurface)
                }
            }
            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.payments) { payment in
                        NavigationLink(value: payment) {
                            PaymentRow(payment: payment, currentUserId: viewModel.currentUserId)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 16))
                        .listRowBackground(Color.quidSurface)
                    }
                } header: {
                    Text(section.title)
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.quidBackground)
    }
}

#Preview("Activity") {
    ActivityView(api: .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken)))
        .environment(AppEnvironment.demo())
}
