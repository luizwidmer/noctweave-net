import NoctwebUI
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
    @State private var showsRelayAuthorization = false

    var body: some View {
        GeometryReader { proxy in
            if model.activeWorkspace == nil {
                selectedWorkspace(width: proxy.size.width)
            } else if model.activeWorkspace?.sites.isEmpty != false {
                selectedWorkspace(width: proxy.size.width)
            } else if proxy.size.width >= siteLibraryBreakpoint {
                HStack(spacing: 0) {
                    siteLibrary
                        .frame(width: 264)
                    Divider()
                    selectedWorkspace(
                        width: proxy.size.width - 265,
                        showsSitePicker: false
                    )
                }
            } else {
                selectedWorkspace(
                    width: proxy.size.width,
                    showsSitePicker: true
                )
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
    private func selectedWorkspace(
        width: CGFloat,
        showsSitePicker: Bool = false
    ) -> some View {
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
            siteWorkspace(
                site,
                width: width,
                showsSitePicker: showsSitePicker
            )
                .id(site.id)
        } else if model.activeWorkspace?.relays.contains(where: { $0.supports(.host) }) != true {
            VStack(spacing: 16) {
                Image(systemName: "network.slash")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(NoctwebTheme.accent)
                    .frame(width: 70, height: 70)
                    .background(NoctwebTheme.status, in: Circle())
                Text("Connect a host relay")
                    .font(.title2.weight(.semibold))
                Text(
                    "Noctweb Lab publishes only through relays you configure. Add a real host relay before creating your first site."
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                Button {
                    model.selection = .network
                } label: {
                    Label("Add Relay", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 520)
            .background(
                NoctwebTheme.card,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(NoctwebTheme.border, lineWidth: 1)
            }
            .shadow(color: NoctwebTheme.softShadow, radius: 22, y: 10)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(NoctwebTheme.accent)
                    .frame(width: 70, height: 70)
                    .background(NoctwebTheme.status, in: Circle())
                Text("Create your first site")
                    .font(.title2.weight(.semibold))
                Text("Start with a clean website project, then design, preview, and publish from one place.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                Button {
                    model.createSite()
                } label: {
                    Label("New Site", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(maxWidth: 520)
            .background(
                NoctwebTheme.card,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(NoctwebTheme.border, lineWidth: 1)
            }
            .shadow(color: NoctwebTheme.softShadow, radius: 22, y: 10)
            .padding(32)
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
                    Label("New", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Create a site")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

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
        .background(.ultraThinMaterial)
    }

    private func siteWorkspace(
        _ site: SiteProject,
        width: CGFloat,
        showsSitePicker: Bool
    ) -> some View {
        VStack(spacing: 0) {
            if showsSitePicker {
                compactWorkspaceHeader(site)
            } else {
                publicationHeader(site, compact: width < headerBreakpoint)
            }
            Divider()
            WebsiteProjectEditorView(site: site)
        }
    }

    private func compactWorkspaceHeader(_ site: SiteProject) -> some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                compactSitePicker(site)
                    .layoutPriority(1)

                Button {
                    model.createSite()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help("Create a site")

                publisherIdentityBadge(site)
                relayAuthorizationButton

                Button {
                    model.publishSelectedSite()
                } label: {
                    Label(
                        model.publicationInFlight ? "Publishing…" : "Publish",
                        systemImage: "paperplane.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.publicationInFlight ||
                        site.publicationIdentity != .ready
                )

                siteActionMenu(site, iconOnly: true)
            }

            compactPublicationStatus
        }
        .controlSize(.regular)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }

    private func compactSitePicker(_ site: SiteProject) -> some View {
        Menu {
            ForEach(model.activeWorkspace?.sites ?? []) { candidate in
                Button {
                    selectSiteAfterInteraction(candidate.id)
                } label: {
                    if candidate.id == model.selectedSiteID {
                        Label(candidate.title, systemImage: "checkmark")
                    } else {
                        Text(candidate.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "rectangle.stack")
                    .foregroundStyle(NoctwebTheme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(site.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(site.address)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(minWidth: 180, maxWidth: 330, alignment: .leading)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1))
        }
        .accessibilityLabel("Site")
        .accessibilityValue(site.title)
    }

    private func publisherIdentityBadge(_ site: SiteProject) -> some View {
        Image(systemName: site.publicationIdentity.systemImage)
            .foregroundStyle(
                site.publicationIdentity == .ready ? Color.green : Color.orange
            )
            .frame(width: 32, height: 32)
            .background(
                (site.publicationIdentity == .ready ? Color.green : Color.orange)
                    .opacity(0.12),
                in: Circle()
            )
            .help(
                site.publicationIdentity == .ready
                    ? "Publisher secured"
                    : site.publicationIdentity.title
            )
            .accessibilityLabel(
                site.publicationIdentity == .ready
                    ? "Publisher secured"
                    : site.publicationIdentity.title
            )
    }

    private func publicationHeader(_ site: SiteProject, compact: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                siteIdentity(site, compact: compact)
                Spacer(minLength: 12)
                publicationStatus
                    .frame(maxWidth: 280, alignment: .trailing)
                publicationActions(site)
            }

            VStack(alignment: .leading, spacing: 12) {
                siteIdentity(site, compact: true)
                publicationStatus
                publicationActions(site)
            }
        }
        .padding(.horizontal, compact ? 14 : 20)
        .padding(.vertical, compact ? 12 : 14)
        .background(.ultraThinMaterial)
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
            relayAuthorizationButton

            if model.publicationInFlight {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                model.publishSelectedSite()
            } label: {
                Label(
                    model.publicationInFlight ? "Publishing…" : "Publish",
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

    private var relayAuthorizationButton: some View {
        Button {
            showsRelayAuthorization.toggle()
        } label: {
            Image(
                systemName: model.relayPublisherAuthorization.isEmpty
                    ? "key.horizontal"
                    : "key.horizontal.fill"
            )
        }
        .buttonStyle(.bordered)
        .help("Relay publishing access")
        .accessibilityLabel("Relay publishing access")
        .popover(isPresented: $showsRelayAuthorization, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Relay access", systemImage: "key.horizontal")
                    .font(.headline)
                Text(
                    "Only needed when this host relay requires a publisher password. It stays in memory for this app session."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                SecureField(
                    "Relay password",
                    text: $model.relayPublisherAuthorization
                )
                .textFieldStyle(.roundedBorder)
                .privacySensitive()
                .onSubmit {
                    showsRelayAuthorization = false
                }

                HStack {
                    Spacer()
                    Button("Done") {
                        showsRelayAuthorization = false
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .frame(width: 300)
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

    private var compactPublicationStatus: some View {
        HStack(spacing: 7) {
            Image(systemName: outcomeImage)
                .foregroundStyle(outcomeColor)
            Text(model.publicationMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(model.publicationMessage)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .menuIndicator(.hidden)
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
            set: { selectSiteAfterInteraction($0) }
        )
    }

    private func selectSiteAfterInteraction(_ siteID: UUID?) {
        // Let AppKit finish dismissing a menu or settling a list selection
        // before replacing the complete editor hierarchy.
        Task { @MainActor in
            await Task.yield()
            model.selectSite(siteID)
        }
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
