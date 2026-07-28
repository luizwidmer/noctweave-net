import Dispatch
import Foundation
import NoctwebLabCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: ProductSection? = .overview
    @Published private(set) var workspaces: [Workspace]
    @Published var activeWorkspaceID: UUID?
    @Published var selectedSiteID: UUID?
    @Published private(set) var publicationStage: PublicationStage = .draft
    @Published private(set) var publicationOutcome: PublicationOutcome = .ready
    @Published private(set) var publicationMessage = "Draft is ready for validation."
    @Published private(set) var publicationInFlight = false
    @Published private(set) var identityOperationSiteID: UUID?
    @Published private(set) var identityPreparationSiteIDs = Set<UUID>()
    @Published private(set) var trustEvidence: [TrustEvidence] = AppModel.pendingEvidence()
    @Published var routeMode: RouteMode = .direct
    @Published var runtimeAddress = ""
    @Published private(set) var runtimeResult: RuntimeResult = .idle
    @Published private(set) var runtimeHistory: [String] = []
    @Published private(set) var runtimeHistoryIndex = -1
    @Published var selectedScenarioID: UUID?
    @Published var inspectorEvidenceID: UUID?
    @Published var preserveRunHistory = true
    @Published private(set) var operationError: String?

    let scenarios: [FaultScenario] = [
        FaultScenario(
            id: UUID(),
            name: "Host relay outage",
            summary: "Take every host relay offline and confirm retrieval fails closed.",
            fault: .hostOffline,
            expectedResult: "No unverified substitute is rendered."
        ),
        FaultScenario(
            id: UUID(),
            name: "Corrupted hosted object",
            summary: "Alter the only reachable replica while its finalized object identifier remains unchanged.",
            fault: .corruptedObject,
            expectedResult: "Digest mismatch is rejected before rendering."
        ),
        FaultScenario(
            id: UUID(),
            name: "Passthrough interruption",
            summary: "Disable the bounded passthrough route and compare direct retrieval.",
            fault: .passthroughOffline,
            expectedResult: "Passthrough fails while direct verified retrieval remains available."
        ),
        FaultScenario(
            id: UUID(),
            name: "Standard relay isolation",
            summary: "Disable private Noctweave transport and prove public host resolution remains independent.",
            fault: .standardRelayLatency,
            expectedResult: "Consensus-finalized host resolution does not depend on a standard relay."
        ),
    ]

    private let engine: NoctwebLabEngine
    private let workspaceFileURL: URL
    private let identityDeletionJournalFileURL: URL
    private let persistenceQueue = DispatchQueue(
        label: "org.noctweave.noctweb-lab.workspace-persistence",
        qos: .utility
    )
    private var scheduledPersistence: DispatchWorkItem?
    private var draftChangedDuringPublication = false
    private var pendingPublisherIdentityDeletions:
        [PublisherIdentityDeletionTombstone] = []

    init(
        engine: NoctwebLabEngine? = nil,
        workspaceFileURL: URL? = nil
    ) {
        self.engine = engine ?? (try! NoctwebLabEngine(
            identityStore: KeychainPublicationIdentityStore()
        ))
        let resolvedWorkspaceFileURL =
            workspaceFileURL ?? Self.defaultWorkspaceFileURL()
        self.workspaceFileURL = resolvedWorkspaceFileURL
        self.identityDeletionJournalFileURL =
            Self.publisherIdentityDeletionJournalURL(
                for: resolvedWorkspaceFileURL
            )

        if
            let data = try? Data(
                contentsOf: self.identityDeletionJournalFileURL
            ),
            let journal = try? JSONDecoder().decode(
                PublisherIdentityDeletionJournal.self,
                from: data
            )
        {
            var seenSiteIDs = Set<UUID>()
            pendingPublisherIdentityDeletions = journal.pending.filter {
                seenSiteIDs.insert($0.siteID).inserted
            }
        }

        let initialWorkspaces: [Workspace]
        if
            let data = try? Data(contentsOf: self.workspaceFileURL),
            let decoded = try? JSONDecoder().decode([Workspace].self, from: data)
        {
            initialWorkspaces = decoded
        } else {
            initialWorkspaces = [.starter()]
        }
        workspaces = initialWorkspaces
        Self.migrateRelayNamespaces(in: &workspaces)
        Self.migrateRoutingPolicies(in: &workspaces)
        for workspaceIndex in workspaces.indices {
            for siteIndex in workspaces[workspaceIndex].sites.indices {
                WebsiteProjectBuilder.ensureProject(
                    &workspaces[workspaceIndex].sites[siteIndex]
                )
            }
        }

        activeWorkspaceID = workspaces.first?.id
        selectedSiteID = workspaces.first?.sites.first?.id
        runtimeAddress = workspaces.first?.sites.first?.address ?? ""
        selectedScenarioID = scenarios.first?.id
        inspectorEvidenceID = trustEvidence.first?.id

        Task { [weak self] in
            await self?.restoreEngineState()
            await self?.reconcilePendingPublisherIdentityDeletions()
            await self?.prepareMissingPublisherIdentities()
        }
    }

    var activeWorkspace: Workspace? {
        guard let activeWorkspaceID else { return nil }
        return workspaces.first(where: { $0.id == activeWorkspaceID })
    }

    var selectedSite: SiteProject? {
        guard let selectedSiteID else { return nil }
        return activeWorkspace?.sites.first(where: { $0.id == selectedSiteID })
    }

    var selectedWebsiteRoutingContext: WebsiteRoutingContext {
        guard let site = selectedSite else {
            return WebsiteRoutingContext(
                publisherDirective: .open,
                hostRelayIDs: nil,
                usesSignedPublication: false
            )
        }
        guard let publication = try? publishedCapsule(from: site) else {
            return WebsiteRoutingContext(
                publisherDirective: site.resolvedPublisherRouteDirective,
                hostRelayIDs: nil,
                usesSignedPublication: false
            )
        }
        return WebsiteRoutingContext(
            publisherDirective:
                publication.head.claims.routeDirective ?? .open,
            hostRelayIDs: Set(publication.hostRelayIDs),
            usesSignedPublication: true
        )
    }

    var selectedScenario: FaultScenario? {
        guard let selectedScenarioID else { return nil }
        return scenarios.first(where: { $0.id == selectedScenarioID })
    }

    var selectedEvidence: TrustEvidence? {
        guard let inspectorEvidenceID else { return nil }
        return trustEvidence.first(where: { $0.id == inspectorEvidenceID })
    }

    var availableRelayNamespaces: [LabRelayNode] {
        activeWorkspace?.relays.filter {
            $0.supports(.host) &&
                $0.relayNamespaceID != nil &&
                $0.namespaceSuffix != nil
        } ?? []
    }

    var canGoBack: Bool {
        runtimeHistoryIndex > 0
    }

    var canGoForward: Bool {
        runtimeHistoryIndex >= 0 && runtimeHistoryIndex < runtimeHistory.count - 1
    }

    func createWorkspace() {
        var workspace = Workspace.starter()
        workspace.name = "Workspace \(workspaces.count + 1)"
        workspace.sites = []
        workspace.runs = []
        workspaces.append(workspace)
        activeWorkspaceID = workspace.id
        selectedSiteID = nil
        persist()
    }

    func createSite() {
        guard let workspaceIndex = activeWorkspaceIndex else {
            operationError = "Create or select a workspace before adding a site."
            return
        }
        let number = workspaces[workspaceIndex].sites.count + 1
        guard
            let namespaceRelay = workspaces[workspaceIndex].relays.first(
                where: {
                    $0.supports(.host) &&
                        $0.relayNamespaceID != nil &&
                        $0.namespaceSuffix != nil
                }
            ),
            let relayNamespaceID = namespaceRelay.relayNamespaceID,
            let namespaceSuffix = namespaceRelay.namespaceSuffix,
            let address = try? NoctwebAddress(
                siteLabel: "untitled-\(number)",
                relaySuffix: namespaceSuffix
            ).canonicalString
        else {
            operationError =
                "Configure at least one host relay namespace before creating a site."
            return
        }
        var site = SiteProject(
            id: UUID(),
            address: address,
            relayNamespaceID: relayNamespaceID,
            title: "Untitled publication",
            subtitle: "A new site for Noctweb.",
            body: "Start writing here.",
            accentHex: "#4F8F77",
            revision: 0,
            lastPublishedAt: nil,
            objectID: nil,
            headID: nil,
            publisherID: nil,
            publishedEnvelope: nil,
            publicationIdentity: .pending
        )
        WebsiteProjectBuilder.ensureProject(&site)
        workspaces[workspaceIndex].sites.append(site)
        selectedSiteID = site.id
        resetPublication()
        persist()
        Task { [weak self] in
            await self?.preparePublisherIdentity(for: site.id)
        }
    }

    func selectWorkspace(_ id: UUID?) {
        guard id != activeWorkspaceID else { return }
        activeWorkspaceID = id
        selectedSiteID = activeWorkspace?.sites.first?.id
        runtimeAddress = selectedSite?.address ?? ""
        resetPublication()
        Task { [weak self] in
            await self?.applyActiveRelayState()
        }
    }

    func selectSite(_ id: UUID?) {
        selectedSiteID = id
        runtimeAddress = selectedSite?.address ?? runtimeAddress
        resetPublication()
    }

    func updateSelectedSite(_ update: (inout SiteProject) -> Void) {
        guard
            let workspaceIndex = activeWorkspaceIndex,
            let selectedSiteID,
            let siteIndex = workspaces[workspaceIndex].sites.firstIndex(
                where: { $0.id == selectedSiteID }
            )
        else { return }

        update(&workspaces[workspaceIndex].sites[siteIndex])
        markDraftChanged()
    }

    func selectRelayNamespace(_ relayNamespaceID: String) {
        guard
            let site = selectedSite,
            site.publishedEnvelope == nil,
            let relay = availableRelayNamespaces.first(where: {
                $0.relayNamespaceID == relayNamespaceID
            }),
            let suffix = relay.namespaceSuffix
        else { return }

        let siteLabel: String
        if let parsed = try? NoctwebAddress.parse(site.address) {
            siteLabel = parsed.siteLabel
        } else if let legacy = Self.legacySiteLabel(from: site.address) {
            siteLabel = legacy
        } else {
            siteLabel = "untitled"
        }
        guard
            let address = try? NoctwebAddress(
                siteLabel: siteLabel,
                relaySuffix: suffix
            ).canonicalString
        else { return }

        updateSelectedSite {
            $0.address = address
            $0.relayNamespaceID = relayNamespaceID
        }
    }

    func setPublisherRouteDirective(_ directive: RouteDirective) {
        updateSelectedSite {
            $0.publisherRouteDirective = directive
        }
    }

    func setFederationMode(_ mode: FederationMode) {
        guard let workspaceIndex = activeWorkspaceIndex else { return }
        workspaces[workspaceIndex].federationMode = mode
        if mode == .solo {
            workspaces[workspaceIndex].federationRouteDirective = .open
        }
        persist()
        Task { [weak self] in
            await self?.applyActiveRelayState()
        }
    }

    func setFederationRouteDirective(_ directive: RouteDirective) {
        guard
            let workspaceIndex = activeWorkspaceIndex,
            workspaces[workspaceIndex].resolvedFederationMode != .solo
        else { return }
        workspaces[workspaceIndex].federationRouteDirective = directive
        persist()
        Task { [weak self] in
            await self?.applyActiveRelayState()
        }
    }

    func setRelayOperatorRouteDirective(
        _ directive: RouteDirective,
        relayID: String
    ) {
        guard
            let workspaceIndex = activeWorkspaceIndex,
            let relayIndex = workspaces[workspaceIndex].relays.firstIndex(
                where: { $0.id == relayID && $0.supports(.host) }
            )
        else { return }
        workspaces[workspaceIndex].relays[relayIndex]
            .operatorRouteDirective = directive
        persist()
        Task { [weak self] in
            await self?.applyActiveRelayState()
        }
    }

    func updateSelectedVisualSite(_ update: (inout SiteProject) -> Void) {
        guard
            let workspaceIndex = activeWorkspaceIndex,
            let selectedSiteID,
            let siteIndex = workspaces[workspaceIndex].sites.firstIndex(
                where: { $0.id == selectedSiteID }
            )
        else { return }

        update(&workspaces[workspaceIndex].sites[siteIndex])
        WebsiteProjectBuilder.synchronizeVisualProject(
            &workspaces[workspaceIndex].sites[siteIndex]
        )
        markDraftChanged()
    }

    func addBlock(_ kind: SiteBlockKind) {
        updateSelectedVisualSite { site in
            var blocks = site.resolvedBlocks
            blocks.append(.blank(kind))
            site.blocks = blocks
        }
    }

    func updateBlock(
        _ blockID: UUID,
        update: (inout SiteBlock) -> Void
    ) {
        updateSelectedVisualSite { site in
            guard
                var blocks = site.blocks,
                let index = blocks.firstIndex(where: { $0.id == blockID })
            else { return }
            update(&blocks[index])
            site.blocks = blocks
        }
    }

    func moveBlock(_ blockID: UUID, offset: Int) {
        updateSelectedVisualSite { site in
            guard
                var blocks = site.blocks,
                let source = blocks.firstIndex(where: { $0.id == blockID })
            else { return }
            let destination = source + offset
            guard blocks.indices.contains(destination) else { return }
            blocks.swapAt(source, destination)
            site.blocks = blocks
        }
    }

    func deleteBlock(_ blockID: UUID) {
        updateSelectedVisualSite { site in
            guard var blocks = site.blocks, blocks.count > 1 else { return }
            blocks.removeAll(where: { $0.id == blockID })
            site.blocks = blocks
        }
    }

    func addSourceFile(path: String) {
        let normalized = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard
            isSafeProjectPath(normalized),
            let site = selectedSite,
            !site.resolvedFiles.contains(where: {
                $0.path.caseInsensitiveCompare(normalized) == .orderedSame
            })
        else {
            operationError = "Enter a unique relative file path without '..' segments."
            return
        }
        updateSelectedSite { site in
            var files = site.resolvedFiles
            files.append(
                SiteSourceFile(
                    path: normalized,
                    mediaType: WebsiteProjectBuilder.mediaType(forPath: normalized),
                    bytes: Data()
                )
            )
            site.files = files.sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
            site.projectKind = .imported
        }
    }

    func updateSourceFile(_ fileID: UUID, text: String) {
        updateSelectedSite { site in
            guard
                var files = site.files,
                let index = files.firstIndex(where: { $0.id == fileID })
            else { return }
            files[index].text = text
            site.files = files
            site.projectKind = .imported
        }
    }

    func renameSourceFile(_ fileID: UUID, path: String) {
        let normalized = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        guard isSafeProjectPath(normalized), let site = selectedSite else {
            operationError = "Enter a relative file path without '..' segments."
            return
        }
        guard !site.resolvedFiles.contains(where: {
            $0.id != fileID &&
                $0.path.caseInsensitiveCompare(normalized) == .orderedSame
        }) else {
            operationError = "A file already uses that path."
            return
        }
        updateSelectedSite { site in
            guard
                var files = site.files,
                let index = files.firstIndex(where: { $0.id == fileID })
            else { return }
            let previousPath = files[index].path
            files[index].path = normalized
            files[index].mediaType =
                WebsiteProjectBuilder.mediaType(forPath: normalized)
            site.files = files
            if site.entryPath == previousPath {
                site.entryPath = normalized
            }
            site.projectKind = .imported
        }
    }

    func deleteSourceFile(_ fileID: UUID) {
        guard
            let site = selectedSite,
            let file = site.resolvedFiles.first(where: { $0.id == fileID })
        else { return }
        guard file.path != site.resolvedEntryPath else {
            operationError = "The entry file cannot be deleted. Choose another entry file first."
            return
        }
        updateSelectedSite { site in
            site.files?.removeAll(where: { $0.id == fileID })
            site.projectKind = .imported
        }
    }

    func clearOperationError() {
        operationError = nil
    }

    func reportOperationError(_ message: String) {
        operationError = message
    }

    func flushPersistence() {
        do {
            try saveWorkspaces()
        } catch {
            operationError =
                "Workspace could not be saved: \(error.localizedDescription)"
        }
    }

    private func markDraftChanged() {
        if publicationInFlight {
            draftChangedDuringPublication = true
            publicationMessage =
                "Publishing the captured revision. Your newer draft changes are saved separately."
            scheduleWorkspaceSave()
            return
        }
        publicationStage = .draft
        publicationOutcome = .ready
        publicationMessage = "Draft changed. Validate before publishing."
        trustEvidence = Self.pendingEvidence()
        inspectorEvidenceID = trustEvidence.first?.id
        scheduleWorkspaceSave()
    }

    func publishSelectedSite() {
        guard
            !publicationInFlight,
            let site = selectedSite,
            let workspaceID = activeWorkspaceID
        else { return }

        publicationInFlight = true
        draftChangedDuringPublication = false
        publicationOutcome = .running
        Task { [weak self] in
            await self?.executePublication(site, workspaceID: workspaceID)
        }
    }

    func resetPublication() {
        guard !publicationInFlight else { return }
        publicationStage = .draft
        publicationOutcome = .ready
        publicationMessage = "Draft is ready for validation."
        trustEvidence = Self.pendingEvidence()
        inspectorEvidenceID = trustEvidence.first?.id
    }

    func navigateRuntime() {
        let enteredAddress = runtimeAddress.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !enteredAddress.isEmpty else {
            runtimeResult = .unavailable(message: "Enter a Noctweb address.")
            return
        }
        let address: String
        if let canonical = try? NoctwebAddress.parse(enteredAddress) {
            address = canonical.canonicalString
            runtimeAddress = address
        } else if workspaces
            .flatMap(\.sites)
            .contains(where: {
                $0.address == enteredAddress &&
                    $0.publishedEnvelope != nil &&
                    $0.relayNamespaceID == nil
            })
        {
            address = enteredAddress
        } else {
            runtimeResult = .unavailable(
                message:
                    "Use a canonical address such as noct://site.relay-suffix/."
            )
            return
        }

        if runtimeHistory.last != address {
            if runtimeHistoryIndex < runtimeHistory.count - 1 {
                runtimeHistory.removeSubrange((runtimeHistoryIndex + 1)...)
            }
            runtimeHistory.append(address)
            runtimeHistoryIndex = runtimeHistory.count - 1
        }
        resolveRuntime(address)
    }

    func reloadRuntime() {
        guard
            runtimeHistoryIndex >= 0,
            runtimeHistory.indices.contains(runtimeHistoryIndex)
        else {
            navigateRuntime()
            return
        }
        resolveRuntime(runtimeHistory[runtimeHistoryIndex])
    }

    func goBack() {
        guard canGoBack else { return }
        runtimeHistoryIndex -= 1
        runtimeAddress = runtimeHistory[runtimeHistoryIndex]
        resolveRuntime(runtimeAddress)
    }

    func goForward() {
        guard canGoForward else { return }
        runtimeHistoryIndex += 1
        runtimeAddress = runtimeHistory[runtimeHistoryIndex]
        resolveRuntime(runtimeAddress)
    }

    func setRelayOnline(_ relayID: String, isOnline: Bool) {
        guard
            let workspaceIndex = activeWorkspaceIndex,
            let relayIndex = workspaces[workspaceIndex].relays.firstIndex(
                where: { $0.id == relayID }
            )
        else { return }

        workspaces[workspaceIndex].relays[relayIndex].isOnline = isOnline
        persist()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await engine.setRelayOnline(
                    isOnline,
                    relayID: relayID
                )
                reloadRuntime()
            } catch {
                publicationMessage = error.localizedDescription
            }
        }
    }

    func runSelectedScenario() {
        guard let scenario = selectedScenario else { return }
        Task { [weak self] in
            await self?.executeScenario(scenario)
        }
    }

    func clearRunHistory() {
        guard let workspaceIndex = activeWorkspaceIndex else { return }
        workspaces[workspaceIndex].runs.removeAll()
        persist()
    }

    func importWebsiteDirectory(_ url: URL) {
        operationError = nil
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let files = try WebsiteProjectBuilder.importDirectory(at: url)
            updateSelectedSite { site in
                site.projectKind = .imported
                site.entryPath = WebsiteProjectBuilder.entryPath
                site.files = files
                site.blocks = nil
                if site.title == "Untitled publication" {
                    site.title = url.deletingPathExtension().lastPathComponent
                }
                site.subtitle =
                    "Standard website bundle imported from \(url.lastPathComponent)."
            }
        } catch {
            operationError = error.localizedDescription
        }
    }

    @discardableResult
    func deleteSite(_ siteID: UUID) -> Bool {
        operationError = nil
        guard !publicationInFlight else {
            operationError = "Wait for the current publication to finish before removing a project."
            return false
        }
        guard identityOperationSiteID != siteID else {
            operationError =
                "Wait for publisher-key destruction to finish before removing this project."
            return false
        }
        guard !identityPreparationSiteIDs.contains(siteID) else {
            operationError =
                "Wait for publisher-key preparation to finish before removing this project."
            return false
        }
        guard
            let workspaceIndex = activeWorkspaceIndex,
            let siteIndex = workspaces[workspaceIndex].sites.firstIndex(
                where: { $0.id == siteID }
            )
        else { return false }

        let previousWorkspaces = workspaces
        let previousSelectedSiteID = selectedSiteID
        let previousRuntimeAddress = runtimeAddress
        let previousRuntimeHistory = runtimeHistory
        let previousRuntimeHistoryIndex = runtimeHistoryIndex
        let previousRuntimeResult = runtimeResult
        let removed = workspaces[workspaceIndex].sites.remove(at: siteIndex)

        if selectedSiteID == siteID {
            let remaining = workspaces[workspaceIndex].sites
            if remaining.indices.contains(siteIndex) {
                selectedSiteID = remaining[siteIndex].id
            } else {
                selectedSiteID = remaining.last?.id
            }
        }
        pruneRuntimeState(
            removingSiteIDs: [siteID],
            addresses: [removed.address]
        )
        runtimeAddress = selectedSite?.address ?? ""
        refreshRetainedObjectCounts(workspaceIndex: workspaceIndex)

        do {
            try saveWorkspaces()
            resetPublication()
            return true
        } catch {
            workspaces = previousWorkspaces
            selectedSiteID = previousSelectedSiteID
            runtimeAddress = previousRuntimeAddress
            runtimeHistory = previousRuntimeHistory
            runtimeHistoryIndex = previousRuntimeHistoryIndex
            runtimeResult = previousRuntimeResult
            operationError = "The project was not removed: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func deleteWorkspace(_ workspaceID: UUID) -> Bool {
        operationError = nil
        guard !publicationInFlight else {
            operationError = "Wait for the current publication to finish before removing a workspace."
            return false
        }
        guard
            let workspaceIndex = workspaces.firstIndex(
                where: { $0.id == workspaceID }
            )
        else { return false }
        if
            let identityOperationSiteID,
            workspaces[workspaceIndex].sites.contains(
                where: { $0.id == identityOperationSiteID }
            )
        {
            operationError =
                "Wait for publisher-key destruction to finish before removing this workspace."
            return false
        }
        let workspaceSiteIDs = Set(
            workspaces[workspaceIndex].sites.map(\.id)
        )
        guard identityPreparationSiteIDs.isDisjoint(with: workspaceSiteIDs) else {
            operationError =
                "Wait for publisher-key preparation to finish before removing this workspace."
            return false
        }

        let previousWorkspaces = workspaces
        let previousActiveWorkspaceID = activeWorkspaceID
        let previousSelectedSiteID = selectedSiteID
        let previousRuntimeAddress = runtimeAddress
        let previousRuntimeHistory = runtimeHistory
        let previousRuntimeHistoryIndex = runtimeHistoryIndex
        let previousRuntimeResult = runtimeResult
        let removed = workspaces.remove(at: workspaceIndex)

        if activeWorkspaceID == workspaceID {
            if workspaces.indices.contains(workspaceIndex) {
                activeWorkspaceID = workspaces[workspaceIndex].id
            } else {
                activeWorkspaceID = workspaces.last?.id
            }
            selectedSiteID = activeWorkspace?.sites.first?.id
        }
        pruneRuntimeState(
            removingSiteIDs: Set(removed.sites.map(\.id)),
            addresses: Set(removed.sites.map(\.address))
        )
        runtimeAddress = selectedSite?.address ?? ""

        do {
            try saveWorkspaces()
            resetPublication()
            Task { [weak self] in
                await self?.applyActiveRelayState()
            }
            return true
        } catch {
            workspaces = previousWorkspaces
            activeWorkspaceID = previousActiveWorkspaceID
            selectedSiteID = previousSelectedSiteID
            runtimeAddress = previousRuntimeAddress
            runtimeHistory = previousRuntimeHistory
            runtimeHistoryIndex = previousRuntimeHistoryIndex
            runtimeResult = previousRuntimeResult
            operationError = "The workspace was not removed: \(error.localizedDescription)"
            return false
        }
    }

    func destroyPublisherIdentity(for siteID: UUID) async -> Bool {
        operationError = nil
        guard !publicationInFlight else {
            operationError = "Wait for publishing to finish before destroying a publisher identity."
            return false
        }
        guard identityOperationSiteID == nil else {
            operationError = "Another publisher-key operation is still running."
            return false
        }
        guard !identityPreparationSiteIDs.contains(siteID) else {
            operationError =
                "Wait for this publisher key to finish preparing before destroying it."
            return false
        }
        guard location(of: siteID) != nil else { return false }

        identityOperationSiteID = siteID
        defer { identityOperationSiteID = nil }

        let tombstone = PublisherIdentityDeletionTombstone(
            siteID: siteID,
            publicationID: siteID.uuidString.lowercased(),
            requestedAt: Date()
        )
        do {
            try recordPublisherIdentityDeletion(tombstone)
        } catch {
            operationError =
                "The publisher key was not destroyed because the deletion request could not be saved: \(error.localizedDescription)"
            return false
        }

        do {
            try await engine.deletePublisherIdentity(
                for: tombstone.publicationID
            )
        } catch {
            operationError =
                "The publisher key could not be destroyed yet. The saved deletion request will be retried when Noctweb Lab starts: \(error.localizedDescription)"
            return false
        }

        if let location = location(of: siteID) {
            workspaces[location.workspace].sites[location.site]
                .publicationIdentity = .unavailable
            do {
                try saveWorkspaces()
            } catch {
                operationError =
                    "The publisher key was destroyed, but its local status could not be saved. The pending cleanup will be reconciled when Noctweb Lab starts: \(error.localizedDescription)"
                return true
            }
        }

        do {
            try clearPublisherIdentityDeletion(for: siteID)
        } catch {
            operationError =
                "The publisher key was destroyed, but its cleanup marker could not be cleared. Noctweb Lab will safely retry the idempotent cleanup when it starts: \(error.localizedDescription)"
        }
        return true
    }

    private func reconcilePendingPublisherIdentityDeletions() async {
        for tombstone in pendingPublisherIdentityDeletions {
            identityOperationSiteID = tombstone.siteID
            await reconcilePublisherIdentityDeletion(tombstone)
            identityOperationSiteID = nil
        }
    }

    private func reconcilePublisherIdentityDeletion(
        _ tombstone: PublisherIdentityDeletionTombstone
    ) async {
        do {
            try await engine.deletePublisherIdentity(
                for: tombstone.publicationID
            )
        } catch {
            operationError =
                "A pending publisher-key deletion could not be completed and will be retried: \(error.localizedDescription)"
            return
        }

        if let location = location(of: tombstone.siteID) {
            workspaces[location.workspace].sites[location.site]
                .publicationIdentity = .unavailable
            do {
                try saveWorkspaces()
            } catch {
                operationError =
                    "A publisher key was destroyed, but its local status could not be saved. Cleanup remains pending: \(error.localizedDescription)"
                return
            }
        }

        do {
            try clearPublisherIdentityDeletion(
                for: tombstone.siteID
            )
        } catch {
            operationError =
                "A publisher key was destroyed, but its cleanup marker could not be cleared. The idempotent cleanup remains pending: \(error.localizedDescription)"
        }
    }

    private func prepareMissingPublisherIdentities() async {
        let pendingSiteIDs = Set(
            pendingPublisherIdentityDeletions.map(\.siteID)
        )
        let siteIDs = workspaces.flatMap(\.sites).compactMap { site in
            site.publisherID == nil && !pendingSiteIDs.contains(site.id)
                ? site.id
                : nil
        }
        for siteID in siteIDs {
            await preparePublisherIdentity(for: siteID)
        }
    }

    private func preparePublisherIdentity(for siteID: UUID) async {
        guard
            location(of: siteID) != nil,
            !identityPreparationSiteIDs.contains(siteID),
            !pendingPublisherIdentityDeletions.contains(
                where: { $0.siteID == siteID }
            )
        else { return }

        identityPreparationSiteIDs.insert(siteID)
        defer { identityPreparationSiteIDs.remove(siteID) }

        do {
            let publisherID = try await engine.preparePublisherIdentity(
                for: siteID.uuidString.lowercased()
            )

            if pendingPublisherIdentityDeletions.contains(
                where: { $0.siteID == siteID }
            ) {
                do {
                    try await engine.deletePublisherIdentity(
                        for: siteID.uuidString.lowercased()
                    )
                } catch {
                    operationError =
                        "A publisher key was prepared during a pending deletion and could not be cleaned up yet: \(error.localizedDescription)"
                }
                return
            }

            guard
                let location = location(of: siteID)
            else { return }
            workspaces[location.workspace].sites[location.site].publisherID =
                publisherID
            workspaces[location.workspace].sites[location.site].publicationIdentity =
                .ready
            persist()
        } catch {
            guard
                !pendingPublisherIdentityDeletions.contains(
                    where: { $0.siteID == siteID }
                ),
                let location = location(of: siteID)
            else { return }
            workspaces[location.workspace].sites[location.site].publicationIdentity =
                .unavailable
            operationError =
                "The publisher identity could not be prepared: \(error.localizedDescription)"
            persist()
        }
    }

    private var activeWorkspaceIndex: Int? {
        guard let activeWorkspaceID else { return nil }
        return workspaces.firstIndex(where: { $0.id == activeWorkspaceID })
    }

    private func pruneRuntimeState(
        removingSiteIDs: Set<UUID>,
        addresses: Set<String>
    ) {
        runtimeHistory.removeAll(where: addresses.contains)
        if runtimeHistory.isEmpty {
            runtimeHistoryIndex = -1
        } else {
            runtimeHistoryIndex = min(
                max(runtimeHistoryIndex, 0),
                runtimeHistory.count - 1
            )
        }
        if
            case let .resolved(snapshot, _) = runtimeResult,
            removingSiteIDs.contains(snapshot.sourceSiteID)
        {
            runtimeResult = .idle
        }
    }

    private func isSafeProjectPath(_ path: String) -> Bool {
        guard
            !path.isEmpty,
            !path.hasPrefix("/"),
            !path.hasSuffix("/"),
            !path.contains("\0")
        else { return false }
        return !path
            .split(separator: "/", omittingEmptySubsequences: false)
            .contains("..")
    }

    private func executePublication(
        _ initialSite: SiteProject,
        workspaceID: UUID
    ) async {
        defer {
            publicationInFlight = false
        }
        transition(
            to: .validate,
            message: "Validating the address, entry point, file paths, media types, and bounded website bundle."
        )
        guard
            (try? NoctwebAddress.parse(initialSite.address)) != nil,
            initialSite.relayNamespaceID.map(
                RelayNamespace.isValidID
            ) == true,
            !initialSite.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            !initialSite.resolvedFiles.isEmpty,
            initialSite.resolvedFiles.contains(
                where: { $0.path == initialSite.resolvedEntryPath }
            )
        else {
            failPublication(
                "Validation failed. A title, canonical relay-scoped Noctweb address, signed namespace identity, and existing website entry file are required."
            )
            return
        }

        transition(
            to: .sign,
            message: "Signing the strict publisher-head transcript with this publication's Keychain authority."
        )

        do {
            let expectedPublisherID: String
            if let publisherID = initialSite.publisherID {
                expectedPublisherID = publisherID
            } else if
                let publication = try? publishedCapsule(
                    from: initialSite
                )
            {
                expectedPublisherID = publication.object.publisherID
            } else {
                expectedPublisherID =
                    try await engine.preparePublisherIdentity(
                        for: initialSite.id.uuidString.lowercased()
                    )
            }
            let publication = try await engine.publish(
                draft: try coreDraft(from: initialSite),
                expectedPublisherID: expectedPublisherID
            )
            transition(
                to: .finalize,
                message: "Mock consensus finalized the signed publisher head."
            )
            transition(
                to: .replicate,
                message: "The immutable object was retained by \(publication.hostRelayIDs.count) host relays."
            )

            let resolution = try await engine.resolve(
                address: publication.object.address,
                preference: coreRoute
            )
            transition(
                to: .verify,
                message: "Verifying object integrity, publisher authority, and finality independently."
            )

            guard
                let workspaceIndex = workspaces.firstIndex(
                    where: { $0.id == workspaceID }
                ),
                let siteIndex = workspaces[workspaceIndex].sites.firstIndex(
                    where: { $0.id == initialSite.id }
                )
            else {
                failPublication(
                    "The publication finished, but its local workspace was removed."
                )
                return
            }

            let envelope = try CanonicalJSON.encode(publication)
            workspaces[workspaceIndex].sites[siteIndex].revision =
                Int(publication.object.revision)
            workspaces[workspaceIndex].sites[siteIndex].lastPublishedAt = Date()
            workspaces[workspaceIndex].sites[siteIndex].objectID =
                publication.head.claims.objectID
            workspaces[workspaceIndex].sites[siteIndex].headID =
                publication.headID
            workspaces[workspaceIndex].sites[siteIndex].publisherID =
                publication.object.publisherID
            workspaces[workspaceIndex].sites[siteIndex].publishedEnvelope =
                envelope
            workspaces[workspaceIndex].sites[siteIndex].publicationIdentity =
                .ready
            refreshRetainedObjectCounts(workspaceIndex: workspaceIndex)

            trustEvidence = evidence(
                from: resolution,
                publication: publication
            )
            inspectorEvidenceID = trustEvidence.first?.id
            if draftChangedDuringPublication {
                publicationStage = .draft
                publicationOutcome = .ready
                publicationMessage =
                    "Revision \(publication.object.revision) published. Your newer draft changes are ready for another revision."
                draftChangedDuringPublication = false
            } else {
                publicationOutcome = .succeeded
                publicationMessage =
                    "Revision \(publication.object.revision) published and independently verified."
            }
            persist()

            runtimeAddress = publication.object.address
            applyResolution(
                resolution,
                sourceSiteID: initialSite.id
            )
            if runtimeHistory.last != runtimeAddress {
                runtimeHistory.append(runtimeAddress)
                runtimeHistoryIndex = runtimeHistory.count - 1
            }
        } catch {
            if
                let location = siteLocation(
                    workspaceID: workspaceID,
                    siteID: initialSite.id
                ),
                Self.isPublisherIdentityFailure(error)
            {
                workspaces[location.workspace].sites[location.site]
                    .publicationIdentity = .unavailable
            }
            failPublication(error.localizedDescription)
            trustEvidence = Self.rejectedEvidence(for: error)
            inspectorEvidenceID = trustEvidence.first?.id
        }
    }

    private func resolveRuntime(_ address: String) {
        Task { [weak self] in
            await self?.performResolution(address)
        }
    }

    private func performResolution(_ address: String) async {
        guard
            let site = workspaces
                .flatMap(\.sites)
                .first(where: { $0.address == address }),
            site.publishedEnvelope != nil
        else {
            runtimeResult = .unavailable(
                message: "No finalized local publisher head was found for this address."
            )
            return
        }

        do {
            let result = try await engine.resolve(
                address: address,
                preference: coreRoute
            )
            let publication = try publishedCapsule(from: site)
            trustEvidence = evidence(
                from: result,
                publication: publication
            )
            inspectorEvidenceID = trustEvidence.first?.id
            applyResolution(result, sourceSiteID: site.id)
        } catch {
            trustEvidence = Self.rejectedEvidence(for: error)
            inspectorEvidenceID = trustEvidence.first?.id
            if Self.isVerificationFailure(error) {
                runtimeResult = .rejected(message: error.localizedDescription)
            } else {
                runtimeResult = .unavailable(message: error.localizedDescription)
            }
        }
    }

    private func applyResolution(
        _ result: ResolutionResult,
        sourceSiteID: UUID
    ) {
        let object = result.object
        let snapshot = ResolvedSiteSnapshot(
            sourceSiteID: sourceSiteID,
            address: object.address,
            relayNamespaceID: object.relayNamespaceID,
            title: object.title,
            subtitle: object.subtitle,
            body: object.body,
            accentHex: object.accentHex,
            revision: object.revision,
            objectID: result.head.claims.objectID,
            publisherID: object.publisherID,
            bundle: object.bundle ?? legacyBundle(from: object),
            routingDecision: result.routingDecision
        )
        runtimeResult = .resolved(
            snapshot: snapshot,
            relayPath: relayPath(for: result.route)
        )
    }

    private func executeScenario(_ scenario: FaultScenario) async {
        guard
            let workspaceIndex = activeWorkspaceIndex,
            let site = selectedSite,
            let publication = try? publishedCapsule(from: site)
        else {
            recordScenario(
                scenario,
                passed: false,
                durationMilliseconds: 1,
                events: [
                    "Scenario could not start because the selected site has no verified publication receipt."
                ]
            )
            return
        }

        let startedAt = Date()
        var events: [String] = []
        var passed = false
        let relays = workspaces[workspaceIndex].relays
        let hostIDs = relays.filter { $0.supports(.host) }.map(\.id)
        let passthroughIDs = relays.filter {
            $0.supports(.passthrough)
        }.map(\.id)
        let standardIDs = relays.filter {
            $0.supports(.standard)
        }.map(\.id)

        do {
            switch scenario.fault {
            case .hostOffline:
                for id in hostIDs {
                    try await engine.setRelayOnline(false, relayID: id)
                }
                do {
                    _ = try await engine.resolve(
                        address: site.address,
                        preference: .direct
                    )
                    events.append("Unexpectedly resolved with every host offline.")
                } catch {
                    passed = true
                    events.append("All host relays were taken offline.")
                    events.append("Resolution failed: \(error.localizedDescription)")
                    events.append("No candidate bytes reached the native renderer.")
                }
                for id in hostIDs {
                    try await engine.setRelayOnline(true, relayID: id)
                }

            case .corruptedObject:
                guard let corruptedHost = hostIDs.first else {
                    throw NoctwebLabError.noHostReplica(site.address)
                }
                for id in hostIDs.dropFirst() {
                    try await engine.setRelayOnline(false, relayID: id)
                }
                try await engine.corruptReplica(
                    address: site.address,
                    hostRelayID: corruptedHost
                )
                do {
                    _ = try await engine.resolve(
                        address: site.address,
                        preference: .direct
                    )
                    events.append("Unexpectedly accepted a corrupted replica.")
                } catch {
                    passed = Self.isVerificationFailure(error)
                    events.append("The only reachable replica was altered.")
                    events.append("Verification rejected it: \(error.localizedDescription)")
                    events.append("The renderer load count remained zero.")
                }
                for id in hostIDs {
                    try await engine.setRelayOnline(true, relayID: id)
                }
                try await engine.restore(publication)

            case .passthroughOffline:
                for id in passthroughIDs {
                    try await engine.setRelayOnline(false, relayID: id)
                }
                var passthroughFailed = false
                do {
                    _ = try await engine.resolve(
                        address: site.address,
                        preference: .passthrough
                    )
                } catch {
                    passthroughFailed = true
                    events.append("Passthrough resolution failed: \(error.localizedDescription)")
                }
                let direct = try await engine.resolve(
                    address: site.address,
                    preference: .direct
                )
                passed = passthroughFailed && direct.evidence.integrity.verified
                events.append("Direct host resolution independently verified the same object.")
                for id in passthroughIDs {
                    try await engine.setRelayOnline(true, relayID: id)
                }

            case .standardRelayLatency:
                for id in standardIDs {
                    try await engine.setRelayOnline(false, relayID: id)
                }
                let direct = try await engine.resolve(
                    address: site.address,
                    preference: .direct
                )
                passed =
                    direct.evidence.integrity.verified &&
                    direct.evidence.finality.finalized
                events.append("The standard relay was isolated.")
                events.append("Consensus-finalized host resolution remained valid.")
                events.append("Private transport and public content hosting stayed separate.")
                for id in standardIDs {
                    try await engine.setRelayOnline(true, relayID: id)
                }
            }
        } catch {
            passed = false
            events.append("Scenario execution failed: \(error.localizedDescription)")
            for relay in relays {
                try? await engine.setRelayOnline(
                    true,
                    relayID: relay.id
                )
            }
            try? await engine.restore(publication)
        }

        for relayIndex in workspaces[workspaceIndex].relays.indices {
            workspaces[workspaceIndex].relays[relayIndex].isOnline = true
        }
        let elapsed = max(
            1,
            Int(Date().timeIntervalSince(startedAt) * 1_000)
        )
        recordScenario(
            scenario,
            passed: passed,
            durationMilliseconds: elapsed,
            events: events
        )
        persist()
        reloadRuntime()
    }

    private func recordScenario(
        _ scenario: FaultScenario,
        passed: Bool,
        durationMilliseconds: Int,
        events: [String]
    ) {
        guard let workspaceIndex = activeWorkspaceIndex else { return }
        let run = ScenarioRun(
            id: UUID(),
            scenarioName: scenario.name,
            startedAt: Date(),
            durationMilliseconds: durationMilliseconds,
            result: passed ? .passed : .failed,
            assertion: scenario.expectedResult,
            events: events
        )
        if preserveRunHistory {
            workspaces[workspaceIndex].runs.insert(run, at: 0)
        } else {
            workspaces[workspaceIndex].runs = [run]
        }
    }

    private func restoreEngineState() async {
        for workspace in workspaces {
            for site in workspace.sites {
                guard let publication = try? publishedCapsule(from: site) else {
                    continue
                }
                try? await engine.restore(publication)
            }
        }
        await applyActiveRelayState()
        if selectedSite?.publishedEnvelope != nil {
            navigateRuntime()
        }
    }

    private func applyActiveRelayState() async {
        guard let activeWorkspace else { return }
        let federationPolicy = FederationRoutingPolicy(
            mode: activeWorkspace.resolvedFederationMode,
            directive: activeWorkspace.resolvedFederationRouteDirective
        )
        let relayConfiguration = activeWorkspace.relays.map {
            RelayRuntimeConfiguration(
                relayID: $0.id,
                advertisedModules: $0.modules,
                operatorRouteDirective:
                    $0.resolvedOperatorRouteDirective,
                isOnline: $0.isOnline
            )
        }
        do {
            try await engine.applyRelayConfiguration(
                federationPolicy: federationPolicy,
                relays: relayConfiguration
            )
        } catch {
            operationError =
                "Could not apply relay policy: \(error.localizedDescription)"
        }
    }

    private func coreDraft(from site: SiteProject) throws -> CapsuleSiteDraft {
        CapsuleSiteDraft(
            publicationID: site.id.uuidString.lowercased(),
            address: site.address,
            relayNamespaceID: site.relayNamespaceID,
            routeDirective: site.resolvedPublisherRouteDirective,
            title: site.title,
            subtitle: site.subtitle,
            body: site.body,
            accentHex: site.accentHex,
            bundle: try WebsiteProjectBuilder.makeBundle(from: site)
        )
    }

    private func legacyBundle(from object: CapsuleObject) -> WebsiteBundle {
        let title = Self.escapeHTML(object.title)
        let subtitle = Self.escapeHTML(object.subtitle)
        let body = Self.escapeHTML(object.body)
            .replacingOccurrences(of: "\n", with: "<br>")
        let css = WebsiteProjectBuilder.legacyCSS(accentHex: object.accentHex)
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(title)</title>
          <style>\(css)</style>
        </head>
        <body>
          <h1>\(title)</h1>
          <p class="subtitle">\(subtitle)</p>
          <p>\(body)</p>
        </body>
        </html>
        """
        return WebsiteBundle(
            entryPath: "index.html",
            files: [
                WebsiteFile(
                    path: "index.html",
                    mediaType: "text/html",
                    bytes: Data(html.utf8)
                )
            ]
        )
    }

    private var coreRoute: LabRoute {
        switch routeMode {
        case .automatic: .automatic
        case .direct: .direct
        case .passthrough: .passthrough
        }
    }

    private static func migrateRelayNamespaces(
        in workspaces: inout [Workspace]
    ) {
        let defaults = RelayTopology.labDefault.nodes.reduce(
            into: [String: RelayNamespace]()
        ) { result, node in
            if let namespace = try? node.relayNamespace() {
                result[node.id] = namespace
            }
        }

        for workspaceIndex in workspaces.indices {
            for relayIndex in workspaces[workspaceIndex].relays.indices {
                let relayID = workspaces[workspaceIndex].relays[relayIndex].id
                guard let namespace = defaults[relayID] else { continue }
                if workspaces[workspaceIndex].relays[relayIndex]
                    .relayNamespaceID == nil
                {
                    workspaces[workspaceIndex].relays[relayIndex]
                        .relayNamespaceID = namespace.id
                }
                if workspaces[workspaceIndex].relays[relayIndex]
                    .namespaceSuffix == nil
                {
                    workspaces[workspaceIndex].relays[relayIndex]
                        .namespaceSuffix = namespace.suffix
                }
            }

            guard
                let primary = workspaces[workspaceIndex].relays.first(
                    where: {
                        $0.supports(.host) &&
                            $0.relayNamespaceID != nil &&
                            $0.namespaceSuffix != nil
                    }
                ),
                let primaryID = primary.relayNamespaceID,
                let primarySuffix = primary.namespaceSuffix
            else { continue }

            for siteIndex in workspaces[workspaceIndex].sites.indices {
                var site = workspaces[workspaceIndex].sites[siteIndex]
                if let envelope = site.publishedEnvelope {
                    if
                        let publication = try? CanonicalJSON.decode(
                            PublishedCapsule.self,
                            from: envelope
                        ),
                        CapsuleObject.usesRelayNamespace(
                            protocolVersion:
                                publication.object.protocolVersion
                        ),
                        CapsuleObject.usesRelayNamespace(
                            protocolVersion:
                                publication.head.claims.protocolVersion
                        ),
                        let namespaceID =
                            publication.object.relayNamespaceID,
                        publication.head.claims.relayNamespaceID ==
                            namespaceID
                    {
                        site.relayNamespaceID = namespaceID
                    } else {
                        // A signed v1 publication is immutable historical data.
                        // Never infer v2 namespace state from its dotted address.
                        site.relayNamespaceID = nil
                    }
                    workspaces[workspaceIndex].sites[siteIndex] = site
                    continue
                }
                if let parsed = try? NoctwebAddress.parse(site.address) {
                    if site.relayNamespaceID == nil,
                       let namespace = workspaces[workspaceIndex].relays.first(
                           where: { $0.namespaceSuffix == parsed.relaySuffix }
                       )?.relayNamespaceID
                    {
                        site.relayNamespaceID = namespace
                    }
                } else if
                    let label = legacySiteLabel(from: site.address),
                    let migratedAddress = try? NoctwebAddress(
                        siteLabel: label,
                        relaySuffix: primarySuffix
                    ).canonicalString
                {
                    site.address = migratedAddress
                    site.relayNamespaceID = primaryID
                }
                workspaces[workspaceIndex].sites[siteIndex] = site
            }
        }
    }

    private static func migrateRoutingPolicies(
        in workspaces: inout [Workspace]
    ) {
        let topology = RelayTopology.labDefault
        let defaultsByID = Dictionary(
            uniqueKeysWithValues: topology.nodes.map { ($0.id, $0) }
        )

        for workspaceIndex in workspaces.indices {
            if workspaces[workspaceIndex].federationMode == nil {
                workspaces[workspaceIndex].federationMode =
                    topology.federationPolicy.mode
            }
            if workspaces[workspaceIndex].federationRouteDirective == nil {
                workspaces[workspaceIndex].federationRouteDirective =
                    topology.federationPolicy.directive
            }
            if workspaces[workspaceIndex].resolvedFederationMode == .solo {
                workspaces[workspaceIndex].federationRouteDirective = .open
            }

            for relayIndex in workspaces[workspaceIndex].relays.indices {
                let relayID = workspaces[workspaceIndex].relays[relayIndex].id
                guard let defaultNode = defaultsByID[relayID] else { continue }
                if workspaces[workspaceIndex].relays[relayIndex]
                    .advertisedModules == nil
                {
                    workspaces[workspaceIndex].relays[relayIndex]
                        .advertisedModules = defaultNode.modules
                }
                if workspaces[workspaceIndex].relays[relayIndex]
                    .operatorRouteDirective == nil
                {
                    workspaces[workspaceIndex].relays[relayIndex]
                        .operatorRouteDirective = defaultNode.routeDirective
                }
            }

            for siteIndex in workspaces[workspaceIndex].sites.indices
            where workspaces[workspaceIndex].sites[siteIndex]
                .publisherRouteDirective == nil
            {
                let envelope = workspaces[workspaceIndex].sites[siteIndex]
                    .publishedEnvelope
                let signedDirective = envelope.flatMap { data in
                    (try? CanonicalJSON.decode(
                        PublishedCapsule.self,
                        from: data
                    ))?.object.routeDirective
                }
                workspaces[workspaceIndex].sites[siteIndex]
                    .publisherRouteDirective = signedDirective ?? .open
            }
        }
    }

    private static func legacySiteLabel(from address: String) -> String? {
        guard
            address.hasPrefix("noct://"),
            address.hasSuffix("/")
        else { return nil }
        let label = String(
            address
                .dropFirst("noct://".count)
                .dropLast()
        )
        guard
            !label.contains("."),
            (try? NoctwebAddress(
                siteLabel: label,
                relaySuffix: "legacy"
            )) != nil
        else { return nil }
        return label
    }

    private func publishedCapsule(
        from site: SiteProject
    ) throws -> PublishedCapsule {
        guard let envelope = site.publishedEnvelope else {
            throw NoctwebLabError.publicationNotFound(site.address)
        }
        return try CanonicalJSON.decode(
            PublishedCapsule.self,
            from: envelope
        )
    }

    private func relayPath(for route: RelayRoute) -> [String] {
        switch route {
        case let .direct(hostRelayID):
            return [hostRelayID]
        case let .passthrough(passthroughRelayID, hostRelayID):
            return [passthroughRelayID, hostRelayID]
        }
    }

    private func evidence(
        from result: ResolutionResult,
        publication: PublishedCapsule
    ) -> [TrustEvidence] {
        let now = Date()
        return [
            TrustEvidence(
                id: UUID(),
                kind: .objectIntegrity,
                state: result.evidence.integrity.verified ? .accepted : .rejected,
                summary: result.evidence.integrity.verified
                    ? "Canonical object digest matched"
                    : "Object digest rejected",
                detail:
                    "\(result.evidence.integrity.computedObjectID) matched the signed immutable object commitment.",
                checkedAt: now
            ),
            TrustEvidence(
                id: UUID(),
                kind: .publicationIdentity,
                state:
                    result.evidence.publisher.signatureValid &&
                    result.evidence.publisher.identityBound
                        ? .accepted : .rejected,
                summary: "Publication-scoped authority accepted",
                detail:
                    "\(result.evidence.publisher.derivedPublisherID) signed this head. It is a publication identity, not a global account.",
                checkedAt: now
            ),
            TrustEvidence(
                id: UUID(),
                kind: .consensusFinality,
                state: result.evidence.finality.finalized
                    ? .accepted : .rejected,
                summary: "Revision \(result.object.revision) finalized",
                detail:
                    "Mock round \(result.evidence.finality.round) reached \(result.evidence.finality.confirmations.count)/\(result.evidence.finality.quorum) confirmations.",
                checkedAt: now
            ),
            TrustEvidence(
                id: UUID(),
                kind: .replication,
                state: publication.hostRelayIDs.isEmpty ? .rejected : .accepted,
                summary:
                    "Stored on \(publication.hostRelayIDs.count) host relay\(publication.hostRelayIDs.count == 1 ? "" : "s")",
                detail:
                    "Only host relays retain the immutable object: \(publication.hostRelayIDs.joined(separator: ", ")).",
                checkedAt: now
            ),
        ]
    }

    private func transition(
        to stage: PublicationStage,
        message: String
    ) {
        publicationStage = stage
        publicationMessage = message
    }

    private func failPublication(_ message: String) {
        publicationOutcome = .failed
        publicationMessage = message
    }

    private func refreshRetainedObjectCounts(workspaceIndex: Int) {
        for relayIndex in workspaces[workspaceIndex].relays.indices {
            let relayID = workspaces[workspaceIndex].relays[relayIndex].id
            guard
                workspaces[workspaceIndex].relays[relayIndex].supports(.host)
            else {
                workspaces[workspaceIndex].relays[relayIndex].retainedObjects = 0
                continue
            }
            workspaces[workspaceIndex].relays[relayIndex].retainedObjects =
                workspaces[workspaceIndex].sites.reduce(into: 0) {
                    count,
                    site in
                    guard
                        let publication = try? publishedCapsule(from: site),
                        publication.hostRelayIDs.contains(relayID)
                    else { return }
                    count += 1
                }
        }
    }

    private func siteLocation(
        workspaceID: UUID,
        siteID: UUID
    ) -> (workspace: Int, site: Int)? {
        guard
            let workspace = workspaces.firstIndex(
                where: { $0.id == workspaceID }
            ),
            let site = workspaces[workspace].sites.firstIndex(
                where: { $0.id == siteID }
            )
        else { return nil }
        return (workspace, site)
    }

    private func location(of siteID: UUID) -> (workspace: Int, site: Int)? {
        for workspaceIndex in workspaces.indices {
            if let siteIndex = workspaces[workspaceIndex].sites.firstIndex(
                where: { $0.id == siteID }
            ) {
                return (workspaceIndex, siteIndex)
            }
        }
        return nil
    }

    private func saveWorkspaces() throws {
        scheduledPersistence?.cancel()
        scheduledPersistence = nil
        let snapshot = workspaces
        let url = workspaceFileURL
        try persistenceQueue.sync {
            try Self.writeWorkspaces(snapshot, to: url)
        }
    }

    private func recordPublisherIdentityDeletion(
        _ tombstone: PublisherIdentityDeletionTombstone
    ) throws {
        let previous = pendingPublisherIdentityDeletions
        pendingPublisherIdentityDeletions.removeAll {
            $0.siteID == tombstone.siteID
        }
        pendingPublisherIdentityDeletions.append(tombstone)
        do {
            try savePublisherIdentityDeletionJournal()
        } catch {
            pendingPublisherIdentityDeletions = previous
            throw error
        }
    }

    private func clearPublisherIdentityDeletion(
        for siteID: UUID
    ) throws {
        let previous = pendingPublisherIdentityDeletions
        pendingPublisherIdentityDeletions.removeAll {
            $0.siteID == siteID
        }
        do {
            try savePublisherIdentityDeletionJournal()
        } catch {
            pendingPublisherIdentityDeletions = previous
            throw error
        }
    }

    private func savePublisherIdentityDeletionJournal() throws {
        let snapshot = PublisherIdentityDeletionJournal(
            pending: pendingPublisherIdentityDeletions.sorted {
                $0.siteID.uuidString < $1.siteID.uuidString
            }
        )
        let url = identityDeletionJournalFileURL
        try persistenceQueue.sync {
            try Self.writePublisherIdentityDeletionJournal(
                snapshot,
                to: url
            )
        }
    }

    private func scheduleWorkspaceSave() {
        scheduledPersistence?.cancel()

        let snapshot = workspaces
        let url = workspaceFileURL
        let item = DispatchWorkItem { [weak self] in
            do {
                try Self.writeWorkspaces(snapshot, to: url)
            } catch {
                Task { @MainActor [weak self] in
                    self?.operationError =
                        "Workspace could not be saved: \(error.localizedDescription)"
                }
            }
        }
        scheduledPersistence = item
        persistenceQueue.asyncAfter(
            deadline: .now() + .milliseconds(350),
            execute: item
        )
    }

    private func persist() {
        do {
            try saveWorkspaces()
        } catch {
            operationError = error.localizedDescription
            publicationMessage =
                "Workspace could not be saved: \(error.localizedDescription)"
        }
    }

    nonisolated private static func writeWorkspaces(
        _ workspaces: [Workspace],
        to workspaceFileURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: workspaceFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoded = try JSONEncoder().encode(workspaces)
        try encoded.write(
            to: workspaceFileURL,
            options: [.atomic, .completeFileProtection]
        )
    }

    nonisolated private static func writePublisherIdentityDeletionJournal(
        _ journal: PublisherIdentityDeletionJournal,
        to journalFileURL: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: journalFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoded = try JSONEncoder().encode(journal)
        try encoded.write(
            to: journalFileURL,
            options: [.atomic, .completeFileProtection]
        )
    }

    nonisolated static func publisherIdentityDeletionJournalURL(
        for workspaceFileURL: URL
    ) -> URL {
        workspaceFileURL.appendingPathExtension(
            "publisher-key-deletions-v1.json"
        )
    }

    private static func defaultWorkspaceFileURL() -> URL {
        let support = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent(
                "Noctweave/Noctweb Lab",
                isDirectory: true
            )
            .appendingPathComponent("product-workspaces-v1.json")
    }

    private static func pendingEvidence() -> [TrustEvidence] {
        TrustEvidenceKind.allCases.map {
            TrustEvidence(
                id: UUID(),
                kind: $0,
                state: .pending,
                summary: "Not evaluated",
                detail:
                    "Publish and resolve a revision to evaluate this evidence independently.",
                checkedAt: nil
            )
        }
    }

    private static func rejectedEvidence(
        for error: any Error
    ) -> [TrustEvidence] {
        TrustEvidenceKind.allCases.map { kind in
            TrustEvidence(
                id: UUID(),
                kind: kind,
                state: kind == .replication ? .warning : .rejected,
                summary: kind == .replication
                    ? "Resolution did not complete"
                    : "Evidence was not accepted",
                detail: error.localizedDescription,
                checkedAt: Date()
            )
        }
    }

    private static func isVerificationFailure(_ error: any Error) -> Bool {
        guard let error = error as? NoctwebLabError else { return false }
        switch error {
        case .integrityMismatch,
             .publisherMismatch,
             .invalidPublisherSignature,
             .invalidFinality:
            return true
        default:
            return false
        }
    }

    private static func isPublisherIdentityFailure(
        _ error: any Error
    ) -> Bool {
        guard let error = error as? NoctwebLabError else { return false }
        switch error {
        case .identityMissing, .invalidPrivateKey, .keychainFailure:
            return true
        default:
            return false
        }
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
