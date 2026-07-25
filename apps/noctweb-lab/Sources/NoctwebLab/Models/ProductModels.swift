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
        case .finalize: "Finalize"
        case .replicate: "Replicate"
        case .verify: "Verify"
        }
    }

    var systemImage: String {
        switch self {
        case .draft: "pencil.line"
        case .validate: "checkmark.seal"
        case .sign: "signature"
        case .finalize: "checkmark.circle"
        case .replicate: "square.3.layers.3d"
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
}

enum TrustEvidenceKind: String, CaseIterable, Codable, Identifiable {
    case objectIntegrity
    case publicationIdentity
    case consensusFinality
    case replication

    var id: Self { self }

    var title: String {
        switch self {
        case .objectIntegrity: "Object integrity"
        case .publicationIdentity: "Publication identity"
        case .consensusFinality: "Consensus finality"
        case .replication: "Host replication"
        }
    }

    var systemImage: String {
        switch self {
        case .objectIntegrity: "number"
        case .publicationIdentity: "signature"
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

struct SiteProject: Identifiable, Codable, Hashable {
    let id: UUID
    var address: String
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
}

enum RouteMode: String, CaseIterable, Identifiable {
    case direct
    case passthrough

    var id: Self { self }

    var title: String {
        switch self {
        case .direct: "Direct"
        case .passthrough: "Passthrough"
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
    let title: String
    let subtitle: String
    let body: String
    let accentHex: String
    let revision: UInt64
    let objectID: String
    let publisherID: String
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
}

extension Workspace {
    static func starter() -> Workspace {
        Workspace(
            id: UUID(),
            name: "Local development",
            createdAt: Date(),
            sites: [
                SiteProject(
                    id: UUID(),
                    address: "noct://quiet-garden/",
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
                    publicationIdentity: .pending
                )
            ],
            relays: RelayTopology.labDefault.nodes.map { node in
                LabRelayNode(
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
                    retainedObjects: 0
                )
            },
            runs: []
        )
    }
}
