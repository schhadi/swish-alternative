import SwiftUI

/// Profile, linked bank, limits, notifications, legal, sign out and delete account, as cards.
struct MeView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var viewModel: MeViewModel
    @State private var placeholder: PhasePlaceholder?
    @State private var showDeleteConfirmation = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    init(api: APIClient) {
        _viewModel = State(initialValue: MeViewModel(api: api))
    }

    /// Nothing loaded and nothing failed: show redacted placeholders. Stays true through a cancelled load.
    private var showsPlaceholders: Bool {
        viewModel.me == nil && viewModel.error == nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if viewModel.me == nil, let error = viewModel.error {
                        // The error card stays mounted while "Try again" runs; `error` is cleared only on success.
                        ErrorStateView(error: error) { await viewModel.load() }
                    } else {
                        profileCard
                        bankSection
                        limitsSection
                    }
                    notificationsSection
                    legalSection
                    accountSection
                    Text("Quid \(AppConfig.appVersion) (\(AppConfig.buildNumber))\(appEnvironment.isMock ? " · Demo data" : "")")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidMuted)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
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
            .alert("Couldn't delete your account", isPresented: deleteErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.deleteError?.userMessage ?? "")
            }
        }
        .sheet(item: $placeholder) { PhasePlaceholderSheet(placeholder: $0) }
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.deleteError != nil },
            set: { presented in
                if !presented {
                    viewModel.deleteError = nil
                }
            }
        )
    }

    // MARK: - Sections

    private var profileCard: some View {
        QuidCard {
            HStack(spacing: 14) {
                Avatar(name: viewModel.me?.user.displayName ?? "", size: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.me?.user.displayName ?? "Your name")
                        .font(.quidTitle3)
                        .foregroundStyle(Color.quidInk)
                    Text(viewModel.me.map { MeViewModel.formattedPhone($0.user.phoneE164) } ?? "+44 0000 000000")
                        .font(.quidSubheadline)
                        .foregroundStyle(Color.quidMuted)
                }
            }
        }
        .redacted(reason: showsPlaceholders ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(profileAccessibilityLabel)
    }

    private var profileAccessibilityLabel: String {
        guard let me = viewModel.me else { return "Loading your profile" }
        return "\(me.user.displayName), \(MeViewModel.formattedPhone(me.user.phoneE164))"
    }

    private var bankSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuidSectionHeader(title: "Linked bank", size: .small)
            QuidCard(padding: 0) {
                VStack(spacing: 0) {
                    if let bank = viewModel.me?.bankAccount {
                        HStack(spacing: 12) {
                            MeRow(systemImage: "building.columns", title: bank.bankName)
                            StatusPill(text: bank.copStatus.label, tone: bank.copStatus.pillTone)
                                .padding(.trailing, 16)
                        }
                        if let until = bank.coolingOffUntil, until > Date() {
                            Text("You can receive payments again from \(until.quidReceiptDescription).")
                                .font(.quidFootnote)
                                .foregroundStyle(Color.quidPendingText)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 12)
                        }
                        QuidDivider().padding(.leading, 58)
                        Button {
                            placeholder = .changeBank
                        } label: {
                            MeRow(systemImage: "arrow.triangle.2.circlepath", title: "Change bank account", accessory: .chevron)
                        }
                        .buttonStyle(.plain)
                    } else if viewModel.me != nil {
                        MeRow(systemImage: "building.columns", title: "No bank linked yet")
                    } else {
                        MeRow(systemImage: "building.columns", title: "Loading")
                            .redacted(reason: .placeholder)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuidSectionHeader(title: "Limits", size: .small)
            QuidCard(padding: 0) {
                let limits = viewModel.me?.limits
                VStack(spacing: 0) {
                    MeRow(systemImage: "arrow.up.right", title: "Per payment", value: limits.map { Money(minor: $0.perPaymentMinor).formatted(compact: true) })
                    QuidDivider().padding(.leading, 58)
                    MeRow(systemImage: "sun.max", title: "Per 24 hours", value: limits.map { Money(minor: $0.rolling24hMinor).formatted(compact: true) })
                    QuidDivider().padding(.leading, 58)
                    MeRow(systemImage: "calendar", title: "Per 30 days", value: limits.map { Money(minor: $0.rolling30dMinor).formatted(compact: true) })
                }
                .redacted(reason: showsPlaceholders ? .placeholder : [])
            }
            Text("Limits are set by Quid, not your bank, and apply to payments you send.")
                .font(.quidFootnote)
                .foregroundStyle(Color.quidMuted)
                .padding(.horizontal, 4)
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuidSectionHeader(title: "Notifications", size: .small)
            QuidCard(padding: 0) {
                Toggle(isOn: $notificationsEnabled) {
                    MeRow(systemImage: "bell", title: "Payment updates")
                }
                .tint(Color.quidAccentText)
                .padding(.trailing, 16)
            }
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuidSectionHeader(title: "Legal", size: .small)
            QuidCard(padding: 0) {
                VStack(spacing: 0) {
                    Link(destination: AppConfig.privacyURL) {
                        MeRow(systemImage: "hand.raised", title: "Privacy policy", accessory: .externalLink)
                    }
                    .buttonStyle(.plain)
                    QuidDivider().padding(.leading, 58)
                    Link(destination: AppConfig.termsURL) {
                        MeRow(systemImage: "doc.text", title: "Terms of use", accessory: .externalLink)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var accountSection: some View {
        QuidCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    appEnvironment.session.signOut()
                } label: {
                    Text("Sign out")
                        .font(.quidBody)
                        .foregroundStyle(Color.quidInk)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                QuidDivider().padding(.leading, 16)
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Text("Delete account")
                        .font(.quidBody)
                        .foregroundStyle(Color.quidFailureText)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isDeleting)
            }
        }
    }
}

/// Settings-style row: icon tile, title, optional trailing value, and a chevron (pushes a screen) or an
/// external-link glyph (leaves the app). 52pt tall, so always a comfortable target.
struct MeRow: View {
    enum Accessory {
        case none, chevron, externalLink
    }

    let systemImage: String
    let title: String
    var value: String? = nil
    var accessory: Accessory = .none

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
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.quidSubheadline)
                    .foregroundStyle(Color.quidMuted)
            }
            switch accessory {
            case .none:
                EmptyView()
            case .chevron:
                QuidChevron()
            case .externalLink:
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.quidMuted.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#Preview("Me") {
    MeView(api: .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken)))
        .environment(AppEnvironment.demo())
}
