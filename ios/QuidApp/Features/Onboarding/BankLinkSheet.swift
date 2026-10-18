import SwiftUI

/// Link or change the bank account from Home or Me. Wraps the form and the CoP result in its own navigation stack.
struct BankLinkSheet: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: BankLinkViewModel
    @State private var showResult = false
    let onLinked: () async -> Void

    init(api: APIClient, onLinked: @escaping () async -> Void) {
        _viewModel = State(initialValue: BankLinkViewModel(api: api))
        self.onLinked = onLinked
    }

    var body: some View {
        NavigationStack {
            BankAccountFormView(
                viewModel: viewModel,
                mode: .change,
                onSubmit: {
                    if await viewModel.submit() {
                        showResult = true
                    }
                }
            )
            .navigationDestination(isPresented: $showResult) {
                CopResultView(
                    bankLink: viewModel,
                    onContinue: {
                        appEnvironment.bankAccountLinked()
                        await onLinked()
                        dismiss()
                    },
                    onUseSuggested: { await viewModel.acceptSuggestedName() },
                    onEdit: {
                        viewModel.editAgain()
                        showResult = false
                    }
                )
                .navigationBarBackButtonHidden(true)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.quidSubheadline)
                }
            }
        }
        .tint(Color.quidAccentText)
    }
}
