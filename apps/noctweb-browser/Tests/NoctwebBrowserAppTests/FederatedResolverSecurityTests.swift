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
            let resolver = FederatedNoctwebResolver(sendRequest: { _, _ in
                await counter.record()
                throw URLError(.cannotConnectToHost)
            }, checkNamespace: { _ in }, checkPublicationHead: { _ in })
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
        let resolver = FederatedNoctwebResolver(sendRequest: { _, request in
            try await relay.respond(to: request)
        }, checkNamespace: { _ in }, checkPublicationHead: { _ in })
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
        let resolver = FederatedNoctwebResolver(sendRequest: { _, request in
            try await relay.respond(to: request)
        }, checkNamespace: { _ in }, checkPublicationHead: { _ in })
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
        let suite = "NoctwebBrowserRelayResetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keyService = "net.noctweave.noctweb-browser-tests.\(suite)"
        defer { try? NoctwebLocalKeyProvider().destroy(service: keyService) }
        let profileObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.profile))
        let clear = try JSONSerialization.data(withJSONObject: [
            "bookmarks": [], "history": [], "lastProfileID": fixture.profile.id,
            "lastAddress": fixture.navigationURL.canonicalString,
            "relayEndpoint": "http://127.0.0.1:9340", "relayProfile": profileObject,
        ])
        let sealed = try NoctwebEncryptedLocalData.seal(
            clear,
            using: NoctwebEncryptedLocalData.key(
                service: keyService,
                provider: NoctwebLocalKeyProvider()
            ),
            context: "browser-state-v1"
        )
        defaults.set(sealed, forKey: "net.noctweave.noctweb-browser.state.v1")
        let persistenceStore = BrowserPersistenceStore(
            defaults: defaults, keyService: keyService
        )
        let resolver = FederatedNoctwebResolver(sendRequest: { _, request in
            try await relay.respond(to: request)
        }, checkNamespace: { observation in
            try await persistenceStore.checkAndAdvanceNamespace(observation)
        }, checkPublicationHead: { checkpoint in
            try await persistenceStore.checkAndAdvancePublicationHead(checkpoint)
        })
        let model = BrowserAppModel(
            persistenceStore: persistenceStore, resolver: resolver
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
        let resolver = FederatedNoctwebResolver(sendRequest: { _, request in
            try await relay.respond(to: request)
        }, checkNamespace: { _ in }, checkPublicationHead: { _ in })
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

    @MainActor
    func testSameGlobalEpochReleaseAndSignedAbsenceCannotRestoreSuffix() async throws {
        let fixture = try await HostedFixture.make()
        XCTAssertEqual(fixture.sameEpochActiveSnapshot.payload.epoch, 10)
        XCTAssertEqual(fixture.sameEpochTombstoneSnapshot.payload.epoch, 10)
        XCTAssertEqual(fixture.sameEpochAbsentSnapshot.payload.epoch, 10)
        let relay = FixtureRelay(fixture: fixture)
        let suite = "NoctwebBrowserSuffixCutoffTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keyService = "net.noctweave.noctweb-browser-tests.\(suite)"
        defer { try? NoctwebLocalKeyProvider().destroy(service: keyService) }
        let store = BrowserPersistenceStore(defaults: defaults, keyService: keyService)
        let resolver = FederatedNoctwebResolver(sendRequest: { _, request in
            try await relay.respond(to: request)
        }, checkNamespace: { observation in
            try await store.checkAndAdvanceNamespace(observation)
        }, checkPublicationHead: { checkpoint in
            try await store.checkAndAdvancePublicationHead(checkpoint)
        })

        await relay.serve(snapshot: fixture.sameEpochActiveSnapshot)
        let active = try await resolver.resolve(
            fixture.navigationURL, profile: fixture.profile, visitorDirective: .open
        )
        XCTAssertEqual(active.evidence.namespaceRecordSequence, 1)
        await relay.serve(snapshot: fixture.sameEpochTombstoneSnapshot)
        do {
            _ = try await resolver.resolve(
                fixture.navigationURL, profile: fixture.profile, visitorDirective: .open
            )
            XCTFail("A signed release must remove the suffix")
        } catch {}
        XCTAssertThrowsError(try store.checkAndAdvanceNamespace(
            fixture.observation(for: fixture.sameEpochActiveSnapshot)
        ), "The old active record must not return at the same global epoch")

        try store.purge()
        await relay.serve(snapshot: fixture.sameEpochActiveSnapshot)
        _ = try await resolver.resolve(
            fixture.navigationURL, profile: fixture.profile, visitorDirective: .open
        )
        await relay.serve(snapshot: fixture.sameEpochAbsentSnapshot)
        do {
            _ = try await resolver.resolve(
                fixture.navigationURL, profile: fixture.profile, visitorDirective: .open
            )
            XCTFail("A signed absent record must remove the suffix")
        } catch {}
        XCTAssertThrowsError(try store.checkAndAdvanceNamespace(
            fixture.observation(for: fixture.sameEpochActiveSnapshot)
        ), "An old active record must not return after signed absence in the same bucket")
        let restarted = BrowserPersistenceStore(defaults: defaults, keyService: keyService)
        XCTAssertThrowsError(try restarted.checkAndAdvanceNamespace(
            fixture.observation(for: fixture.sameEpochActiveSnapshot)
        ), "The signed absence cutoff must survive restart")
    }

    @MainActor
    func testBrowserRejectsPreviouslySeenNamespaceAndPublicationRollback() async throws {
        let fixture = try await HostedFixture.make()
        let relay = FixtureRelay(fixture: fixture)
        await relay.serve(snapshot: fixture.newerSnapshot)
        let suite = "NoctwebBrowserEpochRollbackTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keyService = "net.noctweave.noctweb-browser-tests.\(suite)"
        defer { try? NoctwebLocalKeyProvider().destroy(service: keyService) }
        let profileObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.profile))
        let clear = try JSONSerialization.data(withJSONObject: [
            "bookmarks": [], "history": [], "lastProfileID": fixture.profile.id,
            "lastAddress": fixture.navigationURL.canonicalString,
            "relayEndpoint": "http://127.0.0.1:9340", "relayProfile": profileObject,
        ])
        let sealed = try NoctwebEncryptedLocalData.seal(
            clear,
            using: NoctwebEncryptedLocalData.key(
                service: keyService,
                provider: NoctwebLocalKeyProvider()
            ),
            context: "browser-state-v1"
        )
        defaults.set(sealed, forKey: "net.noctweave.noctweb-browser.state.v1")
        let persistenceStore = BrowserPersistenceStore(
            defaults: defaults, keyService: keyService
        )
        let resolver = FederatedNoctwebResolver(sendRequest: { _, request in
            try await relay.respond(to: request)
        }, checkNamespace: { observation in
            try await persistenceStore.checkAndAdvanceNamespace(observation)
        }, checkPublicationHead: { checkpoint in
            try await persistenceStore.checkAndAdvancePublicationHead(checkpoint)
        })
        let model = BrowserAppModel(
            persistenceStore: persistenceStore,
            resolver: resolver
        )
        model.navigate(to: fixture.navigationURL.canonicalString)
        for _ in 0..<200 where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.selectedSite?.evidence.epoch, 2)
        let olderOpenTabID = model.selectedTab.id
        model.addTab()
        model.navigate(to: fixture.navigationURL.canonicalString)
        for _ in 0..<200 where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(model.sitesByTab[olderOpenTabID])

        await relay.serveNewerPublication()
        model.reload()
        for _ in 0..<200 where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.selectedSite?.evidence.headID, fixture.newerPublication.headID)
        XCTAssertNil(model.sitesByTab[olderOpenTabID],
                     "Observing a newer head must tear down an already open older tab")
        XCTAssertEqual(model.session.tabs.first(where: { $0.id == olderOpenTabID })?.verificationState,
                       .stale)
        await relay.serveOriginalPublication()
        model.reload()
        for _ in 0..<200 where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(model.selectedSite,
                     "An older signed publication revision must not replace a newer head")

        await relay.serve(snapshot: fixture.snapshot)
        model.reload()
        for _ in 0..<200 where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(model.selectedSite, "An older valid snapshot must not replace a newer observed epoch")

        await relay.serve(snapshot: fixture.newerSnapshot)
        let restartedStore = BrowserPersistenceStore(
            defaults: defaults, keyService: keyService
        )
        let restartedResolver = FederatedNoctwebResolver(sendRequest: { _, request in
            try await relay.respond(to: request)
        }, checkNamespace: { observation in
            try await restartedStore.checkAndAdvanceNamespace(observation)
        }, checkPublicationHead: { checkpoint in
            try await restartedStore.checkAndAdvancePublicationHead(checkpoint)
        })
        let restarted = BrowserAppModel(
            persistenceStore: restartedStore, resolver: restartedResolver
        )
        restarted.navigate(to: fixture.navigationURL.canonicalString)
        for _ in 0..<200 where restarted.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(restarted.selectedSite, "The publication revision floor must survive a Browser restart")

        await relay.serve(snapshot: fixture.snapshot)
        restarted.reload()
        for _ in 0..<200 where restarted.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(restarted.selectedSite, "The epoch floor must survive a Browser restart")

        await relay.serve(snapshot: fixture.newestSnapshot)
        await relay.serveNewerPublication()
        restarted.reload()
        for _ in 0..<200 where restarted.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(restarted.selectedSite?.evidence.epoch, 3,
                       "A later signed epoch must remain usable")
        let preRevocationTabID = restarted.selectedTab.id
        restarted.addTab()
        restarted.navigate(to: fixture.navigationURL.canonicalString)
        for _ in 0..<200 where restarted.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNotNil(restarted.sitesByTab[preRevocationTabID])

        await relay.serve(snapshot: fixture.revokedSnapshot)
        restarted.reload()
        for _ in 0..<200 where restarted.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(restarted.selectedSite, "The signed revocation has no active owner")
        XCTAssertNil(restarted.sitesByTab[preRevocationTabID],
                     "Failed navigation after signed revocation must tear down older open content")
        XCTAssertEqual(restarted.session.tabs.first(where: { $0.id == preRevocationTabID })?.verificationState,
                       .stale)
        await relay.serve(snapshot: fixture.newestSnapshot)
        restarted.reload()
        for _ in 0..<200 where restarted.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(restarted.selectedSite,
                     "A revoked namespace must not accept its prior active snapshot")

        let suffix = try XCTUnwrap(NoctwebRelaySuffixV1(rawValue: ".security-test"))
        let oldHead = VerifiedPublicationHead(
            profile: fixture.profile, relaySuffix: suffix.rawValue,
            siteLabel: fixture.navigationURL.siteLabel, namespaceEpoch: 3,
            publisherID: fixture.publication.object.publisherID,
            revision: fixture.publication.object.revision,
            headID: fixture.publication.headID,
            objectID: fixture.publication.head.claims.objectID
        )
        restarted.forgetRelay()
        XCTAssertThrowsError(try restartedStore.checkAndAdvanceNamespace(
            fixture.observation(for: fixture.newestSnapshot)
        ), "Forgetting a relay must not erase its namespace cutoff")
        XCTAssertThrowsError(try restartedStore.checkAndAdvancePublicationHead(oldHead),
                             "Forgetting a relay must not erase its publication cutoff")
        try restartedStore.purge()
        XCTAssertNoThrow(try restartedStore.checkAndAdvanceNamespace(
            fixture.observation(for: fixture.snapshot)
        ), "Explicit Browser data removal clears the namespace checkpoint")
        XCTAssertNoThrow(try restartedStore.checkAndAdvancePublicationHead(oldHead),
                         "Explicit Browser data removal clears the publication checkpoint")
    }

    @MainActor
    func testLateOlderTabResultCannotRenderAfterAnotherTabAdvancesHead() async throws {
        let fixture = try await HostedFixture.make()
        let suite = "NoctwebBrowserConcurrentHeadTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let keyService = "net.noctweave.noctweb-browser-tests.\(suite)"
        defer { try? NoctwebLocalKeyProvider().destroy(service: keyService) }
        let profileObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.profile))
        let clear = try JSONSerialization.data(withJSONObject: [
            "bookmarks": [], "history": [], "lastProfileID": fixture.profile.id,
            "lastAddress": fixture.navigationURL.canonicalString,
            "relayEndpoint": "http://127.0.0.1:9340", "relayProfile": profileObject,
        ])
        let sealed = try NoctwebEncryptedLocalData.seal(
            clear,
            using: NoctwebEncryptedLocalData.key(
                service: keyService, provider: NoctwebLocalKeyProvider()
            ),
            context: "browser-state-v1"
        )
        defaults.set(sealed, forKey: "net.noctweave.noctweb-browser.state.v1")
        let store = BrowserPersistenceStore(defaults: defaults, keyService: keyService)
        let resolver = HeldPublicationResolver(fixture: fixture, store: store)
        let model = BrowserAppModel(persistenceStore: store, resolver: resolver)

        let firstTab = model.selectedTab.id
        model.navigate(to: fixture.navigationURL.canonicalString)
        for _ in 0..<200 {
            if await resolver.isHoldingFirst { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let firstIsHeld = await resolver.isHoldingFirst
        XCTAssertTrue(firstIsHeld)
        model.addTab()
        model.navigate(to: fixture.navigationURL.canonicalString)
        for _ in 0..<200 where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(model.selectedSite?.evidence.headID, fixture.newerPublication.headID)

        model.selectTab(firstTab)
        await resolver.releaseFirst()
        for _ in 0..<200 where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(model.selectedSite,
                     "A delayed older result must not render after another tab raises the head floor")
        XCTAssertEqual(model.selectedTab.verificationState, .failed)

        await resolver.enableMismatchedConsensusEvidence()
        model.addTab()
        model.navigate(to: fixture.navigationURL.canonicalString)
        for _ in 0..<200 where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertNil(model.selectedSite,
                     "A changed namespace policy must not skip the final checkpoint gate")
        XCTAssertEqual(model.selectedTab.verificationState, .failed)
    }
}

private actor RequestCounter {
    private(set) var count = 0
    func record() { count += 1 }
}

private actor FixtureRelay {
    let fixture: HostedFixture
    private(set) var count = 0
    private var snapshot: NoctwebNamespaceSnapshotV1
    private var resolution: NoctweaveNetHostNameResolutionV1
    private var hosted: NoctweaveNetHostFetchResponse
    init(fixture: HostedFixture) {
        self.fixture = fixture
        snapshot = fixture.snapshot
        resolution = fixture.resolution
        hosted = fixture.hosted
    }

    func serve(snapshot: NoctwebNamespaceSnapshotV1) {
        self.snapshot = snapshot
    }

    func serveNewerPublication() {
        resolution = fixture.newerResolution
        hosted = fixture.newerHosted
    }

    func serveOriginalPublication() {
        resolution = fixture.resolution
        hosted = fixture.hosted
    }

    func respond(to request: RelayRequest) throws -> RelayResponse {
        count += 1
        switch request.body {
        case .getNoctwebNamespaceSnapshot:
            return .success(.noctwebNamespaceSnapshot(snapshot), respondingTo: request)
        case .resolveNetHostName:
            return .success(.netHostNameResolution(resolution), respondingTo: request)
        case .getNetHostObject:
            return .success(.netHostObject(hosted), respondingTo: request)
        default:
            throw URLError(.unsupportedURL)
        }
    }
}

private actor HeldPublicationResolver: NoctwebResolving {
    let fixture: HostedFixture
    let store: BrowserPersistenceStore
    private var requestCount = 0
    private var firstContinuation: CheckedContinuation<Void, Never>?
    private(set) var isHoldingFirst = false
    private var mismatchConsensusEvidence = false

    init(fixture: HostedFixture, store: BrowserPersistenceStore) {
        self.fixture = fixture
        self.store = store
    }

    func resolve(
        _ navigationURL: NoctwebNavigationURL,
        profile: NoctwebNetworkProfile,
        visitorDirective: NoctwebBrowserCore.RouteDirective
    ) async throws -> VerifiedNoctwebSite {
        requestCount += 1
        let isFirst = requestCount == 1
        let publication = try (isFirst ? fixture.publication : fixture.newerPublication).verified()
        guard let suffix = NoctwebRelaySuffixV1(rawValue: ".\(navigationURL.relaySuffix)"),
              let sourceBundle = publication.object.bundle else {
            throw URLError(.badURL)
        }
        let observation = try fixture.observation(for: fixture.newerSnapshot)
        try await store.checkAndAdvanceNamespace(observation)
        try await store.checkAndAdvancePublicationHead(VerifiedPublicationHead(
            profile: profile, relaySuffix: suffix.rawValue,
            siteLabel: navigationURL.siteLabel, namespaceEpoch: 2,
            publisherID: publication.object.publisherID,
            revision: publication.object.revision,
            headID: publication.headID,
            objectID: publication.head.claims.objectID
        ))
        if isFirst {
            await withCheckedContinuation { continuation in
                firstContinuation = continuation
                isHoldingFirst = true
            }
        }
        let bundle = try NoctwebWebsiteBundle(
            entryPath: sourceBundle.entryPath,
            files: sourceBundle.files.map {
                NoctwebWebsiteFile(path: $0.path, mediaType: $0.mediaType, bytes: $0.bytes)
            }
        )
        let route = NoctwebBrowserCore.RoutingPolicyResolver.resolve(
            federationMode: profile.federationMode, federation: profile.federationDirective,
            hostOperator: .open, publisher: .open, visitor: visitorDirective
        )
        return VerifiedNoctwebSite(
            navigationURL: navigationURL, title: publication.object.title,
            bundle: bundle, state: .hostedPreview,
            evidence: NoctwebVerificationEvidence(
                publisherID: publication.object.publisherID,
                routingTrustDomainID: profile.routingTrustDomainID,
                consensusProfileID: mismatchConsensusEvidence
                    ? "different-consensus-policy" : profile.consensusProfileID,
                epoch: 2,
                namespaceRecordSequence: observation.recordSequence,
                namespaceRecordDigest: observation.recordDigest,
                headID: publication.headID,
                objectID: publication.head.claims.objectID,
                route: route, verifiedAt: Date()
            )
        )
    }

    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
        isHoldingFirst = false
    }

    func enableMismatchedConsensusEvidence() {
        mismatchConsensusEvidence = true
    }
}

private struct HostedFixture: @unchecked Sendable {
    let navigationURL: NoctwebNavigationURL
    let profile: NoctwebNetworkProfile
    let publication: HostedCapsuleEnvelope
    let newerPublication: HostedCapsuleEnvelope
    let snapshot: NoctwebNamespaceSnapshotV1
    let newerSnapshot: NoctwebNamespaceSnapshotV1
    let newestSnapshot: NoctwebNamespaceSnapshotV1
    let revokedSnapshot: NoctwebNamespaceSnapshotV1
    let sameEpochActiveSnapshot: NoctwebNamespaceSnapshotV1
    let sameEpochTombstoneSnapshot: NoctwebNamespaceSnapshotV1
    let sameEpochAbsentSnapshot: NoctwebNamespaceSnapshotV1
    let resolution: NoctweaveNetHostNameResolutionV1
    let hosted: NoctweaveNetHostFetchResponse
    let newerResolution: NoctweaveNetHostNameResolutionV1
    let newerHosted: NoctweaveNetHostFetchResponse

    func observation(
        for snapshot: NoctwebNamespaceSnapshotV1
    ) throws -> VerifiedNamespaceObservation {
        let suffix = try XCTUnwrap(NoctwebRelaySuffixV1(rawValue: ".security-test"))
        let record = snapshot.payload.records.first { $0.suffix == suffix }
        let digest = try record.map {
            Data(SHA256.hash(data: try NoctweaveCanonicalJSON.encode($0)))
        }
        let baseDigest = try record.map { record in
            let base = NoctwebNamespaceRecordV1(
                suffix: record.suffix, ownerRelayID: record.ownerRelayID,
                ownerSigningPublicKey: record.ownerSigningPublicKey,
                ownershipSequence: record.ownershipSequence, status: record.status,
                assignedAt: record.assignedAt, updatedAt: record.updatedAt,
                activeIdentityClaim: nil
            )
            return Data(SHA256.hash(data: try NoctweaveCanonicalJSON.encode(base)))
        }
        return VerifiedNamespaceObservation(
            profile: profile, relaySuffix: suffix.rawValue,
            epoch: UInt64(snapshot.payload.epoch), issuedAt: snapshot.payload.issuedAt,
            recordSequence: record.map { UInt64($0.ownershipSequence) },
            recordStatus: record?.status.rawValue ?? "absent",
            recordBaseDigest: baseDigest, recordDigest: digest,
            hasActiveIdentityClaim: record?.activeIdentityClaim != nil
        )
    }

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
        let newerSnapshot = try NoctwebNamespaceSnapshotV1.signed(
            payload: NoctwebNamespaceSnapshotPayloadV1(
                federationMode: .manual, federationName: federation.name,
                epoch: 2, previousSnapshotDigest: try snapshot.payload.digest(),
                records: ledger.snapshotRecords(at: now), issuedAt: now
            ), by: [signer]
        )
        let newestSnapshot = try NoctwebNamespaceSnapshotV1.signed(
            payload: NoctwebNamespaceSnapshotPayloadV1(
                federationMode: .manual, federationName: federation.name,
                epoch: 3, previousSnapshotDigest: try newerSnapshot.payload.digest(),
                records: ledger.snapshotRecords(at: now), issuedAt: now
            ), by: [signer]
        )
        let revokedSnapshot = try NoctwebNamespaceSnapshotV1.signed(
            payload: NoctwebNamespaceSnapshotPayloadV1(
                federationMode: .manual, federationName: federation.name,
                epoch: 4, previousSnapshotDigest: try newestSnapshot.payload.digest(),
                records: [], issuedAt: now
            ), by: [signer]
        )
        let dominantSigner = try RelayIdentityKeyMaterialV1.generate()
        let dominantSuffix = try XCTUnwrap(NoctwebRelaySuffixV1(rawValue: ".dominant"))
        let dominantIdentity = try dominantSigner.makeSignedClaim(
            sequence: 10, relayKind: .standard, federation: federation,
            advertisedEndpoints: [endpoint], noctwebSuffix: dominantSuffix,
            hostSigningPublicKey: hostKey.publicKey.rawRepresentation,
            capabilities: RelayCapabilityManifestV2.advertised(
                attachmentsEnabled: true, wakeEnabled: false,
                hiddenRetrievalEnabled: false, onionEnabled: false,
                mixnetEnabled: false, netHostEnabled: true
            ), issuedAt: now, lifetime: 3_600
        )
        try ledger.claim(dominantIdentity, now: now)
        let sameEpochActivePayload = try ledger.snapshotPayload(
            federation: federation, at: now
        )
        let sameEpochActiveSnapshot = try NoctwebNamespaceSnapshotV1.signed(
            payload: sameEpochActivePayload, by: [signer]
        )
        let release = try NoctwebNamespaceReleaseV1.signed(
            suffix: suffix, owner: signer, sequence: 2, issuedAt: now
        )
        try ledger.release(release, now: now)
        let sameEpochTombstonePayload = try ledger.snapshotPayload(
            federation: federation, at: now
        )
        let sameEpochTombstoneSnapshot = try NoctwebNamespaceSnapshotV1.signed(
            payload: sameEpochTombstonePayload, by: [signer]
        )
        let sameEpochAbsentSnapshot = try NoctwebNamespaceSnapshotV1.signed(
            payload: NoctwebNamespaceSnapshotPayloadV1(
                federationMode: .manual, federationName: federation.name,
                epoch: 10, previousSnapshotDigest: nil,
                records: sameEpochTombstonePayload.records.filter { $0.suffix != suffix },
                issuedAt: sameEpochTombstonePayload.issuedAt
            ), by: [signer]
        )
        let navigationURL = try NoctwebNavigationURL(parsing: "noct://example.security-test/")
        let engine = try NoctwebLabEngine(identityStore: InMemoryPublicationPrivateKeyStore())
        let draft = CapsuleSiteDraft(
            publicationID: UUID().uuidString.lowercased(),
            address: navigationURL.baseAddress, relayNamespaceID: namespace.id,
            routeDirective: .open, title: "Hosted security fixture", subtitle: "Test",
            body: "Signed content without a content finality certificate", accentHex: "#4F8F77",
            bundle: WebsiteBundle(entryPath: "index.html", files: [
                WebsiteFile(path: "index.html", mediaType: "text/html", bytes: Data("<p>Fixture</p>".utf8)),
            ])
        )
        let publication = try await engine.makeHostedPublication(
            draft: draft, relayNamespace: namespace, at: now
        )
        let newerPublication = try await engine.makeHostedPublication(
            draft: draft, relayNamespace: namespace, previous: publication,
            at: now.addingTimeInterval(1)
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
        let newerPayload = try CanonicalJSON.encode(newerPublication)
        let newerObjectID = NoctweaveNetHostPutRequest.objectID(for: newerPayload)
        let newerUnsignedReceipt = NoctweaveNetHostingReceipt(
            objectID: newerObjectID, byteCount: UInt64(newerPayload.count), storedAt: now,
            expiresAt: now.addingTimeInterval(600),
            signingPublicKey: hostKey.publicKey.rawRepresentation, signature: Data()
        )
        let newerReceipt = NoctweaveNetHostingReceipt(
            objectID: newerObjectID, byteCount: UInt64(newerPayload.count), storedAt: now,
            expiresAt: now.addingTimeInterval(600),
            signingPublicKey: hostKey.publicKey.rawRepresentation,
            signature: try hostKey.signature(for: newerUnsignedReceipt.signingPayload)
        )
        let newerResolution = try NoctweaveNetHostNameResolutionV1.signed(
            binding: NoctweaveNetHostNameBindingRequestV1(
                relaySuffix: suffix, siteLabel: navigationURL.siteLabel,
                objectID: newerObjectID, publisherID: newerPublication.object.publisherID,
                headID: newerPublication.headID, revision: newerPublication.object.revision,
                previousObjectID: objectID, idempotencyKey: Data(repeating: 0x43, count: 32)
            ), updatedAt: now.addingTimeInterval(1), signer: signer, at: now
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
        return Self(navigationURL: navigationURL, profile: profile,
                    publication: publication, newerPublication: newerPublication,
                    snapshot: snapshot, newerSnapshot: newerSnapshot,
                    newestSnapshot: newestSnapshot, revokedSnapshot: revokedSnapshot,
                    sameEpochActiveSnapshot: sameEpochActiveSnapshot,
                    sameEpochTombstoneSnapshot: sameEpochTombstoneSnapshot,
                    sameEpochAbsentSnapshot: sameEpochAbsentSnapshot,
                    resolution: resolution,
                    hosted: NoctweaveNetHostFetchResponse(receipt: receipt, payload: payload),
                    newerResolution: newerResolution,
                    newerHosted: NoctweaveNetHostFetchResponse(receipt: newerReceipt, payload: newerPayload))
    }
}
