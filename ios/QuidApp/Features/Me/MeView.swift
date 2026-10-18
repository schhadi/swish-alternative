import SwiftUI

/// Profile, linked bank, limits, notifications, legal, sign out and delete account.
struct MeView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var viewModel: MeViewModel
    @State private var placeholder: PhasePlaceholder?
    @State private var showDeleteConfirmation = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    init(api: APIClient) {
        _viewModel = State(initialValue: MeViewModel(api: api))
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                bankSection
                limitsSection
                notificationsSection
                legalSection
                accountSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.quidBackground)
            .navigationTitle("Me")
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .confirmationDialog("Delete your account?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    Task {
                        if await viewModel.deleteAccount() {
                            appEnvironment.session.signOut()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your bank details and phone number are removed straight away. Past payments stay in other people's activity with your name removed.")
            }
        }
        .sheet(item: $placeholder) { PhasePlaceholderSheet(placeholder: $0) }
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                Avatar(name: viewModel.me?.user.displayName ?? "", size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.me?.user.displayName ?? "Loading")
                        .font(.quidTitle3)
                        .foregroundStyle(Color.quidInk)
                    Text(MeViewModel.formattedPhone(viewModel.me?.user.phoneE164))
                        .font(.quidSubheadline)
                        .foregroundStyle(Color.quidMuted)
                }
            }
            .padding(.vertical, 6)
            .redacted(reason: viewModel.me == nil ? .placeholder : [])
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.quidSurface)
    }

    private var bankSection: some View {
        Section("Linked bank") {
            if let bank = viewModel.me?.bankAccount {
                HStack {
                    MeRow(systemImage: "building.columns", title: bank.bankName)
                    StatusPill(text: bank.copStatus.label, tone: bank.copStatus.pillTone)
                }
                if let until = bank.coolingOffUntil, until > Date() {
                    Text("You can receive payments again from \(until.quidReceiptDescription).")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidPendingText)
                }
                Button {
                    placeholder = .changeBank
                } label: {
                    MeRow(systemImage: "arrow.triangle.2.circlepath", title: "Change bank account")
                }
            } else if let error = viewModel.error, viewModel.me == nil {
                Text(error.userMessage)
                    .font(.quidSubheadline)
                    .foregroundStyle(Color.quidFailureText)
            } else {
                MeRow(systemImage: "building.columns", title: viewModel.me == nil ? "Loading" : "No bank linked yet")
                    .redacted(reason: viewModel.me == nil ? .placeholder : [])
            }
        }
        .listRowBackground(Color.quidSurface)
    }

    private var limitsSection: some View {
        Section {
            let limits = viewModel.me?.limits
            MeRow(systemImage: "arrow.up.right", title: "Per payment", value: limits.map { Money(minor: $0.perPaymentMinor).formatted(compact: true) })
            MeRow(systemImage: "sun.max", title: "Per 24 hours", value: limits.map { Money(minor: $0.rolling24hMinor).formatted(compact: true) })
            MeRow(systemImage: "calendar", title: "Per 30 days", value: limits.map { Money(minor: $0.rolling30dMinor).formatted(compact: true) })
        } header: {
            Text("Limits")
        } footer: {
            Text("Limits are set by Quid, not your bank, and apply to payments you send.")
        }
        .listRowBackground(Color.quidSurface)
    }

    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle(isOn: $notificationsEnabled) {
                MeRow(systemImage: "bell", title: "Payment updates")
            }
            .tint(Color.quidAccent)
        }
        .listRowBackground(Color.quidSurface)
    }

    private var legalSection: some View {
        Section("Legal") {
            Link(destination: AppConfig.privacyURL) {
                MeRow(systemImage: "hand.raised", title: "Privacy policy")
            }
            Link(destination: AppConfig.termsURL) {
                MeRow(systemImage: "doc.text", title: "Terms of use")
            }
        }
        .listRowBackground(Color.quidSurface)
    }

    private var accountSection: some View {
        Section {
            Button("Sign out") {
                appEnvironment.session.signOut()
            }
            .font(.quidBody)
            .foregroundStyle(Color.quidInk)
            Button("Delete account", role: .destructive) {
                showDeleteConfirmation = true
            }
            .font(.quidBody)
            .disabled(viewModel.isDeleting)
        } footer: {
            Text("Quid \(AppConfig.appVersion) (\(AppConfig.buildNumber))\(appEnvironment.isMock ? " · Demo data" : "")")
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
        .listRowBackground(Color.quidSurface)
    }
}

/// Settings-style row: icon tile, title, optional trailing value.
struct MeRow: View {
    let systemImage: String
    let title: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.quidAccentText)
                .frame(width: 30, height: 30)
                .background(Color.quidSuccessTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.quidBody)
                .foregroundStyle(Color.quidInk)
            Spacer()
            if let value {
                Text(value)
                    .font(.quidSubheadline)
                    .foregroundStyle(Color.quidMuted)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview("Me") {
    MeView(api: .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken)))
        .environment(AppEnvironment.demo())
}
