import SwiftUI

/// Contact picker -> amount -> (first-time warning) -> bank authorisation -> result. Presented full screen from Home.
struct PayFlowView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PayViewModel
    @State private var picker: ContactPickerViewModel
    let onFinished: () async -> Void

    init(environment: AppEnvironment, target: PayTarget?, request: PaymentRequestDTO? = nil, collectionDue: CollectionDueDTO? = nil, onFinished: @escaping () async -> Void) {
        _viewModel = State(initialValue: PayViewModel(environment: environment, target: target, request: request, collectionDue: collectionDue))
        _picker = State(initialValue: ContactPickerViewModel(contactSource: environment.contactSource, api: environment.api))
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            root
                .navigationDestination(for: PayViewModel.Step.self) { step in
                    switch step {
                    case .amount:
                        AmountEntryView(viewModel: viewModel)
                    case .result:
                        PaymentResultView(viewModel: viewModel)
                            .navigationBarBackButtonHidden(true)
                    }
                }
        }
        .tint(Color.quidAccentText)
        .interactiveDismissDisabled(viewModel.path.last == .result || viewModel.isAuthorising)
        .sheet(isPresented: firstTimeSheetPresented, onDismiss: {
            // The SDK presents on the top view controller, so it must start after the sheet is fully gone.
            if viewModel.confirmedFirstTime != nil {
                Task { await viewModel.confirmFirstTime() }
            }
        }) {
            if let pending = viewModel.pendingFirstTime {
                FirstTimePayeeSheet(
                    response: pending,
                    onPay: { viewModel.acceptFirstTime() },
                    onCancel: { viewModel.cancelFirstTime() }
                )
            }
        }
        .onChange(of: viewModel.finished) {
            if viewModel.finished {
                // Drop the cover at once; Home reloads behind it.
                dismiss()
                Task { await onFinished() }
            }
        }
    }

    @ViewBuilder
    private var root: some View {
        if viewModel.rootIsPicker {
            ContactPickerView(viewModel: picker) { target in
                viewModel.select(target)
            }
            .toolbar { cancelButton }
        } else {
            AmountEntryView(viewModel: viewModel)
                .toolbar { cancelButton }
        }
    }

    private var cancelButton: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
                .font(.quidSubheadline)
                // Once the payment is being created or authorised, the only way out is the result screen.
                .disabled(viewModel.isSubmitting || viewModel.isAuthorising)
                .accessibilityIdentifier("pay.cancel")
        }
    }

    private var firstTimeSheetPresented: Binding<Bool> {
        Binding(
            get: { viewModel.pendingFirstTime != nil },
            set: { presented in if !presented { viewModel.cancelFirstTime() } }
        )
    }
}

#Preview("Pay flow") {
    PayFlowView(environment: AppEnvironment.demo(), target: nil) {}
        .environment(AppEnvironment.demo())
}
