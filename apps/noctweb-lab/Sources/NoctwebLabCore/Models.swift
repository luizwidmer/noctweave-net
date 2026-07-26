import Foundation

public enum RelayRole: String, Codable, CaseIterable, Sendable {
    case standard
    case passthrough
    case host

    public var module: RelayModule {
        switch self {
        case .standard:
            return .standard
        case .passthrough:
            return .passthrough
        case .host:
            return .host
        }
    }
}

public enum RelayModule: String, Codable, CaseIterable, Sendable {
    case standard = "nw.opaque-route@2"
    case passthrough = "nw.net-passthrough@1"
    case host = "nw.net-host@1"
}

public struct RelayNode: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public let role: RelayRole
    public var endpoint: URL
    public var isOnline: Bool

    public var module: RelayModule {
        role.module
    }

    public init(
        id: String,
        name: String,
        role: RelayRole,
        endpoint: URL,
        isOnline: Bool = true
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.endpoint = endpoint
        self.isOnline = isOnline
    }
}

public struct RelayTopology: Codable, Equatable, Sendable {
    public var nodes: [RelayNode]

    public init(nodes: [RelayNode]) throws {
        guard Set(nodes.map(\.id)).count == nodes.count else {
            throw NoctwebLabError.invalidRelayTopology("relay IDs must be unique")
        }
        self.nodes = nodes
    }

    public func nodes(with role: RelayRole) -> [RelayNode] {
        nodes.filter { $0.role == role }
    }
}

public struct CapsuleSiteDraft: Codable, Equatable, Sendable {
    public var publicationID: String
    public var address: String
    public var title: String
    public var subtitle: String
    public var body: String
    public var accentHex: String
    public var bundle: WebsiteBundle?

    public init(
        publicationID: String,
        address: String,
        title: String,
        subtitle: String,
        body: String,
        accentHex: String,
        bundle: WebsiteBundle? = nil
    ) {
        self.publicationID = publicationID
        self.address = address
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.accentHex = accentHex
        self.bundle = bundle
    }
}

public struct CapsuleObject: Codable, Equatable, Sendable {
    public static let currentProtocolVersion = "noctweb-lab-v1"

    public let protocolVersion: String
    public let publicationID: String
    public let address: String
    public let publisherID: String
    public let revision: UInt64
    public let previousObjectID: String?
    public let title: String
    public let subtitle: String
    public let body: String
    public let accentHex: String
    public let bundle: WebsiteBundle?

    public init(
        protocolVersion: String = CapsuleObject.currentProtocolVersion,
        publicationID: String,
        address: String,
        publisherID: String,
        revision: UInt64,
        previousObjectID: String?,
        title: String,
        subtitle: String,
        body: String,
        accentHex: String,
        bundle: WebsiteBundle? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.publicationID = publicationID
        self.address = address
        self.publisherID = publisherID
        self.revision = revision
        self.previousObjectID = previousObjectID
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.accentHex = accentHex
        self.bundle = bundle
    }
}

public struct PublisherHeadClaims: Codable, Equatable, Sendable {
    public let protocolVersion: String
    public let publicationID: String
    public let address: String
    public let publisherID: String
    public let publisherPublicKey: Data
    public let objectID: String
    public let revision: UInt64
    public let previousHeadID: String?
    public let issuedAtMilliseconds: UInt64

    public init(
        protocolVersion: String = CapsuleObject.currentProtocolVersion,
        publicationID: String,
        address: String,
        publisherID: String,
        publisherPublicKey: Data,
        objectID: String,
        revision: UInt64,
        previousHeadID: String?,
        issuedAtMilliseconds: UInt64
    ) {
        self.protocolVersion = protocolVersion
        self.publicationID = publicationID
        self.address = address
        self.publisherID = publisherID
        self.publisherPublicKey = publisherPublicKey
        self.objectID = objectID
        self.revision = revision
        self.previousHeadID = previousHeadID
        self.issuedAtMilliseconds = issuedAtMilliseconds
    }
}

public struct PublisherHead: Codable, Equatable, Sendable {
    public let claims: PublisherHeadClaims
    public let signature: Data

    public init(claims: PublisherHeadClaims, signature: Data) {
        self.claims = claims
        self.signature = signature
    }
}

public struct IntegrityEvidence: Codable, Equatable, Sendable {
    public let declaredObjectID: String
    public let computedObjectID: String
    public let canonicalEncoding: Bool
    public let verified: Bool

    public init(
        declaredObjectID: String,
        computedObjectID: String,
        canonicalEncoding: Bool,
        verified: Bool
    ) {
        self.declaredObjectID = declaredObjectID
        self.computedObjectID = computedObjectID
        self.canonicalEncoding = canonicalEncoding
        self.verified = verified
    }
}

public struct PublisherEvidence: Codable, Equatable, Sendable {
    public let expectedPublisherID: String
    public let claimedPublisherID: String
    public let derivedPublisherID: String
    public let signatureValid: Bool
    public let identityBound: Bool

    public init(
        expectedPublisherID: String,
        claimedPublisherID: String,
        derivedPublisherID: String,
        signatureValid: Bool,
        identityBound: Bool
    ) {
        self.expectedPublisherID = expectedPublisherID
        self.claimedPublisherID = claimedPublisherID
        self.derivedPublisherID = derivedPublisherID
        self.signatureValid = signatureValid
        self.identityBound = identityBound
    }
}

public struct FinalityEvidence: Codable, Equatable, Sendable {
    public let headID: String
    public let round: UInt64
    public let quorum: Int
    public let confirmations: [String]
    public let receiptID: String
    public let finalized: Bool

    public init(
        headID: String,
        round: UInt64,
        quorum: Int,
        confirmations: [String],
        receiptID: String,
        finalized: Bool
    ) {
        self.headID = headID
        self.round = round
        self.quorum = quorum
        self.confirmations = confirmations
        self.receiptID = receiptID
        self.finalized = finalized
    }
}

public struct ResolutionEvidence: Codable, Equatable, Sendable {
    public let integrity: IntegrityEvidence
    public let publisher: PublisherEvidence
    public let finality: FinalityEvidence

    public init(
        integrity: IntegrityEvidence,
        publisher: PublisherEvidence,
        finality: FinalityEvidence
    ) {
        self.integrity = integrity
        self.publisher = publisher
        self.finality = finality
    }
}

public struct PublishedCapsule: Codable, Equatable, Sendable {
    public let object: CapsuleObject
    public let encodedObject: Data
    public let head: PublisherHead
    public let headID: String
    public let hostRelayIDs: [String]
    public let finality: FinalityEvidence

    public init(
        object: CapsuleObject,
        encodedObject: Data,
        head: PublisherHead,
        headID: String,
        hostRelayIDs: [String],
        finality: FinalityEvidence
    ) {
        self.object = object
        self.encodedObject = encodedObject
        self.head = head
        self.headID = headID
        self.hostRelayIDs = hostRelayIDs
        self.finality = finality
    }
}

public enum RelayRoute: Codable, Equatable, Sendable {
    case direct(hostRelayID: String)
    case passthrough(passthroughRelayID: String, hostRelayID: String)

    public var hostRelayID: String {
        switch self {
        case let .direct(hostRelayID):
            return hostRelayID
        case let .passthrough(_, hostRelayID):
            return hostRelayID
        }
    }
}

public enum LabRoute: String, Codable, CaseIterable, Sendable {
    case automatic
    case direct
    case passthrough
}

public extension RelayTopology {
    static var labDefault: RelayTopology {
        try! RelayTopology(nodes: [
            RelayNode(
                id: "standard-local",
                name: "Local Standard",
                role: .standard,
                endpoint: URL(string: "https://standard.noctweave.invalid")!
            ),
            RelayNode(
                id: "passthrough-atlantic",
                name: "Atlantic Passthrough",
                role: .passthrough,
                endpoint: URL(string: "https://passthrough.noctweave.invalid")!
            ),
            RelayNode(
                id: "host-lisbon",
                name: "Lisbon Host",
                role: .host,
                endpoint: URL(string: "https://lisbon.host.noctweave.invalid")!
            ),
            RelayNode(
                id: "host-salvador",
                name: "Salvador Host",
                role: .host,
                endpoint: URL(string: "https://salvador.host.noctweave.invalid")!
            ),
        ])
    }
}

public struct ResolutionResult: Codable, Equatable, Sendable {
    public let object: CapsuleObject
    public let head: PublisherHead
    public let headID: String
    public let route: RelayRoute
    public let evidence: ResolutionEvidence

    public init(
        object: CapsuleObject,
        head: PublisherHead,
        headID: String,
        route: RelayRoute,
        evidence: ResolutionEvidence
    ) {
        self.object = object
        self.head = head
        self.headID = headID
        self.route = route
        self.evidence = evidence
    }
}

public enum PublicationStage: String, Codable, CaseIterable, Sendable {
    case draft
    case published
}

public struct WorkspacePublication: Codable, Equatable, Identifiable, Sendable {
    public var id: String {
        draft.publicationID
    }

    public var draft: CapsuleSiteDraft
    public var trustedPublisherID: String?
    public var lastPublished: PublishedCapsule?

    public var stage: PublicationStage {
        lastPublished == nil ? .draft : .published
    }

    public init(
        draft: CapsuleSiteDraft,
        trustedPublisherID: String? = nil,
        lastPublished: PublishedCapsule? = nil
    ) {
        self.draft = draft
        self.trustedPublisherID = trustedPublisherID
        self.lastPublished = lastPublished
    }
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var selectedPublicationID: String?
    public var publications: [WorkspacePublication]
    public var relays: [RelayNode]

    public static var empty: WorkspaceSnapshot {
        WorkspaceSnapshot(
            selectedPublicationID: nil,
            publications: [],
            relays: []
        )
    }

    public init(
        schemaVersion: Int = WorkspaceSnapshot.currentSchemaVersion,
        selectedPublicationID: String?,
        publications: [WorkspacePublication],
        relays: [RelayNode]
    ) {
        self.schemaVersion = schemaVersion
        self.selectedPublicationID = selectedPublicationID
        self.publications = publications
        self.relays = relays
    }
}

public enum NoctwebLabError: Error, Equatable, Sendable {
    case invalidPublicationID(String)
    case invalidAddress(String)
    case invalidRelayTopology(String)
    case identityAlreadyExists(String)
    case identityMissing(String)
    case invalidPrivateKey(String)
    case keychainFailure(Int32)
    case canonicalEncoding(String)
    case invalidWebsiteBundle(String)
    case invalidRoute(String)
    case relayUnavailable(String)
    case noHostReplica(String)
    case finalityNotReached(required: Int, confirmed: Int)
    case publicationNotFound(String)
    case integrityMismatch(String)
    case publisherMismatch(expected: String, actual: String)
    case invalidPublisherSignature
    case invalidFinality(String)
    case workspaceSchema(Int)
    case workspaceIO(String)
}

extension NoctwebLabError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidPublicationID(value):
            return "Invalid publication ID: \(value)"
        case let .invalidAddress(value):
            return "Invalid Noctweb address: \(value)"
        case let .invalidRelayTopology(reason):
            return "Invalid relay topology: \(reason)"
        case let .identityAlreadyExists(publicationID):
            return "A publisher identity already exists for \(publicationID)."
        case let .identityMissing(publicationID):
            return "The publisher identity for \(publicationID) is missing."
        case let .invalidPrivateKey(reason):
            return "Invalid publisher private key: \(reason)"
        case let .keychainFailure(status):
            return "Keychain operation failed with OSStatus \(status)."
        case let .canonicalEncoding(reason):
            return "Canonical encoding failed: \(reason)"
        case let .invalidWebsiteBundle(reason):
            return "Invalid website bundle: \(reason)"
        case let .invalidRoute(reason):
            return "Invalid relay route: \(reason)"
        case let .relayUnavailable(relayID):
            return "Relay \(relayID) is unavailable."
        case let .noHostReplica(address):
            return "No host replica accepted \(address)."
        case let .finalityNotReached(required, confirmed):
            return "Consensus finality requires \(required) confirmations; received \(confirmed)."
        case let .publicationNotFound(address):
            return "No publication was found for \(address)."
        case let .integrityMismatch(reason):
            return "Capsule integrity verification failed: \(reason)"
        case let .publisherMismatch(expected, actual):
            return "Publisher mismatch. Expected \(expected), received \(actual)."
        case .invalidPublisherSignature:
            return "The publisher signature is invalid."
        case let .invalidFinality(reason):
            return "Consensus finality verification failed: \(reason)"
        case let .workspaceSchema(version):
            return "Unsupported workspace schema version \(version)."
        case let .workspaceIO(reason):
            return "Workspace persistence failed: \(reason)"
        }
    }
}
