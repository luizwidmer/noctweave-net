import XCTest
@testable import NoctwebLabCore

final class LiveHostRelayTests: XCTestCase {
    func testLiveHostRelayDiscoveryWhenConfigured() async throws {
        guard let endpoint = ProcessInfo.processInfo.environment[
            "NOCTWEB_LIVE_HOST_RELAY"
        ] else {
            throw XCTSkip("Set NOCTWEB_LIVE_HOST_RELAY.")
        }

        let client = try NoctwebHostRelayClient(endpoint: endpoint)
        let configuration = try await client.discover(force: true)

        XCTAssertTrue(configuration.isValid)
        XCTAssertNotNil(configuration.relayNamespace)
        XCTAssertEqual(configuration.hostModule, "nw.net-host")
        XCTAssertEqual(configuration.hostModuleVersion, 1)
    }

    func testHostedEnvelopeHasNoFinalityClaimAndRejectsTampering() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let namespace = try RelayNamespace(
            publicKey: Data(repeating: 0x42, count: 32)
        )
        let draft = CapsuleSiteDraft(
            publicationID: UUID().uuidString.lowercased(),
            address: try NoctwebAddress(
                siteLabel: "signed-test",
                relaySuffix: namespace.suffix
            ).canonicalString,
            relayNamespaceID: namespace.id,
            routeDirective: .direct,
            title: "Signed test",
            subtitle: "Hosted only",
            body: "A publisher-signed hosted capsule.",
            accentHex: "#6757D9"
        )
        let publication = try await engine.makeHostedPublication(
            draft: draft,
            relayNamespace: namespace
        )
        XCTAssertEqual(
            try publication.verified(),
            publication
        )
        let encoded = try CanonicalJSON.encode(publication)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(text.contains(#""finality":"#))
        XCTAssertFalse(text.contains(#""consensus":"#))

        var tampered = publication.encodedObject
        tampered[tampered.startIndex] ^= 0x01
        let invalid = HostedCapsuleEnvelope(
            object: publication.object,
            encodedObject: tampered,
            head: publication.head,
            headID: publication.headID
        )
        XCTAssertThrowsError(try invalid.verified())
    }

    func testLiveHostRelayRoundTripWhenConfigured() async throws {
        guard
            let endpoint = ProcessInfo.processInfo.environment[
                "NOCTWEB_LIVE_HOST_RELAY"
            ],
            let authorization = ProcessInfo.processInfo.environment[
                "NOCTWEB_LIVE_HOST_PASSWORD"
            ]
        else {
            throw XCTSkip(
                "Set NOCTWEB_LIVE_HOST_RELAY and NOCTWEB_LIVE_HOST_PASSWORD."
            )
        }
        let client = try NoctwebHostRelayClient(endpoint: endpoint)
        let configuration = try await client.discover(force: true)
        let namespace = try XCTUnwrap(configuration.relayNamespace)
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let draft = CapsuleSiteDraft(
            publicationID: UUID().uuidString.lowercased(),
            address: try NoctwebAddress(
                siteLabel: "live-\(UUID().uuidString.lowercased().prefix(8))",
                relaySuffix: namespace.suffix
            ).canonicalString,
            relayNamespaceID: namespace.id,
            routeDirective: .direct,
            title: "Live relay test",
            subtitle: "Real nw.net-host round trip",
            body: "This object is removed before the test exits.",
            accentHex: "#6757D9"
        )
        let publication = try await engine.makeHostedPublication(
            draft: draft,
            relayNamespace: namespace
        )
        let payload = try CanonicalJSON.encode(publication)
        let put = try await client.put(
            payload: payload,
            ttlSeconds: configuration.minimumRetentionSeconds,
            authorization: authorization
        )
        defer {
            Task {
                _ = try? await client.release(
                    objectID: put.receipt.objectID,
                    releaseCapability: put.releaseCapability,
                    authorization: authorization
                )
            }
        }

        let presentAfterPut = try await client.contains(
            objectID: put.receipt.objectID
        )
        XCTAssertTrue(presentAfterPut)
        let fetched = try await client.fetch(
            objectID: put.receipt.objectID
        )
        XCTAssertEqual(fetched.payload, payload)
        XCTAssertEqual(
            try CanonicalJSON.decode(
                HostedCapsuleEnvelope.self,
                from: fetched.payload
            ).verified(),
            publication
        )
        let released = try await client.release(
            objectID: put.receipt.objectID,
            releaseCapability: put.releaseCapability,
            authorization: authorization
        )
        XCTAssertTrue(released)
        let presentAfterRelease = try await client.contains(
            objectID: put.receipt.objectID
        )
        XCTAssertFalse(presentAfterRelease)
    }
}
