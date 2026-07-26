import Foundation

struct HostedPublication: Sendable {
    var encodedObject: Data
    var head: PublisherHead
    var headID: String
    var finality: FinalityEvidence?
}

public actor InMemoryRelayNetwork {
    private var nodesByID: [String: RelayNode]
    private var publicationsByHost: [String: [String: HostedPublication]]

    public init(topology: RelayTopology) {
        self.nodesByID = Dictionary(
            uniqueKeysWithValues: topology.nodes.map { ($0.id, $0) }
        )
        self.publicationsByHost = [:]
    }

    public func topology() throws -> RelayTopology {
        try RelayTopology(nodes: nodesByID.values.sorted { $0.id < $1.id })
    }

    public func setOnline(
        _ online: Bool,
        relayID: String,
        expectedRole: RelayRole? = nil
    ) throws {
        guard var node = nodesByID[relayID] else {
            throw NoctwebLabError.invalidRoute("unknown relay \(relayID)")
        }
        if let expectedRole, node.role != expectedRole {
            throw NoctwebLabError.invalidRoute(
                "\(relayID) is \(node.role.rawValue), not \(expectedRole.rawValue)"
            )
        }
        node.isOnline = online
        nodesByID[relayID] = node
    }

    func store(
        encodedObject: Data,
        head: PublisherHead,
        headID: String,
        route: RelayRoute
    ) throws -> String {
        let hostID = try validate(route: route)
        var hostPublications = publicationsByHost[hostID, default: [:]]

        if let current = hostPublications[head.claims.address] {
            if current.headID == headID {
                return hostID
            }
            guard current.head.claims.revision < head.claims.revision else {
                throw NoctwebLabError.invalidFinality(
                    "host \(hostID) rejected a non-increasing revision"
                )
            }
            guard head.claims.previousHeadID == current.headID else {
                throw NoctwebLabError.invalidFinality(
                    "host \(hostID) rejected a discontinuous publisher head"
                )
            }
        }

        hostPublications[head.claims.address] = HostedPublication(
            encodedObject: encodedObject,
            head: head,
            headID: headID,
            finality: nil
        )
        publicationsByHost[hostID] = hostPublications
        return hostID
    }

    func attach(
        finality: FinalityEvidence,
        address: String,
        hostRelayIDs: [String]
    ) {
        for hostID in hostRelayIDs {
            guard
                var record = publicationsByHost[hostID]?[address],
                record.headID == finality.headID
            else {
                continue
            }
            record.finality = finality
            publicationsByHost[hostID]?[address] = record
        }
    }

    func fetch(
        address: String,
        route: RelayRoute
    ) throws -> HostedPublication? {
        let hostID = try validate(route: route)
        return publicationsByHost[hostID]?[address]
    }

    public func replicaRelayIDs(for address: String) -> [String] {
        publicationsByHost
            .filter { $0.value[address] != nil }
            .map(\.key)
            .sorted()
    }

    public func routes(for preference: LabRoute) -> [RelayRoute] {
        let hostIDs = nodesByID.values
            .filter { $0.role == .host }
            .map(\.id)
            .sorted()
        let passthroughIDs = nodesByID.values
            .filter { $0.role == .passthrough }
            .map(\.id)
            .sorted()

        let direct = hostIDs.map(RelayRoute.direct(hostRelayID:))
        let passthrough = passthroughIDs.flatMap { passthroughID in
            hostIDs.map {
                RelayRoute.passthrough(
                    passthroughRelayID: passthroughID,
                    hostRelayID: $0
                )
            }
        }

        switch preference {
        case .direct:
            return direct
        case .passthrough:
            return passthrough
        case .automatic:
            return direct + passthrough
        }
    }

    public func corruptObject(
        address: String,
        onHost relayID: String
    ) throws {
        guard nodesByID[relayID]?.role == .host else {
            throw NoctwebLabError.invalidRoute("\(relayID) is not a host relay")
        }
        guard var record = publicationsByHost[relayID]?[address] else {
            throw NoctwebLabError.publicationNotFound(address)
        }
        if record.encodedObject.isEmpty {
            record.encodedObject = Data([0xff])
        } else {
            record.encodedObject[record.encodedObject.startIndex] ^= 0xff
        }
        publicationsByHost[relayID]?[address] = record
    }

    public func replaceHead(
        address: String,
        onHost relayID: String,
        with head: PublisherHead
    ) throws {
        guard var record = publicationsByHost[relayID]?[address] else {
            throw NoctwebLabError.publicationNotFound(address)
        }
        record.head = head
        record.headID = try NoctwebDigest.headID(for: head)
        publicationsByHost[relayID]?[address] = record
    }

    public func replaceFinality(
        address: String,
        onHost relayID: String,
        with finality: FinalityEvidence?
    ) throws {
        guard var record = publicationsByHost[relayID]?[address] else {
            throw NoctwebLabError.publicationNotFound(address)
        }
        record.finality = finality
        publicationsByHost[relayID]?[address] = record
    }

    func restore(
        _ publication: PublishedCapsule,
        onHosts relayIDs: [String]
    ) throws {
        let relayIDs = Array(Set(relayIDs)).sorted()
        for relayID in relayIDs {
            try requireOnlineRelay(relayID, role: .host)
            if let current = publicationsByHost[relayID]?[
                publication.object.address
            ] {
                try validateRestoreSuccessor(
                    publication,
                    after: current,
                    relayID: relayID
                )
            }
        }

        for relayID in relayIDs {
            publicationsByHost[relayID, default: [:]][
                publication.object.address
            ] = HostedPublication(
                encodedObject: publication.encodedObject,
                head: publication.head,
                headID: publication.headID,
                finality: publication.finality
            )
        }
    }

    private func validateRestoreSuccessor(
        _ publication: PublishedCapsule,
        after current: HostedPublication,
        relayID: String
    ) throws {
        guard current.headID != publication.headID else { return }
        let currentClaims = current.head.claims
        let candidateClaims = publication.head.claims
        guard
            currentClaims.publicationID == candidateClaims.publicationID,
            currentClaims.publisherID == candidateClaims.publisherID,
            currentClaims.relayNamespaceID ==
                candidateClaims.relayNamespaceID
        else {
            throw NoctwebLabError.invalidFinality(
                "host \(relayID) rejected a restored name owned by another publication"
            )
        }
        guard currentClaims.revision < candidateClaims.revision else {
            throw NoctwebLabError.invalidFinality(
                "host \(relayID) rejected a stale restored revision"
            )
        }
        guard
            candidateClaims.previousHeadID == current.headID,
            publication.object.previousObjectID == currentClaims.objectID
        else {
            throw NoctwebLabError.invalidFinality(
                "host \(relayID) rejected a discontinuous restored revision"
            )
        }
    }

    private func validate(route: RelayRoute) throws -> String {
        switch route {
        case let .direct(hostRelayID):
            try requireOnlineRelay(hostRelayID, role: .host)
            return hostRelayID
        case let .passthrough(passthroughRelayID, hostRelayID):
            try requireOnlineRelay(passthroughRelayID, role: .passthrough)
            try requireOnlineRelay(hostRelayID, role: .host)
            return hostRelayID
        }
    }

    private func requireOnlineRelay(
        _ relayID: String,
        role: RelayRole
    ) throws {
        guard let node = nodesByID[relayID], node.role == role else {
            throw NoctwebLabError.invalidRoute(
                "\(relayID) is not a \(role.rawValue) relay"
            )
        }
        guard node.isOnline else {
            throw NoctwebLabError.relayUnavailable(relayID)
        }
    }
}

public struct MockConsensusFinalizer: Sendable {
    public let quorum: Int

    public init(quorum: Int = 2) throws {
        guard quorum > 0 else {
            throw NoctwebLabError.invalidFinality(
                "consensus quorum must be positive"
            )
        }
        self.quorum = quorum
    }

    public func finalize(
        headID: String,
        confirmations: [String],
        round: UInt64
    ) throws -> FinalityEvidence {
        let unique = Array(Set(confirmations)).sorted()
        let finalized = unique.count >= quorum
        return FinalityEvidence(
            headID: headID,
            round: round,
            quorum: quorum,
            confirmations: unique,
            receiptID: try NoctwebDigest.finalityReceiptID(
                headID: headID,
                round: round,
                quorum: quorum,
                confirmations: unique
            ),
            finalized: finalized
        )
    }

    public func verify(_ evidence: FinalityEvidence) -> Bool {
        let canonicalConfirmations = Array(Set(evidence.confirmations)).sorted()
        guard
            evidence.finalized,
            evidence.quorum == quorum,
            evidence.confirmations == canonicalConfirmations,
            canonicalConfirmations.count >= quorum
        else {
            return false
        }
        return evidence.receiptID == (try? NoctwebDigest.finalityReceiptID(
            headID: evidence.headID,
            round: evidence.round,
            quorum: evidence.quorum,
            confirmations: canonicalConfirmations
        ))
    }
}
