import Foundation
import NoctwebBrowserCore
@testable import NoctwebBrowser
import XCTest

final class NoctwebBrowserAppTests: XCTestCase {
    @MainActor
    func testDefaultAppResolvesVerifiedFixture() async throws {
        let suiteName = "NoctwebBrowserTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = BrowserAppModel(
            persistenceStore: BrowserPersistenceStore(defaults: defaults)
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
            persistenceStore: BrowserPersistenceStore(defaults: defaults)
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

    @MainActor
    func testVisitorRoutePreferenceRecomputesEffectivePolicy() async throws {
        let suiteName = "NoctwebBrowserTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = BrowserAppModel(
            persistenceStore: BrowserPersistenceStore(defaults: defaults)
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
