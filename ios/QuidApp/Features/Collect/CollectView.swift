import SwiftUI

/// Organisations the user looks after and their collections, plus the collections the user is on the list of
/// (docs/SPEC.md section 8, screen 7).
struct CollectView: View {
    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var viewModel: CollectViewModel
    @State private var path: [CollectDestination] = []
    @State private var showingNewOrganisation = false
    @State private var newCollectionFor: OrganisationDTO?
    @State private var payingDue: CollectionDueDTO?

    init(api: APIClient) {
        _viewModel = State(initialValue: CollectViewModel(api: api))
    }

    /// A collection from the list, or one just created (which shows a short "created" banner).
    enum CollectDestination: Hashable {
        case collection(CollectionSummaryDTO)
        case created(CollectionSummaryDTO)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let error = viewModel.error, viewModel.isEmpty {
                    ErrorStateView(error: error) { await viewModel.load() }
                        .padding(16)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if viewModel.isAwaitingFirstLoad && viewModel.isEmpty {
                    LoadingView()
                } else if viewModel.isEmpty {
                    VStack(spacing: 16) {
                        EmptyStateView(
                            systemImage: "person.3",
                            title: "No organisations yet",
                            message: "Collect money for a society, sports club or flat. Set one up and share a link or QR code."
                        )
                        QuidButton(title: "Set up an organisation", systemImage: "plus") {
                            showingNewOrganisation = true
                        }
                        .accessibilityIdentifier("collect.newOrganisation")
                    }
                    .padding(16)
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    content
                }
            }
            .background(Color.quidBackground)
            .navigationTitle("Collect")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(viewModel.treasurerOrganisations) { organisation in
                            Button("New collection for \(organisation.name)", systemImage: "plus.circle") {
                                newCollectionFor = organisation
                            }
                        }
                        Button("New organisation", systemImage: "building.2") {
                            showingNewOrganisation = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("New")
                    .accessibilityIdentifier("collect.new")
                }
            }
            .navigationDestination(for: CollectDestination.self) { destination in
                switch destination {
                case .collection(let collection):
                    CollectionDetailView(api: viewModel.api, collection: collection)
                case .created(let collection):
                    CollectionDetailView(api: viewModel.api, collection: collection, justCreated: true)
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
        }
        .sheet(isPresented: $showingNewOrganisation) {
            CreateOrganisationView(api: viewModel.api) { _ in
                await viewModel.load()
            }
        }
        .sheet(item: $newCollectionFor) { organisation in
            CreateCollectionView(environment: appEnvironment, organisation: organisation) { detail in
                await viewModel.load()
                path.append(.created(detail.collection))
            }
            .environment(appEnvironment)
        }
        .fullScreenCover(item: $payingDue) { due in
            PayFlowView(environment: appEnvironment, target: nil, collectionDue: due) {
                await viewModel.load()
            }
            .environment(appEnvironment)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !viewModel.dues.isEmpty {
                    duesSection
                }
                ForEach(viewModel.organisations) { organisation in
                    organisationSection(organisation)
                }
                if viewModel.organisations.isEmpty {
                    QuidButton(title: "Set up an organisation", systemImage: "plus", style: .secondary) {
                        showingNewOrganisation = true
                    }
                    .accessibilityIdentifier("collect.newOrganisation")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    /// Collections the user has to pay (or has paid). Open, unpaid ones open the pay flow.
    private var duesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            QuidSectionHeader(title: "You're on the list", size: .small)
            QuidCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.dues.enumerated()), id: \.element.id) { index, due in
                        // Only a share still to pay is a button; a paid or closed one is information, not a disabled
                        // control, so it keeps full contrast.
                        if due.isPayable {
                            Button {
                                payingDue = due
                            } label: {
                                CollectionDueRow(due: due)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("collect.due.\(due.collectionId)")
                        } else {
                            CollectionDueRow(due: due)
                                .accessibilityIdentifier("collect.due.\(due.collectionId)")
                        }
                        if index < viewModel.dues.count - 1 {
                            QuidDivider().padding(.leading, 72)
                        }
                    }
                }
            }
        }
    }

    private func organisationSection(_ organisation: OrganisationDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(organisation.name)
                    .font(.quidTitle3)
                    .foregroundStyle(Color.quidInk)
                StatusPill(
                    text: organisation.role == .treasurer ? "Treasurer" : organisation.kind.label,
                    tone: .neutral
                )
                Spacer(minLength: 8)
                if organisation.role == .treasurer {
                    QuidPillButton(title: "New collection", style: .neutral) {
                        newCollectionFor = organisation
                    }
                    .accessibilityLabel("New collection for \(organisation.name)")
                    .accessibilityIdentifier("collect.newCollection.\(organisation.id)")
                }
            }
            .frame(minHeight: 28)
            if let bankName = organisation.bankName {
                Text("Collects into \(bankName)")
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
            }
            if organisation.collections.isEmpty {
                QuidCard {
                    Text("No collections yet. Create one and share its link or QR code.")
                        .font(.quidSubheadline)
                        .foregroundStyle(Color.quidMuted)
                }
            } else {
                QuidCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(organisation.collections.enumerated()), id: \.element.id) { index, collection in
                            NavigationLink(value: CollectDestination.collection(collection)) {
                                CollectionRow(collection: collection)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("collect.collection.\(collection.id)")
                            if index < organisation.collections.count - 1 {
                                QuidDivider().padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A collection the user is on: who is collecting, for what, how much, and whether it is paid.
struct CollectionDueRow: View {
    let due: CollectionDueDTO

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: due.organisationName, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(due.organisationName)
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                    .quidLineLimit(1)
                Text(subtitle)
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                    .quidLineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money(minor: due.amountPerPersonMinor).formatted())
                    .font(.quidHeadline)
                    .foregroundStyle(Color.quidInk)
                StatusPill(text: pillText, tone: pillTone)
            }
            if due.isPayable {
                QuidChevron()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(due.organisationName), \(due.title), \(Money(minor: due.amountPerPersonMinor).formatted()). \(pillText)")
        .accessibilityAddTraits(due.isPayable ? .isButton : [])
    }

    private var subtitle: String {
        if let paidAt = due.paidAt {
            return "\(due.title) · paid \(paidAt.quidInlineDescription)"
        }
        if let dueAt = due.dueAt {
            return "\(due.title) · \(dueAt.quidDueDescription)"
        }
        return due.title
    }

    private var pillText: String {
        if due.status == .paid { return "Paid" }
        return due.collectionStatus == .closed ? "Closed" : "To pay"
    }

    private var pillTone: StatusPill.Tone {
        if due.status == .paid { return .success }
        return due.collectionStatus == .closed ? .neutral : .pending
    }
}

struct CollectionRow: View {
    let collection: CollectionSummaryDTO

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(collection.title)
                        .font(.quidHeadline)
                        .foregroundStyle(Color.quidInk)
                    if collection.status == .closed {
                        StatusPill(text: "Closed", tone: .neutral)
                    }
                }
                Text(subtitle)
                    .font(.quidFootnote)
                    .foregroundStyle(Color.quidMuted)
                ProgressView(value: Double(collection.paidCount), total: Double(max(collection.memberCount, 1)))
                    .tint(Color.quidAccentText)
                Text("\(collection.paidCount) of \(collection.memberCount) paid")
                    .font(.quidCaption)
                    .foregroundStyle(Color.quidMuted)
            }
            QuidChevron()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var subtitle: String {
        var parts = ["\(Money(minor: collection.amountPerPersonMinor).formatted(compact: true)) each"]
        if let dueAt = collection.dueAt {
            parts.append(dueAt.quidDueDescription)
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Collect") {
    CollectView(api: .mock(tokenStore: InMemoryTokenStore(token: MockMode.sessionToken)))
        .environment(AppEnvironment.demo())
}
