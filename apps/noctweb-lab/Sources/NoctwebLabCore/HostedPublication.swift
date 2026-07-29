import Foundation

/// A publisher-signed Noctweb capsule that can be stored by `nw.net-host@1`.
/// It intentionally carries no consensus-finality claim.
public struct HostedCapsuleEnvelope: Codable, Equatable, Sendable {
    public static let profile = "noctweb-hosted-capsule-v1"

    public let profile: String
    public let object: CapsuleObject
    public let encodedObject: Data
    public let head: PublisherHead
    public let headID: String

    public init(
        object: CapsuleObject,
        encodedObject: Data,
        head: PublisherHead,
        headID: String
    ) {
        self.profile = Self.profile
        self.object = object
        self.encodedObject = encodedObject
        self.head = head
        self.headID = headID
    }

    public func verified() throws -> HostedCapsuleEnvelope {
        guard profile == Self.profile else {
            throw NoctwebLabError.integrityMismatch(
                "unsupported hosted capsule profile"
            )
        }
        let decoded = try CanonicalJSON.decode(
            CapsuleObject.self,
            from: encodedObject
        )
        try PublicationValidation.validateObject(decoded)
        let canonical = try CanonicalJSON.encode(decoded)
        guard decoded == object,
              canonical == encodedObject,
              NoctwebDigest.objectID(for: encodedObject) == head.claims.objectID,
              object.protocolVersion == head.claims.protocolVersion,
              object.publicationID == head.claims.publicationID,
              object.address == head.claims.address,
              object.relayNamespaceID == head.claims.relayNamespaceID,
              object.routeDirective == head.claims.routeDirective,
              object.publisherID == head.claims.publisherID,
              object.revision == head.claims.revision,
              head.claims.publisherID == NoctwebDigest.publisherID(
                  for: head.claims.publisherPublicKey
              ),
              PublicationSigningIdentity.verify(
                  signature: head.signature,
                  headClaims: head.claims
              ),
              try NoctwebDigest.headID(for: head) == headID else {
            throw NoctwebLabError.integrityMismatch(
                "hosted capsule does not match its canonical bytes or publisher signature"
            )
        }
        return self
    }
}

public extension NoctwebLabEngine {
    func makeHostedPublication(
        draft: CapsuleSiteDraft,
        relayNamespace: RelayNamespace,
        previous: HostedCapsuleEnvelope? = nil,
        expectedPublisherID: String? = nil,
        at date: Date = Date()
    ) async throws -> HostedCapsuleEnvelope {
        try PublicationValidation.validateDraft(draft)
        let address = try NoctwebAddress.parse(draft.address)
        guard draft.relayNamespaceID == relayNamespace.id,
              address.relaySuffix == relayNamespace.suffix else {
            throw NoctwebLabError.invalidRelayTopology(
                "the publication address is not bound to the connected host relay namespace"
            )
        }
        if let previous {
            _ = try previous.verified()
            guard previous.object.publicationID == draft.publicationID,
                  previous.object.address == draft.address,
                  previous.object.relayNamespaceID == draft.relayNamespaceID else {
                throw NoctwebLabError.publisherMismatch(
                    expected: previous.object.publicationID,
                    actual: draft.publicationID
                )
            }
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
            identity = try await identities.loadOrCreateIdentity(
                for: draft.publicationID
            )
        }

        let revision = (previous?.object.revision ?? 0) + 1
        let routeDirective = draft.routeDirective ?? .open
        let object = CapsuleObject(
            publicationID: draft.publicationID,
            address: draft.address,
            relayNamespaceID: draft.relayNamespaceID,
            routeDirective: routeDirective,
            publisherID: identity.publisherID,
            revision: revision,
            previousObjectID: previous?.head.claims.objectID,
            title: draft.title,
            subtitle: draft.subtitle,
            body: draft.body,
            accentHex: draft.accentHex,
            bundle: try PublicationValidation.canonicalBundle(for: draft)
        )
        let encodedObject = try CanonicalJSON.encode(object)
        let claims = PublisherHeadClaims(
            publicationID: draft.publicationID,
            address: draft.address,
            relayNamespaceID: draft.relayNamespaceID,
            routeDirective: routeDirective,
            publisherID: identity.publisherID,
            publisherPublicKey: identity.publicKey,
            objectID: NoctwebDigest.objectID(for: encodedObject),
            revision: revision,
            previousHeadID: previous?.headID,
            issuedAtMilliseconds: UInt64(
                max(0, date.timeIntervalSince1970 * 1_000)
            )
        )
        let head = PublisherHead(
            claims: claims,
            signature: try identity.sign(headClaims: claims)
        )
        return try HostedCapsuleEnvelope(
            object: object,
            encodedObject: encodedObject,
            head: head,
            headID: NoctwebDigest.headID(for: head)
        ).verified()
    }
}
