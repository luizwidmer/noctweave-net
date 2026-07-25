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
    @Published private(set) var trustEvidence: [TrustEvidence] = AppModel.pendingEvidence()
    @Published var routeMode: RouteMode = .direct
    @Published var runtimeAddress = ""
    @Published private(set) var runtimeResult: RuntimeResult = .idle
    @Published private(set) var runtimeHistory: [String] = []
    @Published private(set) var runtimeHistoryIndex = -1
    @Published var selectedScenarioID: UUID?
    @Published var inspectorEvidenceID: UUID?
    @Published var preserveRunHistory = true

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

    init(
        engine: NoctwebLabEngine? = nil,
        workspaceFileURL: URL? = nil
    ) {
        self.engine = engine ?? (try! NoctwebLabEngine(
            identityStore: KeychainPublicationIdentityStore()
        ))
        self.workspaceFileURL =
            workspaceFileURL ?? Self.defaultWorkspaceFileURL()

        if
            let data = try? Data(contentsOf: self.workspaceFileURL),
            let decoded = try? JSONDecoder().decode([Workspace].self, from: data),
            !decoded.isEmpty
        {
            workspaces = decoded
        } else {
            workspaces = [.starter()]
        }

        activeWorkspaceID = workspaces.first?.id
        selectedSiteID = workspaces.first?.sites.first?.id
        runtimeAddress = workspaces.first?.sites.first?.address ?? ""
        selectedScenarioID = scenarios.first?.id
        inspectorEvidenceID = trustEvidence.first?.id

        Task { [weak self] in
            await self?.restoreEngineState()
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

    var selectedScenario: FaultScenario? {
        guard let selectedScenarioID else { return nil }
        return scenarios.first(where: { $0.id == selectedScenarioID })
    }

    var selectedEvidence: TrustEvidence? {
        guard let inspectorEvidenceID else { return nil }
        return trustEvidence.first(where: { $0.id == inspectorEvidenceID })
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
        guard let workspaceIndex = activeWorkspaceIndex else { return }
        let number = workspaces[workspaceIndex].sites.count + 1
        let site = SiteProject(
            id: UUID(),
            address: "noct://untitled-\(number)/",
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
        workspaces[workspaceIndex].sites.append(site)
        selectedSiteID = site.id
        resetPublication()
        persist()
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
        publicationStage = .draft
        publicationOutcome = .ready
        publicationMessage = "Draft changed. Validate before publishing."
        trustEvidence = Self.pendingEvidence()
        inspectorEvidenceID = trustEvidence.first?.id
        persist()
    }

    func publishSelectedSite() {
        guard
            publicationOutcome != .running,
            let site = selectedSite,
            let workspaceID = activeWorkspaceID
        else { return }

        publicationOutcome = .running
        Task { [weak self] in
            await self?.executePublication(site, workspaceID: workspaceID)
        }
    }

    func resetPublication() {
        publicationStage = .draft
        publicationOutcome = .ready
        publicationMessage = "Draft is ready for validation."
        trustEvidence = Self.pendingEvidence()
        inspectorEvidenceID = trustEvidence.first?.id
    }

    func navigateRuntime() {
        let address = runtimeAddress.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !address.isEmpty else {
            runtimeResult = .unavailable(message: "Enter a Noctweb address.")
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

    private var activeWorkspaceIndex: Int? {
        guard let activeWorkspaceID else { return nil }
        return workspaces.firstIndex(where: { $0.id == activeWorkspaceID })
    }

    private func executePublication(
        _ initialSite: SiteProject,
        workspaceID: UUID
    ) async {
        transition(
            to: .validate,
            message: "Validating the address, structured fields, and bounded manifest."
        )
        guard
            initialSite.address.hasPrefix("noct://"),
            !initialSite.title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            !initialSite.body.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            failPublication(
                "Validation failed. Title, body, and a noct:// address are required."
            )
            return
        }

        transition(
            to: .sign,
            message: "Signing the strict publisher-head transcript with this publication's Keychain authority."
        )

        do {
            let publication = try await engine.publish(
                draft: coreDraft(from: initialSite),
                expectedPublisherID: initialSite.publisherID
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
            publicationOutcome = .succeeded
            publicationMessage =
                "Revision \(publication.object.revision) published and independently verified."
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
                error is NoctwebLabError
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
            title: object.title,
            subtitle: object.subtitle,
            body: object.body,
            accentHex: object.accentHex,
            revision: object.revision,
            objectID: result.head.claims.objectID,
            publisherID: object.publisherID
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
        let hostIDs = relays.filter { $0.role == .host }.map(\.id)
        let passthroughIDs = relays.filter { $0.role == .passthrough }.map(\.id)
        let standardIDs = relays.filter { $0.role == .standard }.map(\.id)

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
        for relay in activeWorkspace.relays {
            try? await engine.setRelayOnline(
                relay.isOnline,
                relayID: relay.id
            )
        }
    }

    private func coreDraft(from site: SiteProject) -> CapsuleSiteDraft {
        CapsuleSiteDraft(
            publicationID: site.id.uuidString.lowercased(),
            address: site.address,
            title: site.title,
            subtitle: site.subtitle,
            body: site.body,
            accentHex: site.accentHex
        )
    }

    private var coreRoute: LabRoute {
        routeMode == .direct ? .direct : .passthrough
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
                workspaces[workspaceIndex].relays[relayIndex].role == .host
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

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: workspaceFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoded = try JSONEncoder().encode(workspaces)
            try encoded.write(
                to: workspaceFileURL,
                options: [.atomic, .completeFileProtection]
            )
        } catch {
            publicationMessage =
                "Workspace could not be saved: \(error.localizedDescription)"
        }
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
}
