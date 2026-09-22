import CryptoKit
import Foundation
@preconcurrency import NoctweaveCore
import NoctwebBrowserCore
import NoctwebLabCore
import XCTest
@testable import NoctwebBrowser

final class FederatedResolverSecurityTests: XCTestCase {
    func testPassthroughRequirementRejectsBeforeAnyRelayRequest() async throws {
        for federationDirective in [NoctwebBrowserCore.RouteDirective.open, .passthrough] {
            let environment = try DeterministicNoctwebResolver.developmentEnvironment()
            let source = environment.profile
            let profile = try NoctwebNetworkProfile(
                id: source.id, displayName: source.displayName,
                routingTrustDomainID: source.routingTrustDomainID,
                consensusProfileID: source.consensusProfileID,
                verificationKey: source.verificationKey,
                bootstrapEndpoints: [URL(string: "http://127.0.0.1:9340")!],
                supportedEpochs: [1], federationMode: .manual,
                federationDirective: federationDirective,
                defaultVisitorDirective: .open
            )
            let counter = RequestCounter()
            let resolver = FederatedNoctwebResolver { _, _ in
                await counter.record()
                throw URLError(.cannotConnectToHost)
            }
            do {
                _ = try await resolver.resolve(
                    environment.welcomeURL,
                    profile: profile,
                    visitorDirective: federationDirective == .open ? .passthrough : .direct
                )
                XCTFail("Unsupported passthrough must fail closed")
            } catch {}
            let count = await counter.count
            XCTAssertEqual(count, 0, "Reject before disclosing navigation to a direct transport")
        }
    }

    func testVisitorPassthroughDoesNotFetchSignedHostedContent() async throws {
        let fixture = try await HostedFixture.make()
        let relay = FixtureRelay(fixture: fixture)
        let resolver = FederatedNoctwebResolver { _, request in
            try await relay.respond(to: request)
        }
        do {
            _ = try await resolver.resolve(
                fixture.navigationURL, profile: fixture.profile, visitorDirective: .passthrough
            )
            XCTFail("Unsupported passthrough must fail closed")
        } catch {}
        let count = await relay.count
        XCTAssertEqual(count, 0)
    }

    func testFederationDirectPolicyStillOverridesVisitorPreference() async throws {
        let fixture = try await HostedFixture.make(federationDirective: .direct)
        let relay = FixtureRelay(fixture: fixture)
        let resolver = FederatedNoctwebResolver { _, request in
            try await relay.respond(to: request)
        }
        let site = try await resolver.resolve(
            fixture.navigationURL, profile: fixture.profile, visitorDirective: .passthrough
        )
        XCTAssertEqual(site.evidence.route.directive, .direct)
        XCTAssertEqual(site.evidence.route.authority, .federation)
    }

    @MainActor
    func testForgettingRelayRevokesAllOpenTabs() async throws {
        let fixture = try await HostedFixture.make()
        let relay = FixtureRelay(fixture: fixture)
        let resolver = FederatedNoctwebResolver { _, request in
            try await relay.respond(to: request)
        }
        let suite = "NoctwebBrowserRelayResetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profileObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.profile))
        defaults.set(try JSONSerialization.data(withJSONObject: [
            "bookmarks": [], "history": [], "lastProfileID": fixture.profile.id,
            "lastAddress": fixture.navigationURL.canonicalString,
            "relayEndpoint": "http://127.0.0.1:9340", "relayProfile": profileObject,
        ]), forKey: "net.noctweave.noctweb-browser.state.v1")
        let model = BrowserAppModel(
            persistenceStore: BrowserPersistenceStore(defaults: defaults), resolver: resolver
        )
        let firstTabID = model.selectedTab.id
        model.navigate(to: fixture.navigationURL.canonicalString)
        for _ in 0..<200 where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(model.selectedSite)
        model.addTab()
        model.navigate(to: fixture.navigationURL.canonicalString)
        for _ in 0..<200 where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.sitesByTab.count, 2)
        model.forgetRelay()
        XCTAssertTrue(model.sitesByTab.isEmpty)
        XCTAssertFalse(model.relayIsConfigured)
        model.selectTab(firstTabID)
        XCTAssertNil(model.selectedSite)
        XCTAssertEqual(model.selectedTab.verificationState, .idle)
        XCTAssertEqual(model.addressText, "")
    }

    func testNamespaceConsensusCannotFinalizeHostedPublication() async throws {
        let fixture = try await HostedFixture.make()
        let relay = FixtureRelay(fixture: fixture)
        let resolver = FederatedNoctwebResolver { _, request in
            try await relay.respond(to: request)
        }
        let site = try await resolver.resolve(
            fixture.navigationURL, profile: fixture.profile, visitorDirective: .open
        )
        XCTAssertEqual(site.title, "Hosted security fixture")
        XCTAssertEqual(site.evidence.publisherID, fixture.publication.object.publisherID)
        XCTAssertEqual(site.state, .hostedPreview,
                       "A signed namespace snapshot settles suffix ownership, not publication head finality")
        let count = await relay.count
        XCTAssertEqual(count, 3)
    }
}

private actor RequestCounter {
    private(set) var count = 0
    func record() { count += 1 }
}

private actor FixtureRelay {
    let fixture: HostedFixture
    private(set) var count = 0
    init(fixture: HostedFixture) { self.fixture = fixture }

    func respond(to request: RelayRequest) throws -> RelayResponse {
        count += 1
        switch request.body {
        case .getNoctwebNamespaceSnapshot:
            return .success(.noctwebNamespaceSnapshot(fixture.snapshot), respondingTo: request)
        case .resolveNetHostName:
            return .success(.netHostNameResolution(fixture.resolution), respondingTo: request)
        case .getNetHostObject:
            return .success(.netHostObject(fixture.hosted), respondingTo: request)
        default:
            throw URLError(.unsupportedURL)
        }
    }
}

private struct HostedFixture: @unchecked Sendable {
    let navigationURL: NoctwebNavigationURL
    let profile: NoctwebNetworkProfile
    let publication: HostedCapsuleEnvelope
    let snapshot: NoctwebNamespaceSnapshotV1
    let resolution: NoctweaveNetHostNameResolutionV1
    let hosted: NoctweaveNetHostFetchResponse

    static func make(
        federationDirective: NoctwebBrowserCore.RouteDirective = .open
    ) async throws -> Self {
        let now = Date()
        let endpoint = RelayEndpoint(host: "127.0.0.1", port: 9340, transport: .http)
        let federation = FederationDescriptor(mode: .manual, name: "security-test")
        let signer = try RelayIdentityKeyMaterialV1.generate()
        let hostKey = Curve25519.Signing.PrivateKey()
        let namespace = try RelayNamespace(
            publicKey: hostKey.publicKey.rawRepresentation,
            operatorSuffix: "security-test"
        )
        let suffix = try XCTUnwrap(NoctwebRelaySuffixV1(rawValue: ".security-test"))
        let identity = try signer.makeSignedClaim(
            sequence: 1, relayKind: .standard, federation: federation,
            advertisedEndpoints: [endpoint], noctwebSuffix: suffix,
            hostSigningPublicKey: hostKey.publicKey.rawRepresentation,
            capabilities: RelayCapabilityManifestV2.advertised(
                attachmentsEnabled: true, wakeEnabled: false,
                hiddenRetrievalEnabled: false, onionEnabled: false,
                mixnetEnabled: false, netHostEnabled: true
            ), issuedAt: now, lifetime: 3_600
        )
        var ledger = NoctwebNamespaceLedgerV1()
        try ledger.claim(identity, now: now)
        let snapshot = try NoctwebNamespaceSnapshotV1.signed(
            payload: NoctwebNamespaceSnapshotPayloadV1(
                federationMode: .manual, federationName: federation.name,
                epoch: 1, previousSnapshotDigest: nil,
                records: ledger.snapshotRecords(at: now), issuedAt: now
            ), by: [signer]
        )
        let navigationURL = try NoctwebNavigationURL(parsing: "noct://example.security-test/")
        let engine = try NoctwebLabEngine(identityStore: InMemoryPublicationPrivateKeyStore())
        let publication = try await engine.makeHostedPublication(
            draft: CapsuleSiteDraft(
                publicationID: UUID().uuidString.lowercased(),
                address: navigationURL.baseAddress, relayNamespaceID: namespace.id,
                routeDirective: .open, title: "Hosted security fixture", subtitle: "Test",
                body: "Signed content without a content finality certificate", accentHex: "#4F8F77",
                bundle: WebsiteBundle(entryPath: "index.html", files: [
                    WebsiteFile(path: "index.html", mediaType: "text/html", bytes: Data("<p>Fixture</p>".utf8)),
                ])
            ), relayNamespace: namespace, at: now
        )
        let payload = try CanonicalJSON.encode(publication)
        let objectID = NoctweaveNetHostPutRequest.objectID(for: payload)
        let unsignedReceipt = NoctweaveNetHostingReceipt(
            objectID: objectID, byteCount: UInt64(payload.count), storedAt: now,
            expiresAt: now.addingTimeInterval(600),
            signingPublicKey: hostKey.publicKey.rawRepresentation, signature: Data()
        )
        let receipt = NoctweaveNetHostingReceipt(
            objectID: objectID, byteCount: UInt64(payload.count), storedAt: now,
            expiresAt: now.addingTimeInterval(600),
            signingPublicKey: hostKey.publicKey.rawRepresentation,
            signature: try hostKey.signature(for: unsignedReceipt.signingPayload)
        )
        let resolution = try NoctweaveNetHostNameResolutionV1.signed(
            binding: NoctweaveNetHostNameBindingRequestV1(
                relaySuffix: suffix, siteLabel: navigationURL.siteLabel, objectID: objectID,
                publisherID: publication.object.publisherID, headID: publication.headID,
                revision: publication.object.revision, previousObjectID: nil,
                idempotencyKey: Data(repeating: 0x42, count: 32)
            ), updatedAt: now, signer: signer, at: now
        )
        let profile = try NoctwebNetworkProfile(
            id: "selected-relay", displayName: "Security test",
            routingTrustDomainID: "sha256:" + String(repeating: "a", count: 64),
            consensusProfileID: "noctweb.namespace.v1", verificationKey: Data(repeating: 1, count: 32),
            bootstrapEndpoints: [URL(string: "http://127.0.0.1:9340")!],
            supportedEpochs: [1], federationMode: .manual, namespaceFederationName: federation.name,
            federationDirective: federationDirective, defaultVisitorDirective: .open,
            namespaceSigners: [NoctwebNamespaceSigner(relayID: signer.relayID.rawValue,
                                                    signingPublicKey: signer.signingPublicKey)],
            namespaceThreshold: 1
        )
        return Self(navigationURL: navigationURL, profile: profile, publication: publication,
                    snapshot: snapshot, resolution: resolution,
                    hosted: NoctweaveNetHostFetchResponse(receipt: receipt, payload: payload))
    }
}
