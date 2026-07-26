import CryptoKit
import Foundation
import XCTest
@testable import NoctwebLabCore

final class NoctwebLabCoreTests: XCTestCase {
    func testPublisherIdentityCanBePreparedBeforeFirstPublication() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let publicationID = UUID().uuidString.lowercased()

        let first = try await engine.preparePublisherIdentity(
            for: publicationID
        )
        let second = try await engine.preparePublisherIdentity(
            for: publicationID
        )

        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    private func draft(
        publicationID: String = UUID().uuidString.lowercased(),
        bundle: WebsiteBundle? = nil,
        siteLabel: String = "quiet-garden",
        namespaceRelayID: String = "host-lisbon",
        routeDirective: RouteDirective? = .open
    ) -> CapsuleSiteDraft {
        let node = RelayTopology.labDefault.nodes.first {
            $0.id == namespaceRelayID
        }!
        let namespace = try! node.relayNamespace()!
        return CapsuleSiteDraft(
            publicationID: publicationID,
            address: try! NoctwebAddress(
                siteLabel: siteLabel,
                relaySuffix: namespace.suffix
            ).canonicalString,
            relayNamespaceID: namespace.id,
            routeDirective: routeDirective,
            title: "Quiet Garden",
            subtitle: "A native Noctweb publication",
            body: "Verified structured content.",
            accentHex: "#4f8f77",
            bundle: bundle
        )
    }

    private func bundle(files: [WebsiteFile]? = nil) -> WebsiteBundle {
        WebsiteBundle(
            entryPath: "index.html",
            files: files ?? [
                WebsiteFile(
                    path: "index.html",
                    mediaType: "text/html; charset=utf-8",
                    bytes: Data("<main id=\"root\"></main>".utf8)
                ),
                WebsiteFile(
                    path: "assets/app.js",
                    mediaType: "text/javascript; charset=utf-8",
                    bytes: Data("globalThis.noctweb = 'ready';".utf8)
                ),
                WebsiteFile(
                    path: "assets/site.css",
                    mediaType: "text/css; charset=utf-8",
                    bytes: Data("body{margin:0}".utf8)
                ),
                WebsiteFile(
                    path: "assets/pixel.bin",
                    mediaType: "application/octet-stream",
                    bytes: Data([0x00, 0xff, 0x10, 0x80])
                ),
            ]
        )
    }

    func testRelayTopologyHasExactlyTheThreeRolesAndModules() throws {
        let topology = RelayTopology.labDefault
        XCTAssertEqual(Set(topology.nodes.map(\.role)), Set(RelayRole.allCases))
        XCTAssertEqual(RelayRole.standard.module.rawValue, "nw.opaque-route@2")
        XCTAssertEqual(
            RelayRole.passthrough.module.rawValue,
            "nw.net-passthrough@1"
        )
        XCTAssertEqual(RelayRole.host.module.rawValue, "nw.net-host@1")
    }

    func testRelayNamespacesSupportCustomAndStableAutomaticSuffixes() throws {
        let topology = RelayTopology.labDefault
        let lisbon = try XCTUnwrap(
            topology.nodes.first { $0.id == "host-lisbon" }?.relayNamespace()
        )
        let salvadorNode = try XCTUnwrap(
            topology.nodes.first { $0.id == "host-salvador" }
        )
        let salvador = try XCTUnwrap(salvadorNode.relayNamespace())

        XCTAssertEqual(lisbon.suffix, "lisbon")
        XCTAssertTrue(lisbon.usesCustomSuffix)
        XCTAssertTrue(salvador.suffix.hasPrefix("r-"))
        XCTAssertEqual(salvador.suffix.count, 18)
        XCTAssertFalse(salvador.usesCustomSuffix)
        XCTAssertEqual(
            salvador,
            try RelayNamespace(
                publicKey: try XCTUnwrap(salvadorNode.namespacePublicKey)
            )
        )
        XCTAssertNotEqual(lisbon.id, salvador.id)
    }

    func testCanonicalNoctwebAddressRejectsAliasSpellings() throws {
        let valid = try NoctwebAddress.parse(
            "noct://quiet-garden.lisbon/"
        )
        XCTAssertEqual(valid.siteLabel, "quiet-garden")
        XCTAssertEqual(valid.relaySuffix, "lisbon")
        XCTAssertEqual(valid.canonicalString, "noct://quiet-garden.lisbon/")

        let invalid = [
            "noct://quiet-garden/",
            "noct://Quiet-Garden.lisbon/",
            "noct://quiet-garden.lisbon",
            "noct://quiet-garden.lisbon./",
            "noct://quiet-garden.lisbon/path",
            "noct://quiet-garden.lisbon/?query=1",
            "noct://quiet-garden.lisbon/#fragment",
            "noct://user@quiet-garden.lisbon/",
            "noct://quiet-garden.lisbon:9340/",
            "noct://quiet%2dgarden.lisbon/",
            "noct://quiet.garden.lisbon/",
            "noct://xn--garden.lisbon/",
        ]
        for address in invalid {
            XCTAssertThrowsError(
                try NoctwebAddress.parse(address),
                "accepted noncanonical address \(address)"
            )
        }
    }

    func testRelayTopologyRejectsDuplicateVisibleNamespaceSuffix() throws {
        var nodes = RelayTopology.labDefault.nodes
        let salvadorIndex = try XCTUnwrap(
            nodes.firstIndex { $0.id == "host-salvador" }
        )
        nodes[salvadorIndex].namespaceSuffix = ".lisbon"

        XCTAssertThrowsError(try RelayTopology(nodes: nodes)) { error in
            guard case NoctwebLabError.invalidRelayTopology = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRoutingPolicyUsesFirstNonOpenAuthority() {
        let cases: [(
            FederationRoutingPolicy,
            RouteDirective,
            RouteDirective,
            RouteDirective,
            RouteDirective,
            RoutingAuthority
        )] = [
            (
                .init(mode: .curated, directive: .passthrough),
                .direct, .direct, .direct, .passthrough, .federation
            ),
            (
                .init(mode: .manual, directive: .open),
                .passthrough, .direct, .direct, .passthrough, .relayOperator
            ),
            (
                .init(mode: .open, directive: .open),
                .open, .passthrough, .direct, .passthrough, .publisher
            ),
            (
                .soloOpen,
                .open, .open, .passthrough, .passthrough, .visitor
            ),
            (
                .soloOpen,
                .open, .open, .open, .direct, .defaultDirect
            ),
        ]

        for item in cases {
            let decision = RoutingPolicyResolver.resolve(
                federation: item.0,
                relayOperator: item.1,
                publisher: item.2,
                visitor: item.3
            )
            XCTAssertEqual(decision.directive, item.4)
            XCTAssertEqual(decision.authority, item.5)
        }
    }

    func testSoloStandardRelayCanHostAndResolveDirectly() async throws {
        let namespaceKey = RelayNamespace.deterministicLabPublicKey(
            seed: "solo-standard-host"
        )
        let namespace = try RelayNamespace(
            publicKey: namespaceKey,
            operatorSuffix: "solo"
        )
        let topology = try RelayTopology(
            nodes: [
                RelayNode(
                    id: "solo-standard",
                    name: "Solo Standard + Host",
                    role: .standard,
                    endpoint: URL(string: "https://solo.invalid")!,
                    namespacePublicKey: namespaceKey,
                    namespaceSuffix: "solo",
                    advertisedModules: [.standard, .host]
                )
            ],
            federationPolicy: .soloOpen
        )
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore(),
            topology: topology
        )
        let publication = try await engine.publish(
            draft: CapsuleSiteDraft(
                publicationID: UUID().uuidString.lowercased(),
                address: "noct://garden.solo/",
                relayNamespaceID: namespace.id,
                routeDirective: .direct,
                title: "Solo",
                subtitle: "",
                body: "Directly hosted.",
                accentHex: "#4f8f77",
                bundle: bundle()
            )
        )

        XCTAssertEqual(publication.hostRelayIDs, ["solo-standard"])
        let result = try await engine.resolve(
            address: publication.object.address,
            preference: .automatic
        )
        XCTAssertEqual(result.route.hostRelayID, "solo-standard")
        XCTAssertEqual(result.routingDecision.directive, .direct)
        XCTAssertEqual(result.routingDecision.authority, .publisher)
    }

    func testRelayConfigurationAppliesCapabilitiesAndPolicyAtomically()
        async throws
    {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        try await engine.setRelayOperatorRouteDirective(
            .direct,
            relayID: "standard-local"
        )
        let before = try await engine.topology()
        let configuration = before.nodes.map { node in
            RelayRuntimeConfiguration(
                relayID: node.id,
                advertisedModules: node.id == "standard-local"
                    ? [.standard]
                    : node.modules,
                operatorRouteDirective: node.id == "standard-local"
                    ? .open
                    : node.routeDirective,
                isOnline: node.isOnline
            )
        }

        try await engine.applyRelayConfiguration(
            federationPolicy: .soloOpen,
            relays: configuration
        )

        let topology = try await engine.topology()
        let standard = try XCTUnwrap(
            topology.nodes.first {
                $0.id == "standard-local"
            }
        )
        XCTAssertFalse(standard.supports(.host))
        XCTAssertEqual(standard.routeDirective, .open)
    }

    func testSchemaTwoWorkspaceLoadsAsSchemaThree() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("workspace.json")
        let legacy = WorkspaceSnapshot(
            schemaVersion: 2,
            selectedPublicationID: nil,
            publications: [],
            relays: RelayTopology.labDefault.nodes
        )
        try CanonicalJSON.encode(legacy).write(to: fileURL)

        let loaded = try JSONWorkspaceRepository(fileURL: fileURL).load()

        XCTAssertEqual(
            loaded.schemaVersion,
            WorkspaceSnapshot.currentSchemaVersion
        )
        XCTAssertEqual(loaded.relays, legacy.relays)
        XCTAssertEqual(loaded.federationPolicy, .soloOpen)
    }

    func testContentHostDoesNotNeedNamespaceAuthority() throws {
        let topology = try RelayTopology(
            nodes: [
                RelayNode(
                    id: "content-only",
                    name: "Content-only Solo",
                    role: .standard,
                    endpoint: URL(string: "https://content.invalid")!,
                    advertisedModules: [.standard, .host]
                )
            ]
        )
        XCTAssertTrue(try XCTUnwrap(topology.nodes.first).supports(.host))
        XCTAssertNil(try topology.nodes.first?.relayNamespace())
    }

    func testFederationPassthroughMandateCannotDowngradeOrBeBypassed()
        async throws
    {
        let topology = try RelayTopology(
            nodes: RelayTopology.labDefault.nodes,
            federationPolicy: FederationRoutingPolicy(
                mode: .curated,
                directive: .passthrough
            )
        )
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore(),
            topology: topology
        )
        let publication = try await engine.publish(
            draft: draft(routeDirective: .direct)
        )

        do {
            _ = try await engine.resolve(
                address: publication.object.address,
                route: .direct(hostRelayID: "host-lisbon")
            )
            XCTFail("an explicit route must not bypass federation policy")
        } catch let error as NoctwebLabError {
            guard case .invalidRoute = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let mandated = try await engine.resolve(
            address: publication.object.address,
            preference: .direct
        )
        guard case .passthrough = mandated.route else {
            return XCTFail("federation mandate must select one-hop retrieval")
        }
        XCTAssertEqual(mandated.routingDecision.authority, .federation)
        XCTAssertEqual(
            mandated.routingDecision.directive,
            .passthrough
        )

        try await engine.setRelayOnline(
            false,
            relayID: "passthrough-atlantic"
        )
        do {
            _ = try await engine.resolve(
                address: publication.object.address,
                preference: .direct
            )
            XCTFail("a required passthrough must not downgrade to direct")
        } catch let error as NoctwebLabError {
            XCTAssertEqual(
                error,
                .noHostReplica(publication.object.address)
            )
        }
    }

    func testSignedPublisherRouteDirectiveCannotBeTampered() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let publication = try await engine.publish(
            draft: draft(routeDirective: .passthrough)
        )
        let claims = publication.head.claims
        let tampered = PublisherHeadClaims(
            protocolVersion: claims.protocolVersion,
            publicationID: claims.publicationID,
            address: claims.address,
            relayNamespaceID: claims.relayNamespaceID,
            routeDirective: .direct,
            publisherID: claims.publisherID,
            publisherPublicKey: claims.publisherPublicKey,
            objectID: claims.objectID,
            revision: claims.revision,
            previousHeadID: claims.previousHeadID,
            issuedAtMilliseconds: claims.issuedAtMilliseconds
        )
        XCTAssertFalse(
            PublicationSigningIdentity.verify(
                signature: publication.head.signature,
                headClaims: tampered
            )
        )
    }

    func testV2RelayNamespaceProfileStillVerifiesExactly() throws {
        let publicationID = UUID().uuidString.lowercased()
        let identity = try PublicationSigningIdentity(
            publicationID: publicationID,
            rawPrivateKey: Data(repeating: 11, count: 32)
        )
        let namespace = try XCTUnwrap(
            RelayTopology.labDefault.nodes
                .first { $0.id == "host-lisbon" }?
                .relayNamespace()
        )
        let object = CapsuleObject(
            protocolVersion: CapsuleObject.relayNamespaceProtocolVersion,
            publicationID: publicationID,
            address: "noct://legacy-v2.lisbon/",
            relayNamespaceID: namespace.id,
            routeDirective: nil,
            publisherID: identity.publisherID,
            revision: 1,
            previousObjectID: nil,
            title: "V2",
            subtitle: "",
            body: "Preserved.",
            accentHex: "#4f8f77",
            bundle: try bundle().canonicalized()
        )
        XCTAssertNoThrow(try PublicationValidation.validateObject(object))
        let objectID = NoctwebDigest.objectID(
            for: try CanonicalJSON.encode(object)
        )
        let claims = PublisherHeadClaims(
            protocolVersion: CapsuleObject.relayNamespaceProtocolVersion,
            publicationID: publicationID,
            address: object.address,
            relayNamespaceID: namespace.id,
            routeDirective: nil,
            publisherID: identity.publisherID,
            publisherPublicKey: identity.publicKey,
            objectID: objectID,
            revision: 1,
            previousHeadID: nil,
            issuedAtMilliseconds: 1_700_000_000_000
        )
        let signature = try identity.sign(headClaims: claims)
        XCTAssertTrue(
            PublicationSigningIdentity.verify(
                signature: signature,
                headClaims: claims
            )
        )
    }

    func testRelayModulesMustBeUniqueCanonicalAndIncludePrimaryRole() {
        let endpoint = URL(string: "https://modules.invalid")!
        XCTAssertThrowsError(
            try RelayTopology(
                nodes: [
                    RelayNode(
                        id: "duplicate",
                        name: "Duplicate",
                        role: .standard,
                        endpoint: endpoint,
                        advertisedModules: [.standard, .host, .host]
                    )
                ]
            )
        )
        XCTAssertThrowsError(
            try RelayTopology(
                nodes: [
                    RelayNode(
                        id: "reordered",
                        name: "Reordered",
                        role: .standard,
                        endpoint: endpoint,
                        advertisedModules: [.host, .standard]
                    )
                ]
            )
        )
        XCTAssertThrowsError(
            try RelayTopology(
                nodes: [
                    RelayNode(
                        id: "missing-primary",
                        name: "Missing primary",
                        role: .standard,
                        endpoint: endpoint,
                        advertisedModules: [.host]
                    )
                ]
            )
        )
    }

    func testSameSiteLabelCanExistInDifferentRelayNamespaces() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let lisbon = try await engine.publish(
            draft: draft(namespaceRelayID: "host-lisbon")
        )
        let salvador = try await engine.publish(
            draft: draft(namespaceRelayID: "host-salvador")
        )

        XCTAssertNotEqual(lisbon.object.address, salvador.object.address)
        XCTAssertNotEqual(
            lisbon.object.relayNamespaceID,
            salvador.object.relayNamespaceID
        )
        XCTAssertEqual(
            try NoctwebAddress.parse(lisbon.object.address).siteLabel,
            try NoctwebAddress.parse(salvador.object.address).siteLabel
        )
        _ = try await engine.resolve(
            address: lisbon.object.address,
            preference: .direct
        )
        _ = try await engine.resolve(
            address: salvador.object.address,
            preference: .direct
        )
    }

    func testSameFullNameCannotBeClaimedByAnotherPublication() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let first = draft()
        _ = try await engine.publish(draft: first)

        let second = draft()
        do {
            _ = try await engine.publish(draft: second)
            XCTFail("a finalized relay-scoped name must have one publication")
        } catch let error as NoctwebLabError {
            XCTAssertEqual(
                error,
                .publisherMismatch(
                    expected: first.publicationID,
                    actual: second.publicationID
                )
            )
        }
    }

    func testAddressSuffixMustMatchSignedRelayNamespaceIdentity() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        var mismatched = draft(namespaceRelayID: "host-lisbon")
        let salvador = try XCTUnwrap(
            RelayTopology.labDefault.nodes
                .first { $0.id == "host-salvador" }?
                .relayNamespace()
        )
        mismatched.relayNamespaceID = salvador.id

        do {
            _ = try await engine.publish(draft: mismatched)
            XCTFail("suffix and full relay namespace identity must be bound")
        } catch let error as NoctwebLabError {
            guard case .invalidRelayTopology = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testRestoreCannotReplaceFinalizedNameWithAnotherPublisher() async throws {
        let firstEngine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let secondEngine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let first = try await firstEngine.publish(draft: draft())
        let second = try await secondEngine.publish(draft: draft())
        let restoreEngine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )

        try await restoreEngine.restore(first)
        do {
            try await restoreEngine.restore(second)
            XCTFail("restore must not rebind a finalized name")
        } catch let error as NoctwebLabError {
            XCTAssertEqual(
                error,
                .publisherMismatch(
                    expected: first.object.publisherID,
                    actual: second.object.publisherID
                )
            )
        }

        let resolved = try await restoreEngine.resolve(
            address: first.object.address,
            preference: .direct
        )
        XCTAssertEqual(resolved.object.publisherID, first.object.publisherID)
        XCTAssertEqual(resolved.headID, first.headID)
    }

    func testRestoreCannotRollBackANewerAcceptedRevision() async throws {
        let source = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        var initialDraft = draft(bundle: bundle())
        let first = try await source.publish(draft: initialDraft)
        initialDraft.title = "Quiet Garden, revised"
        let second = try await source.publish(draft: initialDraft)
        let restoreEngine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )

        try await restoreEngine.restore(second)
        do {
            try await restoreEngine.restore(first)
            XCTFail("restore must not roll a finalized name back")
        } catch let error as NoctwebLabError {
            guard case .invalidFinality = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        let resolved = try await restoreEngine.resolve(
            address: second.object.address,
            preference: .direct
        )
        XCTAssertEqual(resolved.object.revision, 2)
        XCTAssertEqual(resolved.headID, second.headID)
    }

    func testLegacyV1ReadValidationMatchesOriginalAddressProfile() throws {
        let publicationID = UUID().uuidString.lowercased()
        let identity = try PublicationSigningIdentity(
            publicationID: publicationID,
            rawPrivateKey: Data(repeating: 9, count: 32)
        )
        let acceptedAddresses = [
            "noct://legacy-site",
            "noct://legacy-site/",
            "noct://legacy.example/",
            "noct://user@legacy.example:9340/?mode=old#section",
        ]
        let legacyBundle = try WebsiteBundleValidation.canonicalized(bundle())

        for address in acceptedAddresses {
            let object = CapsuleObject(
                protocolVersion: CapsuleObject.legacyProtocolVersion,
                publicationID: publicationID,
                address: address,
                publisherID: identity.publisherID,
                revision: 1,
                previousObjectID: nil,
                title: "Legacy",
                subtitle: "",
                body: "Signed under the v1 read profile.",
                accentHex: "#4f8f77",
                bundle: legacyBundle
            )
            XCTAssertNoThrow(try PublicationValidation.validateObject(object))

            let claims = PublisherHeadClaims(
                protocolVersion: CapsuleObject.legacyProtocolVersion,
                publicationID: publicationID,
                address: address,
                publisherID: identity.publisherID,
                publisherPublicKey: identity.publicKey,
                objectID: "sha256:" + String(repeating: "a", count: 64),
                revision: 1,
                previousHeadID: nil,
                issuedAtMilliseconds: 1_700_000_000_000
            )
            let signature = try identity.sign(headClaims: claims)
            XCTAssertTrue(
                PublicationSigningIdentity.verify(
                    signature: signature,
                    headClaims: claims
                )
            )
        }

        XCTAssertThrowsError(
            try PublicationValidation.validateLegacyAddress(
                "https://legacy-site/"
            )
        )
        XCTAssertThrowsError(
            try PublicationValidation.validateLegacyAddress("noct:///")
        )
    }

    func testWorkspaceDecodeAndSaveRejectInvalidRelayNamespaces() throws {
        var nodes = RelayTopology.labDefault.nodes
        let salvadorIndex = try XCTUnwrap(
            nodes.firstIndex { $0.id == "host-salvador" }
        )
        nodes[salvadorIndex].namespaceSuffix = "lisbon"
        let snapshot = WorkspaceSnapshot(
            selectedPublicationID: nil,
            publications: [],
            relays: nodes
        )
        let encoded = try CanonicalJSON.encode(snapshot)

        XCTAssertThrowsError(
            try CanonicalJSON.decode(
                WorkspaceSnapshot.self,
                from: encoded
            )
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = JSONWorkspaceRepository(
            fileURL: root.appendingPathComponent("workspace.json")
        )
        XCTAssertThrowsError(try repository.save(snapshot))
    }

    func testPublishAndResolveThroughDirectAndPassthroughRoutes() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let publication = try await engine.publish(
            draft: draft(),
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(publication.hostRelayIDs.count, 3)

        let direct = try await engine.resolve(
            address: publication.object.address,
            preference: .direct
        )
        XCTAssertTrue(direct.evidence.integrity.verified)
        XCTAssertTrue(direct.evidence.publisher.signatureValid)
        XCTAssertTrue(direct.evidence.publisher.identityBound)
        XCTAssertTrue(direct.evidence.finality.finalized)
        guard case .direct = direct.route else {
            return XCTFail("expected direct host route")
        }

        let passthrough = try await engine.resolve(
            address: publication.object.address,
            preference: .passthrough
        )
        guard case .passthrough = passthrough.route else {
            return XCTFail("expected bounded passthrough route")
        }
    }

    func testWebsiteBundleRoundTripsExactBytesAcrossBothRoutes() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let original = bundle()
        let publication = try await engine.publish(
            draft: draft(bundle: original),
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(publication.object.protocolVersion, "noctweb-lab-v3")
        XCTAssertEqual(
            publication.object.bundle?.files.map(\.path),
            original.files.map(\.path).sorted()
        )
        for preference in [LabRoute.direct, .passthrough] {
            let result = try await engine.resolve(
                address: publication.object.address,
                preference: preference
            )
            for source in original.files {
                let resolved = result.object.bundle?.file(at: source.path)
                XCTAssertEqual(resolved?.mediaType, source.mediaType)
                XCTAssertEqual(resolved?.bytes, source.bytes)
            }
        }
        XCTAssertEqual(
            publication.object.bundle?.file(at: "assets/app.js")?.bytes,
            Data("globalThis.noctweb = 'ready';".utf8)
        )
        XCTAssertEqual(
            publication.object.bundle?.file(at: "assets/pixel.bin")?.bytes,
            Data([0x00, 0xff, 0x10, 0x80])
        )
    }

    func testWebsiteBundleOrderingProducesDeterministicObjectID() async throws {
        let publicationID = "47e0951d-a5ef-4db1-8e1e-e276fbd8536d"
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let unsorted = bundle()
        let sorted = WebsiteBundle(
            entryPath: unsorted.entryPath,
            files: unsorted.files.sorted { $0.path < $1.path }
        )

        let firstStore = InMemoryPublicationPrivateKeyStore()
        let firstEngine = try NoctwebLabEngine(identityStore: firstStore)
        let first = try await firstEngine.publish(
            draft: draft(publicationID: publicationID, bundle: unsorted),
            at: timestamp
        )
        let privateKey = try XCTUnwrap(
            firstStore.loadPrivateKey(for: publicationID)
        )
        let secondStore = InMemoryPublicationPrivateKeyStore(
            keys: [publicationID: privateKey]
        )
        let secondEngine = try NoctwebLabEngine(identityStore: secondStore)
        let second = try await secondEngine.publish(
            draft: draft(publicationID: publicationID, bundle: sorted),
            expectedPublisherID: first.object.publisherID,
            at: timestamp
        )

        XCTAssertEqual(first.encodedObject, second.encodedObject)
        XCTAssertEqual(
            first.head.claims.objectID,
            second.head.claims.objectID
        )
    }

    func testWebsiteBundleRejectsUnsafeAndAmbiguousPaths() async throws {
        let candidates: [WebsiteBundle] = [
            WebsiteBundle(
                entryPath: "index.html",
                files: [
                    WebsiteFile(
                        path: "../index.html",
                        mediaType: "text/html",
                        bytes: Data()
                    ),
                ]
            ),
            WebsiteBundle(
                entryPath: "index.html",
                files: [
                    WebsiteFile(
                        path: "/index.html",
                        mediaType: "text/html",
                        bytes: Data()
                    ),
                ]
            ),
            WebsiteBundle(
                entryPath: "",
                files: [
                    WebsiteFile(
                        path: "index.html",
                        mediaType: "text/html",
                        bytes: Data()
                    ),
                ]
            ),
            WebsiteBundle(
                entryPath: "index.html",
                files: [
                    WebsiteFile(
                        path: "index.html",
                        mediaType: "text/html",
                        bytes: Data()
                    ),
                    WebsiteFile(
                        path: "index.html",
                        mediaType: "text/html",
                        bytes: Data()
                    ),
                ]
            ),
            WebsiteBundle(
                entryPath: "index.html",
                files: [
                    WebsiteFile(
                        path: "index.html",
                        mediaType: "text/html",
                        bytes: Data()
                    ),
                    WebsiteFile(
                        path: "INDEX.HTML",
                        mediaType: "text/html",
                        bytes: Data()
                    ),
                ]
            ),
            WebsiteBundle(
                entryPath: "missing.html",
                files: [
                    WebsiteFile(
                        path: "index.html",
                        mediaType: "text/html",
                        bytes: Data()
                    ),
                ]
            ),
            WebsiteBundle(
                entryPath: "index.html",
                files: [
                    WebsiteFile(
                        path: "index.html",
                        mediaType: "text/html",
                        bytes: Data()
                    ),
                    WebsiteFile(
                        path: "assets%2Fapp.js",
                        mediaType: "text/javascript",
                        bytes: Data()
                    ),
                ]
            ),
            WebsiteBundle(entryPath: "index.html", files: []),
        ]

        for candidate in candidates {
            let engine = try NoctwebLabEngine(
                identityStore: InMemoryPublicationPrivateKeyStore()
            )
            do {
                _ = try await engine.publish(draft: draft(bundle: candidate))
                XCTFail("invalid website bundle was accepted: \(candidate)")
            } catch let error as NoctwebLabError {
                guard case .invalidWebsiteBundle = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testWebsiteBundleRejectsFileCountAndByteLimits() async throws {
        let tooManyFiles = (0...WebsiteBundle.maximumFileCount).map {
            WebsiteFile(
                path: $0 == 0 ? "index.html" : "asset-\($0).bin",
                mediaType: "application/octet-stream",
                bytes: Data()
            )
        }
        let candidates = [
            WebsiteBundle(entryPath: "index.html", files: tooManyFiles),
            WebsiteBundle(
                entryPath: "index.html",
                files: [
                    WebsiteFile(
                        path: "index.html",
                        mediaType: "text/html",
                        bytes: Data(
                            repeating: 0x61,
                            count: WebsiteBundle.maximumTotalBytes + 1
                        )
                    ),
                ]
            ),
        ]

        for candidate in candidates {
            let engine = try NoctwebLabEngine(
                identityStore: InMemoryPublicationPrivateKeyStore()
            )
            do {
                _ = try await engine.publish(draft: draft(bundle: candidate))
                XCTFail("oversized website bundle was accepted")
            } catch let error as NoctwebLabError {
                guard case .invalidWebsiteBundle = error else {
                    return XCTFail("unexpected error: \(error)")
                }
            }
        }
    }

    func testHostFailoverUsesSecondReplica() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let publication = try await engine.publish(draft: draft())
        try await engine.setRelayOnline(false, relayID: "host-lisbon")

        let result = try await engine.resolve(
            address: publication.object.address,
            preference: .direct
        )
        XCTAssertEqual(result.route.hostRelayID, "host-salvador")
    }

    func testCorruptedOnlyReplicaFailsClosed() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let publication = try await engine.publish(draft: draft())
        try await engine.corruptReplica(
            address: publication.object.address,
            hostRelayID: "host-lisbon"
        )
        try await engine.setRelayOnline(false, relayID: "host-salvador")
        try await engine.setRelayOnline(false, relayID: "standard-local")

        do {
            _ = try await engine.resolve(
                address: publication.object.address,
                preference: .direct
            )
            XCTFail("corrupt bytes must never reach the renderer")
        } catch let error as NoctwebLabError {
            guard case .integrityMismatch = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testTamperedDecodedWebsiteObjectFailsClosedOnRestore() async throws {
        let originalEngine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let publication = try await originalEngine.publish(
            draft: draft(bundle: bundle())
        )
        var tamperedBundle = try XCTUnwrap(publication.object.bundle)
        tamperedBundle.files[0].bytes.append(0x00)
        let object = publication.object
        let tamperedObject = CapsuleObject(
            protocolVersion: object.protocolVersion,
            publicationID: object.publicationID,
            address: object.address,
            relayNamespaceID: object.relayNamespaceID,
            publisherID: object.publisherID,
            revision: object.revision,
            previousObjectID: object.previousObjectID,
            title: object.title,
            subtitle: object.subtitle,
            body: object.body,
            accentHex: object.accentHex,
            bundle: tamperedBundle
        )
        let tamperedPublication = PublishedCapsule(
            object: tamperedObject,
            encodedObject: publication.encodedObject,
            head: publication.head,
            headID: publication.headID,
            hostRelayIDs: publication.hostRelayIDs,
            finality: publication.finality
        )
        let restoreEngine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )

        do {
            try await restoreEngine.restore(tamperedPublication)
            XCTFail("a tampered decoded website object must not be restored")
        } catch let error as NoctwebLabError {
            guard case .integrityMismatch = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testTamperedHeadDoesNotVerify() throws {
        let publicationID = UUID().uuidString.lowercased()
        let identity = try PublicationSigningIdentity(
            publicationID: publicationID,
            rawPrivateKey: Data(repeating: 7, count: 32)
        )
        let claims = PublisherHeadClaims(
            publicationID: publicationID,
            address: "noct://quiet-garden.lisbon/",
            relayNamespaceID: try XCTUnwrap(
                RelayTopology.labDefault.nodes
                    .first { $0.id == "host-lisbon" }?
                    .relayNamespace()?
                    .id
            ),
            routeDirective: .open,
            publisherID: identity.publisherID,
            publisherPublicKey: identity.publicKey,
            objectID: "sha256:" + String(repeating: "a", count: 64),
            revision: 1,
            previousHeadID: nil,
            issuedAtMilliseconds: 1_700_000_000_000
        )
        let signature = try identity.sign(headClaims: claims)
        XCTAssertTrue(
            PublicationSigningIdentity.verify(
                signature: signature,
                headClaims: claims
            )
        )

        let tampered = PublisherHeadClaims(
            publicationID: publicationID,
            address: claims.address,
            relayNamespaceID: claims.relayNamespaceID,
            routeDirective: claims.routeDirective,
            publisherID: claims.publisherID,
            publisherPublicKey: claims.publisherPublicKey,
            objectID: "sha256:" + String(repeating: "b", count: 64),
            revision: claims.revision,
            previousHeadID: claims.previousHeadID,
            issuedAtMilliseconds: claims.issuedAtMilliseconds
        )
        XCTAssertFalse(
            PublicationSigningIdentity.verify(
                signature: signature,
                headClaims: tampered
            )
        )
    }

    func testExistingPublicationNeverSilentlyRegeneratesMissingKey() async throws {
        let firstStore = InMemoryPublicationPrivateKeyStore()
        let first = try NoctwebLabEngine(identityStore: firstStore)
        let published = try await first.publish(draft: draft())

        let replacement = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        do {
            _ = try await replacement.publish(
                draft: CapsuleSiteDraft(
                    publicationID: published.object.publicationID,
                    address: published.object.address,
                    relayNamespaceID: published.object.relayNamespaceID,
                    title: published.object.title,
                    subtitle: published.object.subtitle,
                    body: published.object.body,
                    accentHex: published.object.accentHex
                ),
                expectedPublisherID: published.object.publisherID
            )
            XCTFail("missing established identity must block publishing")
        } catch let error as NoctwebLabError {
            XCTAssertEqual(
                error,
                .identityMissing(published.object.publicationID)
            )
        }
    }

    func testPublisherContinuityAcrossWebsiteRevisions() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let initialDraft = draft(bundle: bundle())
        let first = try await engine.publish(draft: initialDraft)

        var revisedDraft = initialDraft
        revisedDraft.bundle?.files.append(
            WebsiteFile(
                path: "assets/chunk.js",
                mediaType: "text/javascript",
                bytes: Data("export const version = 2;".utf8)
            )
        )
        let second = try await engine.publish(draft: revisedDraft)

        XCTAssertEqual(second.object.publisherID, first.object.publisherID)
        XCTAssertEqual(second.object.revision, 2)
        XCTAssertEqual(
            second.object.previousObjectID,
            first.head.claims.objectID
        )
    }

    func testPublisherIdentityDeletionIsExplicitAndIdempotent() async throws {
        let store = InMemoryPublicationPrivateKeyStore()
        let engine = try NoctwebLabEngine(identityStore: store)
        let publication = try await engine.publish(draft: draft(bundle: bundle()))
        XCTAssertNotNil(
            try store.loadPrivateKey(for: publication.object.publicationID)
        )

        try await engine.deletePublisherIdentity(
            for: publication.object.publicationID
        )
        try await engine.deletePublisherIdentity(
            for: publication.object.publicationID
        )
        XCTAssertNil(
            try store.loadPrivateKey(for: publication.object.publicationID)
        )

        do {
            _ = try await engine.publish(
                draft: draft(
                    publicationID: publication.object.publicationID,
                    bundle: bundle()
                )
            )
            XCTFail("publisher continuity must fail after key deletion")
        } catch let error as NoctwebLabError {
            XCTAssertEqual(
                error,
                .identityMissing(publication.object.publicationID)
            )
        }
    }

    func testWorkspaceRepositoryRoundTripsAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONWorkspaceRepository(
            fileURL: directory.appendingPathComponent("workspace.json")
        )
        let snapshot = WorkspaceSnapshot(
            selectedPublicationID: nil,
            publications: [],
            relays: RelayTopology.labDefault.nodes
        )
        try repository.save(snapshot)
        XCTAssertEqual(try repository.load(), snapshot)
    }
}
