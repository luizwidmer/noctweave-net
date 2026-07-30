import Foundation
import NoctwebBrowserCore
import NoctwebLabCore
@testable import NoctwebBrowser
import XCTest

final class NoctwebBrowserAppTests: XCTestCase {
    @MainActor
    func testProductionAppStartsUnconfiguredWithoutCrashing() throws {
        let suiteName = "NoctwebBrowserTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = BrowserAppModel(
            persistenceStore: BrowserPersistenceStore(defaults: defaults)
        )

        XCTAssertFalse(model.relayIsConfigured)
        XCTAssertEqual(model.activeRelayEndpoint, nil)
        XCTAssertEqual(model.addressText, "noct://start.unconfigured/")
        XCTAssertEqual(
            model.selectedProfile.routingTrustDomainID,
            "sha256:" + String(repeating: "0", count: 64)
        )
    }

    func testRelayIdentityBecomesCanonicalRoutingTrustDomain() {
        XCTAssertEqual(
            BrowserAppModel.relayTrustDomainID(
                "nwr1\(String(repeating: "a", count: 64))"
            ),
            "sha256:\(String(repeating: "a", count: 64))"
        )
    }

    @MainActor
    func testDefaultAppResolvesVerifiedFixture() async throws {
        let suiteName = "NoctwebBrowserTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = BrowserAppModel(
            persistenceStore: BrowserPersistenceStore(defaults: defaults),
            useDevelopmentFixtures: true
        )

        model.startIfNeeded()
        for _ in 0..<200
        where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(
            model.selectedTab.verificationState,
            .fixtureVerified
        )
        XCTAssertEqual(
            model.selectedSite?.navigationURL.canonicalString,
            DeterministicNoctwebResolver.welcomeURLString
        )
        XCTAssertNotNil(model.selectedSite?.evidence.publisherID)
        XCTAssertNil(model.selectedError)

        let verifiedSite = model.selectedSite
        model.handleBlockedWebsiteNavigation(
            URL(string: "https://example.com/")!,
            tabID: model.selectedTab.id
        )
        XCTAssertEqual(model.selectedSite, verifiedSite)
        XCTAssertTrue(
            model.selectedBlockedNotice?.contains(
                "External navigation blocked"
            ) == true
        )
        model.dismissBlockedNavigationNotice()
        XCTAssertNil(model.selectedBlockedNotice)
    }

    func testPublicationOriginIncludesVerifiedIdentityMaterial() async throws {
        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        let site = try await environment.resolver.resolve(
            environment.welcomeURL,
            profile: environment.profile,
            visitorDirective: .open
        )
        let snapshot = NoctwebRendererSnapshot(site: site)

        XCTAssertTrue(snapshot.host.hasPrefix("publication-"))
        XCTAssertFalse(snapshot.host.contains(site.navigationURL.relaySuffix))
        XCTAssertEqual(snapshot.rootURL.scheme, "noctweb-site")
        XCTAssertEqual(snapshot.rootURL.host, snapshot.host)
        XCTAssertEqual(snapshot.files.count, site.bundle.files.count)
    }

    func testDevelopmentResolverReverifiesNativeLabPublication() async throws {
        guard
            let relayEndpoint = ProcessInfo.processInfo.environment[
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
        let client = try NoctwebHostRelayClient(endpoint: relayEndpoint)
        let relayConfiguration = try await client.discover(force: true)
        let namespace = try XCTUnwrap(relayConfiguration.relayNamespace)
        let sourceBundle = NoctwebLabCore.WebsiteBundle(
            entryPath: "index.html",
            files: [
                NoctwebLabCore.WebsiteFile(
                    path: "index.html",
                    mediaType: "text/html; charset=utf-8",
                    bytes: Data(
                        "<!doctype html><title>Hosted Lab proof</title>".utf8
                    )
                ),
            ]
        )
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let address = "noct://browser-lab.\(namespace.suffix)/"
        let publication = try await engine.makeHostedPublication(
            draft: CapsuleSiteDraft(
                publicationID: UUID().uuidString.lowercased(),
                address: address,
                relayNamespaceID: namespace.id,
                routeDirective: NoctwebLabCore.RouteDirective.open,
                title: "Hosted Lab proof",
                subtitle: "Native authoring",
                body: "Signed local publication",
                accentHex: "#4F8F77",
                bundle: sourceBundle
            ),
            relayNamespace: namespace
        )
        let envelope = try CanonicalJSON.encode(publication)
        let put = try await client.put(
            payload: envelope,
            ttlSeconds: relayConfiguration.minimumRetentionSeconds,
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
        let workspaceData = try JSONSerialization.data(
            withJSONObject: [
                [
                    "sites": [
                        [
                            "address": address,
                            "relayNamespaceID": namespace.id,
                            "hostRelayEndpoint": relayEndpoint,
                            "hostObjectID": put.receipt.objectID,
                        ],
                    ],
                ],
            ]
        )
        let root = FileManager.default.temporaryDirectory.appending(
            path: "NoctwebBrowserLabResolverTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let workspaceURL = root.appending(path: "workspaces.json")
        try workspaceData.write(to: workspaceURL, options: .atomic)

        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        let resolver = DevelopmentNoctwebResolver(
            fixtureResolver: environment.resolver,
            labWorkspaceURL: workspaceURL
        )
        let site = try await resolver.resolve(
            NoctwebNavigationURL(parsing: address),
            profile: environment.profile,
            visitorDirective: NoctwebBrowserCore.RouteDirective.open
        )

        XCTAssertEqual(site.title, "Hosted Lab proof")
        XCTAssertEqual(site.state, .hostedPreview)
        XCTAssertEqual(site.evidence.publisherID, publication.object.publisherID)
        XCTAssertEqual(
            site.bundle.files.first?.bytes,
            sourceBundle.files.first?.bytes
        )
    }

    func testRendererSourceKeepsWebsiteOutsideNativeAndNetworkBoundaries()
        throws
    {
        let source = try String(
            contentsOf: packageRoot
                .appending(path: "Sources/NoctwebBrowser/VerifiedWebsiteView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("websiteDataStore = .nonPersistent()"))
        XCTAssertTrue(source.contains("javaScriptCanOpenWindowsAutomatically = false"))
        XCTAssertTrue(source.contains("WKURLSchemeHandler"))
        XCTAssertTrue(source.contains("connect-src 'self' data: blob:"))
        XCTAssertTrue(source.contains("webrtc 'block'"))
        XCTAssertTrue(source.contains("X-DNS-Prefetch-Control"))
        XCTAssertTrue(source.contains("Permissions-Policy"))
        XCTAssertTrue(source.contains("decideMediaCapturePermissionsFor"))
        XCTAssertTrue(source.contains("onBlockedNavigation"))
        XCTAssertFalse(source.contains("loadHTMLString"))
        XCTAssertFalse(source.contains("addScriptMessageHandler"))
    }

    func testFederatedResolverAcceptsFreshClaimsFromAnchoredAuthority()
        throws
    {
        let source = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/NoctwebBrowser/FederatedNoctwebResolver.swift"
            ),
            encoding: .utf8
        )

        XCTAssertFalse(
            source.contains("federated.destinationIdentity == identity")
        )
        XCTAssertTrue(source.contains("sameRelayAuthority("))
        XCTAssertTrue(
            source.contains(
                "live.claim.signingPublicKey"
                    + "\n                == anchored.claim.signingPublicKey"
            )
        )
        XCTAssertTrue(
            source.contains(
                "live.claim.hostSigningPublicKey"
                    + "\n                == anchored.claim.hostSigningPublicKey"
            )
        )
        XCTAssertTrue(
            source.contains(
                "live.claim.noctwebSuffix"
                    + "\n                == anchored.claim.noctwebSuffix"
            )
        )
        XCTAssertTrue(
            source.contains(
                "live.claim.federationName"
                    + "\n                == anchored.claim.federationName"
            )
        )
    }

    func testApplicationBundleRegistersNativeNoctwebEntryPoints() throws {
        let data = try Data(
            contentsOf: packageRoot.appending(path: "Packaging/Info.plist")
        )
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        )
        let URLTypes = try XCTUnwrap(
            plist["CFBundleURLTypes"] as? [[String: Any]]
        )
        let schemes = try XCTUnwrap(
            URLTypes.first?["CFBundleURLSchemes"] as? [String]
        )
        XCTAssertEqual(schemes, ["noct"])

        let declarations = try XCTUnwrap(
            plist["UTExportedTypeDeclarations"] as? [[String: Any]]
        )
        XCTAssertEqual(
            declarations.first?["UTTypeIdentifier"] as? String,
            "net.noctweave.noctlink"
        )
    }

    @MainActor
    func testSidePanelsRemainUncrowdedAndMutuallyExclusive() throws {
        let suiteName = "NoctwebBrowserTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = BrowserAppModel(
            persistenceStore: BrowserPersistenceStore(defaults: defaults),
            useDevelopmentFixtures: true
        )

        XCTAssertTrue(model.showsSidebar)
        XCTAssertFalse(model.showsTrustInspector)

        model.toggleTrustInspector()
        XCTAssertFalse(model.showsSidebar)
        XCTAssertTrue(model.showsTrustInspector)

        model.toggleSidebar()
        XCTAssertTrue(model.showsSidebar)
        XCTAssertFalse(model.showsTrustInspector)
    }

    func testSidebarFillsWindowHeightInsteadOfCenteringItsContents() throws {
        let source = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/NoctwebBrowser/BrowserWindowView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains(
                ".frame(maxHeight: .infinity, alignment: .top)"
            )
        )
        XCTAssertTrue(
            source.contains(
                ".frame(maxWidth: .infinity, maxHeight: .infinity)"
            )
        )
    }

    @MainActor
    func testVisitorRoutePreferenceRecomputesEffectivePolicy() async throws {
        let suiteName = "NoctwebBrowserTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = BrowserAppModel(
            persistenceStore: BrowserPersistenceStore(defaults: defaults),
            useDevelopmentFixtures: true
        )
        model.startIfNeeded()
        for _ in 0..<200
        where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }

        model.setVisitorDirective(.passthrough)
        for _ in 0..<200
        where model.selectedTab.verificationState == .resolving {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(model.selectedVisitorDirective, .passthrough)
        XCTAssertEqual(
            model.selectedSite?.evidence.route.directive,
            .passthrough
        )
        XCTAssertEqual(
            model.selectedSite?.evidence.route.authority,
            .visitor
        )
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
