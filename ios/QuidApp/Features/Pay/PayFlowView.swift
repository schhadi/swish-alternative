import SwiftUI

/// Contact picker -> amount -> (first-time warning) -> bank authorisation -> result. Presented full screen from Home.
struct PayFlowView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: PayViewModel
    @State private var picker: ContactPickerViewModel
    let onFinished: () async -> Void

    init(environment: AppEnvironment, target: PayTarget?, onFinished: @escaping () async -> Void) {
        _viewModel = State(initialValue: PayViewModel(environment: environment, target: target))
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
        .sheet(isPresented: firstTimeSheetPresented) {
            if let pending = viewModel.pendingFirstTime {
                FirstTimePayeeSheet(
                    response: pending,
                    onPay: { Task { await viewModel.confirmFirstTime() } },
                    onCancel: { viewModel.cancelFirstTime() }
                )
            }
        }
        .onChange(of: viewModel.finished) {
            if viewModel.finished {
                Task {
                    await onFinished()
                    dismiss()
                }
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
