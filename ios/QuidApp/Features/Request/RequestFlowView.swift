import SwiftUI

/// Pick people -> amounts and title -> the new split's detail. Presented full screen from Home and from a payment's
/// "Split this with others".
struct RequestFlowView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RequestViewModel
    @State private var picker: ContactPickerViewModel
    let onFinished: () async -> Void

    init(environment: AppEnvironment, prefill: RequestPrefill? = nil, onFinished: @escaping () async -> Void) {
        _viewModel = State(initialValue: RequestViewModel(environment: environment, prefill: prefill))
        _picker = State(initialValue: ContactPickerViewModel(contactSource: environment.contactSource, api: environment.api))
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            ContactPickerView(
                viewModel: picker,
                isSelected: { viewModel.isSelected($0) },
                onToggle: { viewModel.toggle($0) }
            )
            .safeAreaInset(edge: .bottom) { continueBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.quidSubheadline)
                        .accessibilityIdentifier("request.cancel")
                }
            }
            .navigationDestination(for: RequestViewModel.Step.self) { step in
                switch step {
                case .amount:
                    RequestAmountView(viewModel: viewModel)
                case .sent(let split):
                    SplitDetailView(api: viewModel.api, split: split, justCreated: true) {
                        viewModel.done()
                    }
                    .navigationBarBackButtonHidden(true)
                }
            }
        }
        .tint(Color.quidAccentText)
        .interactiveDismissDisabled(viewModel.isSubmitting)
        .onChange(of: viewModel.finished) {
            if viewModel.finished {
                dismiss()
                Task { await onFinished() }
            }
        }
    }

    private var continueBar: some View {
        VStack(spacing: 8) {
            if let message = viewModel.selectionMessage {
                QuidErrorLine(message: message)
            }
            QuidButton(title: viewModel.continueTitle) {
                viewModel.continueToAmount()
            }
            .disabled(viewModel.people.isEmpty)
            .accessibilityIdentifier("request.continue")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.quidBackground)
    }
}

#Preview("Request flow") {
    RequestFlowView(environment: AppEnvironment.demo()) {}
        .environment(AppEnvironment.demo())
}
