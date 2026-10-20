import SwiftUI

/// Search your contacts; people on Quid first (tick, bank), everyone else with an Invite share button.
struct ContactPickerView: View {
    @Bindable var viewModel: ContactPickerViewModel
    let onPick: (PayTarget) -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch viewModel.permission {
                case .undetermined:
                    permissionCard(
                        title: "Find friends on Quid",
                        message: "Pick who to pay from your contacts. Numbers are scrambled on your phone before anything is sent.",
                        buttonTitle: "Allow contacts"
                    ) { Task { await viewModel.requestAccess() } }
                case .denied:
                    permissionCard(
                        title: "Contacts access is off",
                        message: "Turn it on in Settings to pick who to pay from your contacts.",
                        buttonTitle: "Open Settings"
                    ) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                case .granted:
                    searchField
                    if let error = viewModel.error, viewModel.entries.isEmpty {
                        ErrorStateView(error: error) { await viewModel.load() }
                    } else if viewModel.isLoading && !viewModel.hasLoaded {
                        LoadingView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    } else if viewModel.entries.isEmpty {
                        EmptyStateView(systemImage: "person.crop.circle.badge.questionmark", title: "No UK numbers found", message: "Add a friend's mobile number to your contacts and they'll show up here.")
                    } else if viewModel.registered.isEmpty && viewModel.others.isEmpty {
                        EmptyStateView(systemImage: "magnifyingglass", title: "No matches", message: "Nothing matches \u{201C}\(viewModel.searchText.trimmingCharacters(in: .whitespaces))\u{201D}.")
                    } else {
                        registeredSection
                        othersSection
                    }
                }
            }
            .padding(16)
        }
        .background(Color.quidBackground)
        .navigationTitle("Who are you paying?")
        .navigationBarTitleDisplayMode(.large)
        .task { await viewModel.load() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.quidMuted)
                .accessibilityHidden(true)
            TextField("Search names or numbers", text: $viewModel.searchText)
                .font(.quidBody)
                .foregroundStyle(Color.quidInk)
                .autocorrectionDisabled()
                .accessibilityIdentifier("pay.search")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Color.quidSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.quidHairline, lineWidth: 1))
    }

    @ViewBuilder
    private var registeredSection: some View {
        if !viewModel.registered.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                QuidSectionHeader(title: "On Quid", size: .small)
                QuidCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.registered.enumerated()), id: \.element.id) { index, entry in
                            if let registered = entry.registered {
                                Button {
                                    onPick(PayTarget(registered: registered))
                                } label: {
                                    ContactRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("pay.contact.\(registered.userId)")
                            }
                            if index < viewModel.registered.count - 1 {
                                QuidDivider().padding(.leading, 72)
                            }
                        }
                    }
                }
            }
        } else if viewModel.searchText.isEmpty {
            EmptyStateView(systemImage: "person.2", title: "None of your contacts are on Quid yet", message: "Invite someone below and they can get paid as soon as they've registered.")
        }
    }

    @ViewBuilder
    private var othersSection: some View {
        if !viewModel.others.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                QuidSectionHeader(title: "Invite to Quid", size: .small)
                QuidCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.others.enumerated()), id: \.element.id) { index, entry in
                            ContactRow(entry: entry)
                            if index < viewModel.others.count - 1 {
                                QuidDivider().padding(.leading, 72)
                            }
                        }
                    }
                }
            }
        }
    }

    private func permissionCard(title: String, message: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        QuidCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.quidAccentText)
                        .frame(width: 36, height: 36)
                        .background(Color.quidSuccessTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.quidHeadline)
                        .foregroundStyle(Color.quidInk)
                }
                Text(message)
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                QuidButton(title: buttonTitle, style: .secondary, action: action)
                    .accessibilityIdentifier("pay.contacts.allow")
            }
        }
    }
}

/// One contact: avatar, name, "Starling · on Quid" or the number, and a tick or an Invite button.
private struct ContactRow: View {
    let entry: ContactPickerViewModel.Entry

    private var subtitle: String {
        if let registered = entry.registered {
            if let until = registered.coolingOffUntil, until > Date() {
                return "Can receive again from \(until.quidRelativeDescription)"
            }
            if let bank = registered.bankName {
                return registered.canReceive ? "\(bank) · on Quid" : "\(bank) · can't receive yet"
            }
            return "On Quid · no bank linked yet"
        }
        return UKPhone.formatForDisplay(entry.contact.phoneE164)
    }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: entry.contact.displayName, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.contact.displayName)
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.quidFootnote)
                    .foregroundStyle(entry.registered?.canReceive == false ? Color.quidPendingText : Color.quidMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if entry.isRegistered {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.quidAccentText)
                    .accessibilityHidden(true)
                QuidChevron()
            } else {
                ShareLink(item: AppConfig.inviteURL, message: Text("I'm using Quid to pay friends by phone number. Join me:")) {
                    Text("Invite")
                        .font(.quidFootnote)
                        .foregroundStyle(Color.quidInk)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 36)
                        .background(Color.quidSurfaceSecondary, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Invite \(entry.contact.displayName) to Quid")
                .accessibilityIdentifier("pay.invite.\(entry.contact.contactId)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: entry.isRegistered ? .combine : .contain)
    }
}
