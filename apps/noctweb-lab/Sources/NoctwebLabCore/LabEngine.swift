import Foundation

public actor NoctwebLabEngine {
    private let identities: PublicationIdentityManager
    private let network: InMemoryRelayNetwork
    private let finalizer: MockConsensusFinalizer
    private var publicationsByAddress: [String: PublishedCapsule] = [:]
    private var round: UInt64 = 0

    public init(
        identityStore: any PublicationPrivateKeyStore,
        topology: RelayTopology = .labDefault,
        consensusQuorum: Int = 2
    ) throws {
        self.identities = PublicationIdentityManager(store: identityStore)
        self.network = InMemoryRelayNetwork(topology: topology)
        self.finalizer = try MockConsensusFinalizer(quorum: consensusQuorum)
    }

    public func topology() async throws -> RelayTopology {
        try await network.topology()
    }

    public func routes(for preference: LabRoute) async -> [RelayRoute] {
        await network.routes(for: preference)
    }

    public func setRelayOnline(
        _ online: Bool,
        relayID: String
    ) async throws {
        try await network.setOnline(online, relayID: relayID)
    }

    public func setFederationPolicy(
        _ policy: FederationRoutingPolicy
    ) async throws {
        try await network.setFederationPolicy(policy)
    }

    public func applyRelayConfiguration(
        federationPolicy: FederationRoutingPolicy,
        relays: [RelayRuntimeConfiguration]
    ) async throws {
        try await network.applyConfiguration(
            federationPolicy: federationPolicy,
            relays: relays
        )
    }

    public func setRelayAdvertisedModules(
        _ modules: [RelayModule],
        relayID: String
    ) async throws {
        try await network.setAdvertisedModules(
            modules,
            relayID: relayID
        )
    }

    public func setRelayOperatorRouteDirective(
        _ directive: RouteDirective,
        relayID: String
    ) async throws {
        try await network.setOperatorRouteDirective(
            directive,
            relayID: relayID
        )
    }

    public func corruptReplica(
        address: String,
        hostRelayID: String
    ) async throws {
        try await network.corruptObject(
            address: address,
            onHost: hostRelayID
        )
    }

    public func restore(_ publication: PublishedCapsule) async throws {
        try verifyStoredPublication(publication)
        try await validateNamespaceBinding(
            address: publication.object.address,
            relayNamespaceID: publication.object.relayNamespaceID,
            protocolVersion: publication.object.protocolVersion
        )
        if let current = publicationsByAddress[publication.object.address] {
            try validateRestoreSuccessor(publication, after: current)
        }
        try await network.restore(
            publication,
            onHosts: publication.hostRelayIDs
        )
        publicationsByAddress[publication.object.address] = publication
        round = max(round, publication.finality.round)
    }

    public func deletePublisherIdentity(for publicationID: String) async throws {
        try await identities.deleteIdentity(for: publicationID)
    }

    public func preparePublisherIdentity(
        for publicationID: String
    ) async throws -> String {
        try await identities
            .loadOrCreateIdentity(for: publicationID)
            .publisherID
    }

    public func publish(
        draft: CapsuleSiteDraft,
        expectedPublisherID: String? = nil,
        at date: Date = Date()
    ) async throws -> PublishedCapsule {
        try PublicationValidation.validateDraft(draft)
        try await validateNamespaceBinding(
            address: draft.address,
            relayNamespaceID: draft.relayNamespaceID,
            protocolVersion: CapsuleObject.currentProtocolVersion
        )
        let bundle = try PublicationValidation.canonicalBundle(for: draft)

        let previous = publicationsByAddress[draft.address]
        if
            let previous,
            previous.object.publicationID != draft.publicationID
        {
            throw NoctwebLabError.publisherMismatch(
                expected: previous.object.publicationID,
                actual: draft.publicationID
            )
        }

        let identity: PublicationSigningIdentity
        if let previous {
            identity = try await identities.loadIdentity(
                for: draft.publicationID,
                expectedPublisherID: previous.object.publisherID
            )
        } else if let expectedPublisherID {
            identity = try await identities.loadIdentity(
                for: draft.publicationID,
                expectedPublisherID: expectedPublisherID
            )
        } else {
            identity = try await identities.createIdentity(
                for: draft.publicationID
            )
        }

        let revision = (previous?.object.revision ?? 0) + 1
        let publisherRouteDirective = draft.routeDirective ?? .open
        let object = CapsuleObject(
            publicationID: draft.publicationID,
            address: draft.address,
            relayNamespaceID: draft.relayNamespaceID,
            routeDirective: publisherRouteDirective,
            publisherID: identity.publisherID,
            revision: revision,
            previousObjectID: previous?.head.claims.objectID,
            title: draft.title,
            subtitle: draft.subtitle,
            body: draft.body,
            accentHex: draft.accentHex,
            bundle: bundle
        )
        let encodedObject = try CanonicalJSON.encode(object)
        let objectID = NoctwebDigest.objectID(for: encodedObject)
        let milliseconds = max(0, date.timeIntervalSince1970 * 1_000)
        let claims = PublisherHeadClaims(
            publicationID: draft.publicationID,
            address: draft.address,
            relayNamespaceID: draft.relayNamespaceID,
            routeDirective: publisherRouteDirective,
            publisherID: identity.publisherID,
            publisherPublicKey: identity.publicKey,
            objectID: objectID,
            revision: revision,
            previousHeadID: previous?.headID,
            issuedAtMilliseconds: UInt64(milliseconds)
        )
        let head = PublisherHead(
            claims: claims,
            signature: try identity.sign(headClaims: claims)
        )
        let headID = try NoctwebDigest.headID(for: head)

        var hostRelayIDs: [String] = []
        for route in await network.directHostRoutes() {
            do {
                let relayID = try await network.store(
                    encodedObject: encodedObject,
                    head: head,
                    headID: headID,
                    route: route
                )
                hostRelayIDs.append(relayID)
            } catch NoctwebLabError.relayUnavailable {
                continue
            }
        }
        guard !hostRelayIDs.isEmpty else {
            throw NoctwebLabError.noHostReplica(draft.address)
        }

        round += 1
        let finality = try finalizer.finalize(
            headID: headID,
            confirmations: [
                "mock-consensus-a",
                "mock-consensus-b",
                "mock-consensus-c",
            ],
            round: round
        )
        guard finality.finalized else {
            throw NoctwebLabError.finalityNotReached(
                required: finality.quorum,
                confirmed: finality.confirmations.count
            )
        }
        await network.attach(
            finality: finality,
            address: draft.address,
            hostRelayIDs: hostRelayIDs
        )

        let publication = PublishedCapsule(
            object: object,
            encodedObject: encodedObject,
            head: head,
            headID: headID,
            hostRelayIDs: hostRelayIDs.sorted(),
            finality: finality
        )
        try verifyStoredPublication(publication)
        publicationsByAddress[draft.address] = publication
        return publication
    }

    public func resolve(
        address: String,
        preference: LabRoute = .automatic
    ) async throws -> ResolutionResult {
        guard let accepted = publicationsByAddress[address] else {
            throw NoctwebLabError.publicationNotFound(address)
        }
        let candidates = await network.policyRoutes(
            publisher: accepted.object.routeDirective ?? .open,
            visitor: preference
        )
        guard !candidates.isEmpty else {
            throw NoctwebLabError.invalidRoute(
                "effective routing policy has no available route shape"
            )
        }
        var lastFailure: (any Error)?
        for candidate in candidates {
            do {
                return try await resolve(
                    address: address,
                    route: candidate.route,
                    routingDecision: candidate.decision,
                    publisherRouteDirective:
                        accepted.object.routeDirective ?? .open,
                    visitor: preference
                )
            } catch NoctwebLabError.relayUnavailable {
                continue
            } catch NoctwebLabError.publicationNotFound {
                continue
            } catch {
                lastFailure = error
            }
        }
        if let lastFailure {
            throw lastFailure
        }
        throw NoctwebLabError.noHostReplica(address)
    }

    public func resolve(
        address: String,
        route: RelayRoute
    ) async throws -> ResolutionResult {
        guard let accepted = publicationsByAddress[address] else {
            throw NoctwebLabError.publicationNotFound(address)
        }
        let visitor: LabRoute = route.directive == .direct
            ? .direct
            : .passthrough
        let decision = try await network.routingDecision(
            for: route,
            publisher: accepted.object.routeDirective ?? .open,
            visitor: visitor
        )
        return try await resolve(
            address: address,
            route: route,
            routingDecision: decision,
            publisherRouteDirective:
                accepted.object.routeDirective ?? .open,
            visitor: visitor
        )
    }

    private func resolve(
        address: String,
        route: RelayRoute,
        routingDecision: RoutingDecision,
        publisherRouteDirective: RouteDirective,
        visitor: LabRoute
    ) async throws -> ResolutionResult {
        guard let accepted = publicationsByAddress[address] else {
            throw NoctwebLabError.publicationNotFound(address)
        }
        if CapsuleObject.usesRelayNamespace(
            protocolVersion: accepted.object.protocolVersion
        ) {
            _ = try NoctwebAddress.parse(address)
        } else {
            try PublicationValidation.validateLegacyAddress(address)
        }
        guard let hosted = try await network.fetch(
            address: address,
            route: route,
            publisher: publisherRouteDirective,
            visitor: visitor,
            expectedDecision: routingDecision
        ) else {
            throw NoctwebLabError.publicationNotFound(address)
        }
        guard hosted.headID == accepted.headID else {
            throw NoctwebLabError.invalidFinality(
                "host returned a non-finalized publisher head"
            )
        }
        guard let finality = hosted.finality else {
            throw NoctwebLabError.invalidFinality(
                "host did not return finality evidence"
            )
        }

        let canonicalObject: CapsuleObject
        let reencoded: Data
        do {
            canonicalObject = try CanonicalJSON.decode(
                CapsuleObject.self,
                from: hosted.encodedObject
            )
            try PublicationValidation.validateObject(canonicalObject)
            reencoded = try CanonicalJSON.encode(canonicalObject)
        } catch {
            throw NoctwebLabError.integrityMismatch(
                "hosted bytes are not a canonical capsule object"
            )
        }
        let computedObjectID = NoctwebDigest.objectID(
            for: hosted.encodedObject
        )
        let canonical = reencoded == hosted.encodedObject
        guard
            canonical,
            computedObjectID == hosted.head.claims.objectID
        else {
            throw NoctwebLabError.integrityMismatch(
                "object bytes do not match the signed object identifier"
            )
        }
        guard
            canonicalObject.protocolVersion ==
                hosted.head.claims.protocolVersion,
            canonicalObject.address == address,
            canonicalObject.publicationID == hosted.head.claims.publicationID,
            canonicalObject.relayNamespaceID ==
                hosted.head.claims.relayNamespaceID,
            canonicalObject.routeDirective ==
                hosted.head.claims.routeDirective,
            canonicalObject.publisherID == hosted.head.claims.publisherID,
            canonicalObject.revision == hosted.head.claims.revision
        else {
            throw NoctwebLabError.integrityMismatch(
                "object fields do not match the signed publisher head"
            )
        }

        let derivedPublisherID = NoctwebDigest.publisherID(
            for: hosted.head.claims.publisherPublicKey
        )
        let expectedPublisherID = accepted.object.publisherID
        guard
            derivedPublisherID == hosted.head.claims.publisherID,
            hosted.head.claims.publisherID == expectedPublisherID
        else {
            throw NoctwebLabError.publisherMismatch(
                expected: expectedPublisherID,
                actual: hosted.head.claims.publisherID
            )
        }
        guard PublicationSigningIdentity.verify(
            signature: hosted.head.signature,
            headClaims: hosted.head.claims
        ) else {
            throw NoctwebLabError.invalidPublisherSignature
        }
        guard
            try NoctwebDigest.headID(for: hosted.head) == hosted.headID,
            finality.headID == hosted.headID,
            finalizer.verify(finality)
        else {
            throw NoctwebLabError.invalidFinality(
                "finality receipt or head commitment is invalid"
            )
        }

        return ResolutionResult(
            object: canonicalObject,
            head: hosted.head,
            headID: hosted.headID,
            route: route,
            routingDecision: routingDecision,
            evidence: ResolutionEvidence(
                integrity: IntegrityEvidence(
                    declaredObjectID: hosted.head.claims.objectID,
                    computedObjectID: computedObjectID,
                    canonicalEncoding: canonical,
                    verified: true
                ),
                publisher: PublisherEvidence(
                    expectedPublisherID: expectedPublisherID,
                    claimedPublisherID: hosted.head.claims.publisherID,
                    derivedPublisherID: derivedPublisherID,
                    signatureValid: true,
                    identityBound: true
                ),
                finality: finality
            )
        )
    }

    private func verifyStoredPublication(
        _ publication: PublishedCapsule
    ) throws {
        let decoded: CapsuleObject
        let canonicalBytes: Data
        do {
            decoded = try CanonicalJSON.decode(
                CapsuleObject.self,
                from: publication.encodedObject
            )
            try PublicationValidation.validateObject(decoded)
            canonicalBytes = try CanonicalJSON.encode(decoded)
        } catch {
            throw NoctwebLabError.integrityMismatch(
                "stored bytes are not a valid canonical capsule object"
            )
        }
        guard
            decoded == publication.object,
            canonicalBytes == publication.encodedObject,
            NoctwebDigest.objectID(for: publication.encodedObject) ==
                publication.head.claims.objectID,
            publication.object.protocolVersion ==
                publication.head.claims.protocolVersion,
            publication.object.publicationID ==
                publication.head.claims.publicationID,
            publication.object.address ==
                publication.head.claims.address,
            publication.object.relayNamespaceID ==
                publication.head.claims.relayNamespaceID,
            publication.object.routeDirective ==
                publication.head.claims.routeDirective,
            publication.object.publisherID ==
                publication.head.claims.publisherID,
            publication.object.revision ==
                publication.head.claims.revision
        else {
            throw NoctwebLabError.integrityMismatch(
                "stored object does not match its canonical bytes or publisher head"
            )
        }
        guard
            publication.head.claims.publisherID ==
                NoctwebDigest.publisherID(
                    for: publication.head.claims.publisherPublicKey
                ),
            PublicationSigningIdentity.verify(
                signature: publication.head.signature,
                headClaims: publication.head.claims
            ),
            try NoctwebDigest.headID(for: publication.head) ==
                publication.headID,
            publication.finality.headID == publication.headID,
            finalizer.verify(publication.finality)
        else {
            throw NoctwebLabError.invalidFinality(
                "restored publication evidence is invalid"
            )
        }
    }

    private func validateNamespaceBinding(
        address: String,
        relayNamespaceID: String?,
        protocolVersion: String
    ) async throws {
        guard CapsuleObject.usesRelayNamespace(
            protocolVersion: protocolVersion
        ) else {
            return
        }
        let parsed = try NoctwebAddress.parse(address)
        guard let relayNamespaceID else {
            throw NoctwebLabError.canonicalEncoding(
                "a relay namespace identity is required"
            )
        }
        let topology = try await network.topology()
        let matches = try topology.nodes
            .filter { $0.supports(.host) }
            .compactMap { try $0.relayNamespace() }
            .contains {
                $0.id == relayNamespaceID &&
                    $0.suffix == parsed.relaySuffix
            }
        guard matches else {
            throw NoctwebLabError.invalidRelayTopology(
                "address suffix .\(parsed.relaySuffix) is not bound to relay namespace \(relayNamespaceID)"
            )
        }
    }

    private func validateRestoreSuccessor(
        _ publication: PublishedCapsule,
        after current: PublishedCapsule
    ) throws {
        guard current.headID != publication.headID else { return }
        guard
            current.object.publicationID == publication.object.publicationID,
            current.object.publisherID == publication.object.publisherID,
            current.object.relayNamespaceID ==
                publication.object.relayNamespaceID
        else {
            throw NoctwebLabError.publisherMismatch(
                expected: current.object.publisherID,
                actual: publication.object.publisherID
            )
        }
        guard current.object.revision < publication.object.revision else {
            throw NoctwebLabError.invalidFinality(
                "restored publication revision is stale or conflicting"
            )
        }
        guard
            publication.head.claims.previousHeadID == current.headID,
            publication.object.previousObjectID ==
                current.head.claims.objectID
        else {
            throw NoctwebLabError.invalidFinality(
                "restored publication does not continue the accepted head"
            )
        }
    }
}
