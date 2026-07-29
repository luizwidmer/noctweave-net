import Foundation
import NoctwebLabCore

enum ProductSection: String, CaseIterable, Identifiable {
    case overview
    case sites
    case runtime
    case network
    case testRuns
    case inspector
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .sites: "Sites"
        case .runtime: "Noctweb Runtime"
        case .network: "Network"
        case .testRuns: "Test Runs"
        case .inspector: "Inspector"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .sites: "rectangle.stack"
        case .runtime: "safari"
        case .network: "point.3.connected.trianglepath.dotted"
        case .testRuns: "checklist"
        case .inspector: "scope"
        case .settings: "gearshape"
        }
    }
}

enum PublicationStage: Int, CaseIterable, Codable, Identifiable {
    case draft
    case validate
    case sign
    case finalize
    case replicate
    case verify

    var id: Self { self }

    var title: String {
        switch self {
        case .draft: "Draft"
        case .validate: "Validate"
        case .sign: "Sign"
        case .finalize: "Host"
        case .replicate: "Fetch"
        case .verify: "Verify"
        }
    }

    var systemImage: String {
        switch self {
        case .draft: "pencil.line"
        case .validate: "checkmark.seal"
        case .sign: "signature"
        case .finalize: "externaldrive.badge.plus"
        case .replicate: "arrow.down.doc"
        case .verify: "shield.checkered"
        }
    }
}

enum PublicationOutcome: String, Codable {
    case ready
    case running
    case succeeded
    case failed
}

enum PublicationIdentityStatus: String, Codable {
    case pending
    case ready
    case locked
    case unavailable

    var title: String {
        switch self {
        case .pending: "Created securely on first publish"
        case .ready: "Local signing authority ready"
        case .locked: "Signing authority locked"
        case .unavailable: "Signing authority unavailable"
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "key.horizontal"
        case .ready: "key.fill"
        case .locked: "lock.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }
}

struct PublisherIdentityDeletionTombstone: Codable, Hashable {
    let siteID: UUID
    let publicationID: String
    let requestedAt: Date
}

struct PublisherIdentityDeletionJournal: Codable, Equatable {
    var pending: [PublisherIdentityDeletionTombstone]

    static let empty = PublisherIdentityDeletionJournal(pending: [])
}

enum LabRelayRole: String, CaseIterable, Codable, Identifiable {
    case standard
    case passthrough
    case host

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: "Standard relay"
        case .passthrough: "Passthrough relay"
        case .host: "Host relay"
        }
    }

    var shortTitle: String {
        switch self {
        case .standard: "Standard"
        case .passthrough: "Passthrough"
        case .host: "Host"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: "arrow.left.arrow.right"
        case .passthrough: "arrow.triangle.swap"
        case .host: "externaldrive.connected.to.line.below"
        }
    }

    var module: RelayModule {
        switch self {
        case .standard: .standard
        case .passthrough: .passthrough
        case .host: .host
        }
    }
}

struct LabRelayNode: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var role: LabRelayRole
    var endpoint: String
    var region: String
    var isOnline: Bool
    var latencyMilliseconds: Int
    var retainedObjects: Int
    var relayNamespaceID: String? = nil
    var namespaceSuffix: String? = nil
    var advertisedModules: [RelayModule]? = nil
    var operatorRouteDirective: RouteDirective? = nil

    var modules: [RelayModule] {
        let configured = Set(
            (advertisedModules ?? [role.module]) + [role.module]
        )
        return RelayModule.allCases.filter {
            configured.contains($0)
        }
    }

    func supports(_ role: LabRelayRole) -> Bool {
        modules.contains(role.module)
    }

    var resolvedOperatorRouteDirective: RouteDirective {
        operatorRouteDirective ?? .open
    }
}

enum TrustEvidenceKind: String, CaseIterable, Codable, Identifiable {
    case objectIntegrity
    case publicationIdentity
    case hostReceipt
    case consensusFinality
    case replication

    var id: Self { self }

    var title: String {
        switch self {
        case .objectIntegrity: "Object integrity"
        case .publicationIdentity: "Publication identity"
        case .hostReceipt: "Host receipt"
        case .consensusFinality: "Consensus finality"
        case .replication: "Host replication"
        }
    }

    var systemImage: String {
        switch self {
        case .objectIntegrity: "number"
        case .publicationIdentity: "signature"
        case .hostReceipt: "externaldrive.badge.checkmark"
        case .consensusFinality: "checkmark.seal"
        case .replication: "square.3.layers.3d"
        }
    }
}

enum EvidenceState: String, Codable {
    case pending
    case accepted
    case warning
    case rejected

    var title: String {
        switch self {
        case .pending: "Pending"
        case .accepted: "Accepted"
        case .warning: "Attention"
        case .rejected: "Rejected"
        }
    }
}

struct TrustEvidence: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: TrustEvidenceKind
    var state: EvidenceState
    var summary: String
    var detail: String
    var checkedAt: Date?
}

enum SiteProjectKind: String, Codable, CaseIterable {
    case visual
    case imported

    var title: String {
        switch self {
        case .visual: "Visual project"
        case .imported: "Standard web project"
        }
    }
}

enum SiteBlockKind: String, Codable, CaseIterable, Identifiable {
    case hero
    case text
    case feature
    case callToAction

    var id: Self { self }

    var title: String {
        switch self {
        case .hero: "Hero"
        case .text: "Text"
        case .feature: "Feature"
        case .callToAction: "Call to action"
        }
    }

    var systemImage: String {
        switch self {
        case .hero: "rectangle.topthird.inset.filled"
        case .text: "text.alignleft"
        case .feature: "sparkles.rectangle.stack"
        case .callToAction: "cursorarrow.click.2"
        }
    }
}

struct SiteBlock: Identifiable, Codable, Hashable {
    let id: UUID
    var kind: SiteBlockKind
    var eyebrow: String
    var heading: String
    var body: String
    var buttonLabel: String
    var buttonURL: String

    static func blank(_ kind: SiteBlockKind) -> SiteBlock {
        switch kind {
        case .hero:
            SiteBlock(
                id: UUID(),
                kind: .hero,
                eyebrow: "Welcome",
                heading: "A remarkable website",
                body: "Tell visitors what makes this project worth exploring.",
                buttonLabel: "Learn more",
                buttonURL: "#content"
            )
        case .text:
            SiteBlock(
                id: UUID(),
                kind: .text,
                eyebrow: "",
                heading: "Your story",
                body: "Write clear, useful content here.",
                buttonLabel: "",
                buttonURL: ""
            )
        case .feature:
            SiteBlock(
                id: UUID(),
                kind: .feature,
                eyebrow: "Feature",
                heading: "Built for the open web",
                body: "HTML, CSS, JavaScript, images, and compiled framework assets travel together.",
                buttonLabel: "",
                buttonURL: ""
            )
        case .callToAction:
            SiteBlock(
                id: UUID(),
                kind: .callToAction,
                eyebrow: "Next step",
                heading: "Ready to publish?",
                body: "Create a signed revision and replicate it through host relays.",
                buttonLabel: "Get started",
                buttonURL: "#"
            )
        }
    }
}

struct SiteSourceFile: Identifiable, Codable, Hashable {
    let id: UUID
    var path: String
    var mediaType: String
    var bytes: Data

    init(
        id: UUID = UUID(),
        path: String,
        mediaType: String,
        bytes: Data
    ) {
        self.id = id
        self.path = path
        self.mediaType = mediaType
        self.bytes = bytes
    }

    var isText: Bool {
        mediaType.hasPrefix("text/") ||
            mediaType.contains("javascript") ||
            mediaType.contains("json") ||
            mediaType.contains("xml") ||
            ["html", "htm", "css", "js", "mjs", "jsx", "ts", "tsx", "svg"]
                .contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    var text: String? {
        get {
            guard isText else { return nil }
            return String(data: bytes, encoding: .utf8)
        }
        set {
            guard let newValue else { return }
            bytes = Data(newValue.utf8)
        }
    }
}

struct SiteProject: Identifiable, Codable, Hashable {
    let id: UUID
    var address: String
    var relayNamespaceID: String? = nil
    var publisherRouteDirective: RouteDirective? = nil
    var title: String
    var subtitle: String
    var body: String
    var accentHex: String
    var revision: Int
    var lastPublishedAt: Date?
    var objectID: String?
    var headID: String?
    var publisherID: String?
    var publishedEnvelope: Data?
    var publicationIdentity: PublicationIdentityStatus
    var projectKind: SiteProjectKind? = nil
    var entryPath: String? = nil
    var files: [SiteSourceFile]? = nil
    var blocks: [SiteBlock]? = nil
    var hostRelayEndpoint: String? = nil
    var hostObjectID: String? = nil
    var hostingReceipt: NoctwebHostingReceipt? = nil

    var resolvedProjectKind: SiteProjectKind {
        projectKind ?? .visual
    }

    var resolvedEntryPath: String {
        entryPath ?? "index.html"
    }

    var resolvedFiles: [SiteSourceFile] {
        files ?? []
    }

    var resolvedBlocks: [SiteBlock] {
        blocks ?? []
    }

    var resolvedPublisherRouteDirective: RouteDirective {
        publisherRouteDirective ?? .open
    }
}

struct WebsiteRoutingContext: Equatable {
    let publisherDirective: RouteDirective
    let hostRelayIDs: Set<String>?
    let usesSignedPublication: Bool
}

enum RouteMode: String, CaseIterable, Identifiable {
    case automatic
    case direct
    case passthrough

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .direct: "Direct"
        case .passthrough: "One-hop"
        }
    }

    var directive: RouteDirective {
        switch self {
        case .automatic: .open
        case .direct: .direct
        case .passthrough: .passthrough
        }
    }
}

enum RuntimeResult: Equatable {
    case idle
    case resolved(snapshot: ResolvedSiteSnapshot, relayPath: [String])
    case unavailable(message: String)
    case rejected(message: String)
}

struct ResolvedSiteSnapshot: Equatable {
    let sourceSiteID: UUID
    let address: String
    let relayNamespaceID: String?
    let title: String
    let subtitle: String
    let body: String
    let accentHex: String
    let revision: UInt64
    let objectID: String
    let publisherID: String
    let bundle: WebsiteBundle
    let routingDecision: RoutingDecision
}

enum FaultKind: String, Codable {
    case hostOffline
    case corruptedObject
    case passthroughOffline
    case standardRelayLatency
}

struct FaultScenario: Identifiable, Hashable {
    let id: UUID
    var name: String
    var summary: String
    var fault: FaultKind
    var expectedResult: String
}

enum TestRunResult: String, Codable {
    case passed
    case failed
}

struct ScenarioRun: Identifiable, Codable, Hashable {
    let id: UUID
    var scenarioName: String
    var startedAt: Date
    var durationMilliseconds: Int
    var result: TestRunResult
    var assertion: String
    var events: [String]
}

struct Workspace: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sites: [SiteProject]
    var relays: [LabRelayNode]
    var runs: [ScenarioRun]
    var federationMode: FederationMode? = nil
    var federationRouteDirective: RouteDirective? = nil

    var resolvedFederationMode: FederationMode {
        federationMode ?? .solo
    }

    var resolvedFederationRouteDirective: RouteDirective {
        federationRouteDirective ?? .open
    }
}

extension Workspace {
    static func liveStarter() -> Workspace {
        Workspace(
            id: UUID(),
            name: "Hosted development",
            createdAt: Date(),
            sites: [],
            relays: [
                LabRelayNode(
                    id: "local-host-relay",
                    name: "Local host relay",
                    role: .host,
                    endpoint: "http://127.0.0.1:9440",
                    region: "Local",
                    isOnline: false,
                    latencyMilliseconds: 0,
                    retainedObjects: 0,
                    advertisedModules: [.host],
                    operatorRouteDirective: .open
                )
            ],
            runs: [],
            federationMode: .solo,
            federationRouteDirective: .open
        )
    }

    static func starter() -> Workspace {
        let topology = RelayTopology.labDefault
        let primaryNamespace = try! topology.nodes
            .first { $0.id == "host-lisbon" }!
            .relayNamespace()!
        return Workspace(
            id: UUID(),
            name: "Local development",
            createdAt: Date(),
            sites: [
                SiteProject(
                    id: UUID(),
                    address: try! NoctwebAddress(
                        siteLabel: "quiet-garden",
                        relaySuffix: primaryNamespace.suffix
                    ).canonicalString,
                    relayNamespaceID: primaryNamespace.id,
                    publisherRouteDirective: .open,
                    title: "A garden with no address",
                    subtitle: "Field notes from a site that belongs to its publisher, not its host.",
                    body: """
                    This page is reconstructed from verified objects. Its host can change without changing what it is.

                    Use the network workspace to take a relay offline, alter a stored object, or reroute retrieval. The runtime keeps the publication address stable and separates each piece of trust evidence.
                    """,
                    accentHex: "#4F8F77",
                    revision: 0,
                    lastPublishedAt: nil,
                    objectID: nil,
                    headID: nil,
                    publisherID: nil,
                    publishedEnvelope: nil,
                    publicationIdentity: .pending,
                    projectKind: .visual,
                    entryPath: "index.html",
                    files: nil,
                    blocks: [
                        SiteBlock(
                            id: UUID(),
                            kind: .hero,
                            eyebrow: "Verified Noctweb publication",
                            heading: "A garden with no address",
                            body: "Field notes from a site that belongs to its publisher, not its host.",
                            buttonLabel: "Explore the project",
                            buttonURL: "#content"
                        ),
                        SiteBlock(
                            id: UUID(),
                            kind: .text,
                            eyebrow: "",
                            heading: "A website reconstructed from verified objects",
                            body: """
                            This page is reconstructed from verified objects. Its host can change without changing what it is.

                            Use the network workspace to take a relay offline, alter a stored object, or reroute retrieval. The runtime keeps the publication address stable and separates each piece of trust evidence.
                            """,
                            buttonLabel: "",
                            buttonURL: ""
                        )
                    ]
                )
            ],
            relays: topology.nodes.map { node in
                let namespace = try? node.relayNamespace()
                return LabRelayNode(
                    id: node.id,
                    name: node.name,
                    role: LabRelayRole(rawValue: node.role.rawValue)!,
                    endpoint: node.endpoint.absoluteString,
                    region: node.name.replacingOccurrences(
                        of: " Host",
                        with: ""
                    ),
                    isOnline: node.isOnline,
                    latencyMilliseconds: node.role == .standard ? 18 :
                        (node.role == .passthrough ? 41 : 32),
                    retainedObjects: 0,
                    relayNamespaceID: namespace?.id,
                    namespaceSuffix: namespace?.suffix,
                    advertisedModules: node.modules,
                    operatorRouteDirective: node.routeDirective
                )
            },
            runs: [],
            federationMode: topology.federationPolicy.mode,
            federationRouteDirective: topology.federationPolicy.directive
        )
    }
}

extension FederationMode {
    var title: String {
        switch self {
        case .solo: "Solo"
        case .manual: "Manual"
        case .curated: "Curated"
        case .open: "Open"
        }
    }
}

extension RouteDirective {
    var title: String {
        switch self {
        case .open: "Leave open"
        case .direct: "Require direct"
        case .passthrough: "Require one-hop"
        }
    }

    var shortTitle: String {
        switch self {
        case .open: "Open"
        case .direct: "Direct"
        case .passthrough: "One-hop"
        }
    }
}

extension RoutingAuthority {
    var title: String {
        switch self {
        case .federation: "Federation"
        case .relayOperator: "Relay operator"
        case .publisher: "Publisher"
        case .visitor: "Visitor"
        case .defaultDirect: "Safe default"
        }
    }
}
