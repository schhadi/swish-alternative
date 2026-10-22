import SwiftUI
import Observation

/// Works out what a split link means for the signed-in user: their own split (detail), a request in it addressed to
/// them (pay or decline), or neither.
@MainActor
@Observable
final class SplitLinkViewModel {
    enum Resolution {
        case loading
        case mine(SplitDTO)
        case forMe(PaymentRequestDTO)
        case notFound
        case failed(AppError)
    }

    let splitId: String
    private(set) var state: Resolution = .loading
    let api: APIClient

    init(api: APIClient, splitId: String) {
        self.api = api
        self.splitId = splitId
    }

    func resolve() async {
        state = .loading
        do {
            state = .mine(try await api.send(API.split(id: splitId)))
            return
        } catch is CancellationError {
            return
        } catch AppError.notFound {
            // Not the creator: look for the request in it that is addressed to this user.
        } catch let appError as AppError {
            state = .failed(appError)
            return
        } catch {
            state = .failed(.unknown(error.localizedDescription))
            return
        }
        do {
            let incoming = try await api.send(API.requests(role: .incoming))
            if let request = incoming.requests.first(where: { $0.splitId == splitId }) {
                state = .forMe(request)
            } else {
                state = .notFound
            }
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            state = .failed(appError)
        } catch {
            state = .failed(.unknown(error.localizedDescription))
        }
    }
}

struct SplitLinkView: View {
    @State private var viewModel: SplitLinkViewModel
    @Environment(\.dismiss) private var dismiss

    init(api: APIClient, splitId: String) {
        _viewModel = State(initialValue: SplitLinkViewModel(api: api, splitId: splitId))
    }

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") { dismiss() }
                            .font(.quidSubheadline)
                            .accessibilityIdentifier("link.close")
                    }
                }
        }
        .tint(Color.quidAccentText)
        .task { await viewModel.resolve() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingView()
                .background(Color.quidBackground)
        case .mine(let split):
            SplitDetailView(api: viewModel.api, split: split)
        case .forMe(let request):
            IncomingRequestDetailView(api: viewModel.api, request: request)
        case .notFound:
            VStack {
                EmptyStateView(systemImage: "link", title: "This split isn't for you", message: "It may have been sent to someone else, or it was removed.")
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.quidBackground)
        case .failed(let error):
            VStack {
                ErrorStateView(error: error) { await viewModel.resolve() }
                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.quidBackground)
        }
    }
}
