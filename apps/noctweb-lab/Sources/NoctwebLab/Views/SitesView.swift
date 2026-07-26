import SwiftUI

private enum SiteDestructiveAction {
    case removeProject(SiteProject)
    case destroyIdentity(SiteProject)

    var site: SiteProject {
        switch self {
        case let .removeProject(site), let .destroyIdentity(site):
            site
        }
    }

    var title: String {
        switch self {
        case let .removeProject(site):
            "Remove \(site.title) from this Mac?"
        case .destroyIdentity:
            "Destroy the publisher key?"
        }
    }

    var message: String {
        switch self {
        case let .removeProject(site):
            "This deletes the local editor project and its \(site.resolvedFiles.count) files. Published revisions are immutable and may remain on host relays. Choose whether to retain the publisher key or destroy it permanently with the project."
        case let .destroyIdentity(site):
            "This permanently removes the local signing authority for \(site.address). Existing published revisions remain verifiable, but this Lab will no longer be able to publish updates under that identity."
        }
    }
}

struct SitesView: View {
    @EnvironmentObject private var model: AppModel

    @State private var destructiveAction: SiteDestructiveAction?

    var body: some View {
        GeometryReader { proxy in
            if model.activeWorkspace == nil {
                selectedWorkspace(width: proxy.size.width)
            } else if proxy.size.width >= siteLibraryBreakpoint {
                HStack(spacing: 0) {
                    siteLibrary
                        .frame(width: 244)
                    Divider()
                    selectedWorkspace(width: proxy.size.width - 245)
                }
            } else {
                VStack(spacing: 0) {
                    compactSiteSelector
                    Divider()
                    selectedWorkspace(width: proxy.size.width)
                }
            }
        }
        .confirmationDialog(
            destructiveAction?.title ?? "Confirm action",
            isPresented: destructiveActionBinding,
            titleVisibility: .visible,
            presenting: destructiveAction
        ) { action in
            switch action {
            case let .removeProject(site):
                Button("Remove Project, Keep Key", role: .destructive) {
                    _ = model.deleteSite(site.id)
                    destructiveAction = nil
                }
                .disabled(
                    model.identityPreparationSiteIDs.contains(site.id)
                )
                if site.publicationIdentity != .unavailable {
                    Button("Destroy Key & Remove Project", role: .destructive) {
                        destructiveAction = nil
                        Task {
                            if await model.destroyPublisherIdentity(for: site.id) {
                                _ = model.deleteSite(site.id)
                            }
                        }
                    }
                    .disabled(
                        model.identityPreparationSiteIDs.contains(site.id)
                    )
                }
            case let .destroyIdentity(site):
                Button("Destroy Key Permanently", role: .destructive) {
                    destructiveAction = nil
                    Task {
                        _ = await model.destroyPublisherIdentity(for: site.id)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                destructiveAction = nil
            }
        } message: { action in
            Text(action.message)
        }
    }

    @ViewBuilder
    private func selectedWorkspace(width: CGFloat) -> some View {
        if model.activeWorkspace == nil {
            VStack(spacing: 14) {
                ContentUnavailableView(
                    "No Workspace",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Create a local workspace to begin building Noctweb sites.")
                )
                Button("Create Workspace") {
                    model.createWorkspace()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let site = model.selectedSite {
            siteWorkspace(site, width: width)
        } else {
            VStack(spacing: 14) {
                ContentUnavailableView(
                    "No Sites Yet",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text(
                        "Start visually or create a site and import an agent-built production bundle."
                    )
                )
                Button("Create Site") {
                    model.createSite()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var siteLibrary: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sites")
                        .font(.title2.weight(.semibold))
                    Text("\(model.activeWorkspace?.sites.count ?? 0) local projects")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.createSite()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create a site")
            }
            .padding(14)

            Divider()

            List(selection: siteSelection) {
                ForEach(model.activeWorkspace?.sites ?? []) { site in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(site.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(site.address)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(site.lastPublishedAt == nil ? .orange : .green)
                                    .frame(width: 6, height: 6)
                                Text(
                                    site.lastPublishedAt == nil
                                        ? "Draft"
                                        : "Revision \(site.revision)"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }

                        Spacer(minLength: 2)

                        siteActionMenu(site, iconOnly: true)
                    }
                    .padding(.vertical, 5)
                    .tag(Optional(site.id))
                    .contextMenu {
                        siteContextActions(site)
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .background(.regularMaterial)
    }

    private var compactSiteSelector: some View {
        HStack(spacing: 10) {
            Picker("Site", selection: siteSelection) {
                if model.selectedSiteID == nil {
                    Text("Select a site")
                        .tag(UUID?.none)
                }
                ForEach(model.activeWorkspace?.sites ?? []) { site in
                    Text(site.title)
                        .tag(Optional(site.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 330, alignment: .leading)

            Spacer(minLength: 6)

            Button {
                model.createSite()
            } label: {
                Label("New Site", systemImage: "plus")
            }
            .help("Create a site")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(.regularMaterial)
    }

    private func siteWorkspace(_ site: SiteProject, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            publicationHeader(site, compact: width < headerBreakpoint)
            Divider()
            WebsiteProjectEditorView(site: site)
        }
    }

    private func publicationHeader(_ site: SiteProject, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    siteIdentity(site, compact: compact)
                    Spacer(minLength: 12)
                    publicationActions(site)
                }

                VStack(alignment: .leading, spacing: 10) {
                    siteIdentity(site, compact: true)
                    publicationActions(site)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    PublicationPipeline(
                        activeStage: model.publicationStage,
                        outcome: model.publicationOutcome
                    )
                    .frame(maxWidth: 610, alignment: .leading)
                    Spacer(minLength: 8)
                    publicationStatus
                        .frame(maxWidth: 360, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 8) {
                    PublicationPipeline(
                        activeStage: model.publicationStage,
                        outcome: model.publicationOutcome
                    )
                    publicationStatus
                }
            }
        }
        .padding(.horizontal, compact ? 14 : 20)
        .padding(.vertical, compact ? 12 : 15)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func siteIdentity(_ site: SiteProject, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(site.title)
                .font(compact ? .title2.weight(.semibold) : .title.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(site.address)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                StatusPill(
                    title: site.publicationIdentity == .ready
                        ? "Publisher secured"
                        : site.publicationIdentity.title,
                    systemImage: site.publicationIdentity.systemImage,
                    color: site.publicationIdentity == .ready ? .green : .orange
                )
            }
        }
    }

    private func publicationActions(_ site: SiteProject) -> some View {
        HStack(spacing: 8) {
            if model.publicationInFlight {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                model.publishSelectedSite()
            } label: {
                Label(
                    model.publicationInFlight
                        ? "Publishing…"
                        : "Publish Revision",
                    systemImage: "paperplane.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                model.publicationInFlight ||
                    site.publicationIdentity != .ready
            )

            siteActionMenu(site, iconOnly: false)
        }
    }

    private var publicationStatus: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: outcomeImage)
                .foregroundStyle(outcomeColor)
            Text(model.publicationMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func siteActionMenu(_ site: SiteProject, iconOnly: Bool) -> some View {
        Menu {
            siteContextActions(site)
        } label: {
            if iconOnly {
                Image(systemName: "ellipsis")
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "ellipsis.circle")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Site actions")
    }

    @ViewBuilder
    private func siteContextActions(_ site: SiteProject) -> some View {
        Button {
            model.runtimeAddress = site.address
            model.selection = .runtime
            model.navigateRuntime()
        } label: {
            Label("Open Published Site", systemImage: "safari")
        }
        .disabled(site.lastPublishedAt == nil)

        Divider()

        Button(role: .destructive) {
            destructiveAction = .removeProject(site)
        } label: {
            Label("Remove Local Project…", systemImage: "trash")
        }
        .disabled(
            model.publicationInFlight ||
                model.identityOperationSiteID == site.id ||
                model.identityPreparationSiteIDs.contains(site.id)
        )

        Button(role: .destructive) {
            destructiveAction = .destroyIdentity(site)
        } label: {
            Label("Destroy Publisher Key…", systemImage: "key.slash")
        }
        .disabled(
            site.publisherID == nil ||
                site.publicationIdentity == .unavailable ||
                model.publicationInFlight ||
                model.identityOperationSiteID != nil ||
                model.identityPreparationSiteIDs.contains(site.id)
        )
    }

    private var siteSelection: Binding<UUID?> {
        Binding(
            get: { model.selectedSiteID },
            set: { model.selectSite($0) }
        )
    }

    private var destructiveActionBinding: Binding<Bool> {
        Binding(
            get: { destructiveAction != nil },
            set: { if !$0 { destructiveAction = nil } }
        )
    }

    private var outcomeImage: String {
        switch model.publicationOutcome {
        case .ready: "circle.dotted"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var outcomeColor: Color {
        switch model.publicationOutcome {
        case .ready: .secondary
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        }
    }

    private let siteLibraryBreakpoint: CGFloat = 1_220
    private let headerBreakpoint: CGFloat = 760
}
