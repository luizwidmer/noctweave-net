import CryptoKit
import Foundation
import XCTest
@testable import NoctwebBrowserCore

final class NoctwebBrowserCoreTests: XCTestCase {
    func testNavigationURLCanonicalizesBaseAndDeepLink() throws {
        let base = try NoctwebNavigationURL(
            parsing: "noct://welcome.local-dev/"
        )
        XCTAssertEqual(base.siteLabel, "welcome")
        XCTAssertEqual(base.relaySuffix, "local-dev")
        XCTAssertEqual(base.baseAddress, "noct://welcome.local-dev/")
        XCTAssertEqual(base.canonicalString, "noct://welcome.local-dev/")

        let deep = try NoctwebNavigationURL(
            parsing: "noct://welcome.local-dev/docs/start?mode=compact#install"
        )
        XCTAssertEqual(deep.baseAddress, base.baseAddress)
        XCTAssertEqual(deep.requestPath, "/docs/start")
        XCTAssertEqual(
            deep.canonicalString,
            "noct://welcome.local-dev/docs/start?mode=compact#install"
        )
    }

    func testNavigationURLRejectsAmbiguousAndUnsafeForms() {
        for value in [
            "https://welcome.local-dev/",
            "noct://welcome.local-dev",
            "noct://WELCOME.local-dev/",
            "noct://welcome.local-dev.extra/",
            "noct://user@welcome.local-dev/",
            "noct://welcome.local-dev:443/",
            "noct://welcome.local-dev/a/../b",
            "noct://welcome.local-dev/a//b",
            "noct://welcome.local-dev/%2Fetc",
            "noct://welcome.local-dev/?value=%0A",
            "noct://xn--site.local-dev/",
        ] {
            XCTAssertThrowsError(
                try NoctwebNavigationURL(parsing: value),
                "unexpectedly accepted \(value)"
            )
        }
    }

    func testAddressBarInputAddsNoctSchemeAndRootPath() throws {
        XCTAssertEqual(
            try NoctwebNavigationURL(userInput: "welcome.local-dev")
                .canonicalString,
            "noct://welcome.local-dev/"
        )
        XCTAssertEqual(
            try NoctwebNavigationURL(userInput: "noct://welcome.local-dev")
                .canonicalString,
            "noct://welcome.local-dev/"
        )
        XCTAssertEqual(
            try NoctwebNavigationURL(
                userInput: "  welcome.local-dev/docs/start?mode=compact#install  "
            ).canonicalString,
            "noct://welcome.local-dev/docs/start?mode=compact#install"
        )
    }

    func testAddressBarInputDoesNotRewriteForeignOrAmbiguousSchemes() {
        for value in [
            "https://welcome.local-dev",
            "javascript:alert(1)",
            "noct:welcome.local-dev",
            "user@welcome.local-dev",
            "welcome.local-dev:443",
        ] {
            XCTAssertThrowsError(
                try NoctwebNavigationURL(userInput: value),
                "unexpectedly accepted \(value)"
            )
        }
    }

    func testNetworkProfileEnforcesTrustAndBootstrapBounds() throws {
        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        XCTAssertEqual(environment.profile.version, 1)
        XCTAssertEqual(environment.profile.bootstrapEndpoints.count, 1)
        XCTAssertTrue(environment.profile.supports(epoch: 1))

        XCTAssertThrowsError(
            try NoctwebNetworkProfile(
                id: "unsafe",
                displayName: "Unsafe",
                routingTrustDomainID: environment.profile
                    .routingTrustDomainID,
                consensusProfileID: "unsafe",
                verificationKey: Data(repeating: 1, count: 32),
                bootstrapEndpoints: [
                    URL(string: "http://example.com/relay")!,
                ],
                supportedEpochs: [1],
                federationMode: .solo,
                federationDirective: .open,
                defaultVisitorDirective: .open
            )
        )
        XCTAssertThrowsError(
            try NoctwebNetworkProfile(
                id: "unsafe",
                displayName: "Unsafe",
                routingTrustDomainID: environment.profile
                    .routingTrustDomainID,
                consensusProfileID: "unsafe",
                verificationKey: Data(repeating: 1, count: 32),
                bootstrapEndpoints: [],
                supportedEpochs: [2, 1],
                federationMode: .solo,
                federationDirective: .open,
                defaultVisitorDirective: .open
            )
        )
    }

    func testManualNamespacePolicyDefaultsToUnanimity() throws {
        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        let signers = [
            NoctwebNamespaceSigner(
                relayID: "nwr1\(String(repeating: "a", count: 64))",
                signingPublicKey: Data(repeating: 0x11, count: 1_952)
            ),
            NoctwebNamespaceSigner(
                relayID: "nwr1\(String(repeating: "b", count: 64))",
                signingPublicKey: Data(repeating: 0x22, count: 1_952)
            )
        ]
        let profile = try NoctwebNetworkProfile(
            id: "manual-federation",
            displayName: "Manual federation",
            routingTrustDomainID:
                environment.profile.routingTrustDomainID,
            consensusProfileID: "noctweb.namespace.v1",
            verificationKey: Data(repeating: 0x33, count: 32),
            bootstrapEndpoints: [
                URL(string: "https://relay.example")!
            ],
            supportedEpochs: [1],
            federationMode: .manual,
            namespaceFederationName: "friends",
            federationDirective: .open,
            defaultVisitorDirective: .open,
            namespaceSigners: signers
        )

        XCTAssertEqual(profile.namespaceThreshold, signers.count)
        XCTAssertEqual(
            try JSONDecoder().decode(
                NoctwebNetworkProfile.self,
                from: JSONEncoder().encode(profile)
            ),
            profile
        )
    }

    func testCodableEntryPointsReapplySecurityValidation() throws {
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                NoctwebNavigationURL.self,
                from: Data(#""https://example.com/""#.utf8)
            )
        )

        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        var profile = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(environment.profile)
            ) as? [String: Any]
        )
        profile["routingTrustDomainID"] =
            "sha256:\(String(repeating: "١", count: 64))"
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                NoctwebNetworkProfile.self,
                from: JSONSerialization.data(withJSONObject: profile)
            )
        )
        profile = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(environment.profile)
            ) as? [String: Any]
        )
        profile["id"] = "local١"
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                NoctwebNetworkProfile.self,
                from: JSONSerialization.data(withJSONObject: profile)
            )
        )

        let unsafeBundle: [String: Any] = [
            "entryPath": "../index.html",
            "files": [
                [
                    "path": "../index.html",
                    "mediaType": "text/html",
                    "bytes": Data("unsafe".utf8).base64EncodedString(),
                ],
            ],
        ]
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                NoctwebWebsiteBundle.self,
                from: JSONSerialization.data(withJSONObject: unsafeBundle)
            )
        )

        let openDecision = Data(
            """
            {"directive":"open","authority":"visitor","federationMode":"solo"}
            """.utf8
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                RoutingDecision.self,
                from: openDecision
            )
        )
    }

    func testAccessDescriptorExactRoundTripAndUnknownFieldRejection()
        throws
    {
        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        let descriptor = try NoctwebAccessDescriptor(
            navigationURL: environment.welcomeURL,
            routingTrustDomainID: environment.profile
                .routingTrustDomainID,
            bootstrapHints: environment.profile.bootstrapEndpoints
        )
        let encoded = try descriptor.encodedJSON()
        XCTAssertEqual(
            try NoctwebAccessDescriptor.decodeExactJSON(encoded),
            descriptor
        )

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["account"] = "forbidden"
        let unknown = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try NoctwebAccessDescriptor.decodeExactJSON(unknown)
        )

        object.removeValue(forKey: "account")
        object["bootstrapHints"] = ["http://example.com/relay"]
        let plaintextRemote = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(
            try NoctwebAccessDescriptor.decodeExactJSON(plaintextRemote)
        )
    }

    func testRouteAuthorityUsesFirstNonOpenDirective() {
        let federation = RoutingPolicyResolver.resolve(
            federationMode: .curated,
            federation: .passthrough,
            hostOperator: .direct,
            publisher: .direct,
            visitor: .direct
        )
        XCTAssertEqual(federation.directive, .passthrough)
        XCTAssertEqual(federation.authority, .federation)

        let publisher = RoutingPolicyResolver.resolve(
            federationMode: .manual,
            federation: .open,
            hostOperator: .open,
            publisher: .passthrough,
            visitor: .direct
        )
        XCTAssertEqual(publisher.directive, .passthrough)
        XCTAssertEqual(publisher.authority, .publisher)

        let fallback = RoutingPolicyResolver.resolve(
            federationMode: .solo,
            federation: .open,
            hostOperator: .open,
            publisher: .open,
            visitor: .open
        )
        XCTAssertEqual(fallback.directive, .direct)
        XCTAssertEqual(fallback.authority, .defaultDirect)
    }

    func testWebsiteBundleRejectsTraversalDuplicatesAndMissingEntry()
        throws
    {
        let index = NoctwebWebsiteFile(
            path: "index.html",
            mediaType: "text/html",
            bytes: Data("ok".utf8)
        )
        let bundle = try NoctwebWebsiteBundle(
            entryPath: "index.html",
            files: [index]
        )
        XCTAssertEqual(bundle.resource(for: "/")?.bytes, index.bytes)
        XCTAssertEqual(bundle.resource(for: "/dashboard")?.bytes, index.bytes)

        XCTAssertThrowsError(
            try NoctwebWebsiteBundle(
                entryPath: "../index.html",
                files: [index]
            )
        )
        XCTAssertThrowsError(
            try NoctwebWebsiteBundle(
                entryPath: "index.html",
                files: [index, index]
            )
        )
        XCTAssertThrowsError(
            try NoctwebWebsiteBundle(
                entryPath: "missing.html",
                files: [index]
            )
        )
    }

    func testDeterministicFixtureVerifiesBeforeReturningSite() async throws {
        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        let site = try await environment.resolver.resolve(
            environment.welcomeURL,
            profile: environment.profile,
            visitorDirective: .open
        )
        XCTAssertEqual(site.state, .fixtureVerified)
        XCTAssertEqual(site.title, "Welcome to Noctweb")
        XCTAssertTrue(site.evidence.publisherID.hasPrefix("nwpub1_"))
        XCTAssertEqual(site.evidence.route.directive, .direct)
        XCTAssertEqual(site.evidence.route.authority, .defaultDirect)
        XCTAssertNotNil(site.bundle.file(at: "index.html"))
    }

    func testAccessDescriptorExpectedPublisherFailsClosed() async throws {
        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        let descriptor = try NoctwebAccessDescriptor(
            navigationURL: environment.welcomeURL,
            routingTrustDomainID: environment.profile.routingTrustDomainID,
            expectedPublisherID: "nwpub1_\(String(repeating: "0", count: 64))"
        )

        do {
            _ = try await environment.resolver.resolve(
                descriptor,
                profile: environment.profile
            )
            XCTFail("mismatched publisher constraint unexpectedly resolved")
        } catch let error as NoctwebBrowserError {
            guard case .verificationFailed = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testFixtureFailsClosedUnderBundleTampering() async throws {
        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        let original = try await environment.resolver.resolve(
            environment.welcomeURL,
            profile: environment.profile,
            visitorDirective: .open
        )
        let alteredBundle = try NoctwebWebsiteBundle(
            entryPath: "index.html",
            files: [
                NoctwebWebsiteFile(
                    path: "index.html",
                    mediaType: "text/html",
                    bytes: Data("tampered".utf8)
                ),
            ]
        )
        let record = SignedNoctwebFixtureRecord(
            baseAddress: environment.welcomeURL.baseAddress,
            title: original.title,
            routingTrustDomainID: original.evidence
                .routingTrustDomainID,
            consensusProfileID: original.evidence.consensusProfileID,
            consensusVerificationKey: environment.profile.verificationKey,
            epoch: original.evidence.epoch,
            publisherPublicKey: Data(repeating: 2, count: 32),
            publisherID: original.evidence.publisherID,
            objectID: original.evidence.objectID,
            headID: original.evidence.headID,
            hostOperatorDirective: .open,
            publisherDirective: .open,
            bundle: alteredBundle,
            signature: Data(repeating: 0, count: 64)
        )
        let resolver = try DeterministicNoctwebResolver(records: [record])
        do {
            _ = try await resolver.resolve(
                environment.welcomeURL,
                profile: environment.profile,
                visitorDirective: .open
            )
            XCTFail("tampered fixture unexpectedly resolved")
        } catch let error as NoctwebBrowserError {
            guard case .verificationFailed = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testFixtureTitleIsCoveredByPublisherSignature() async throws {
        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        let bundle = try NoctwebWebsiteBundle(
            entryPath: "index.html",
            files: [
                NoctwebWebsiteFile(
                    path: "index.html",
                    mediaType: "text/html",
                    bytes: Data("signed".utf8)
                ),
            ]
        )
        let privateKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: Data(
                SHA256.hash(data: Data("title-test-key".utf8))
            )
        )
        let publicKey = privateKey.publicKey.rawRepresentation
        let publisherID = DeterministicNoctwebResolver.publisherID(
            for: publicKey
        )
        let objectID = DeterministicNoctwebResolver.hexDigest(
            try bundle.canonicalBytes()
        )
        let transcript = DeterministicNoctwebResolver.publisherTranscript(
            baseAddress: environment.welcomeURL.baseAddress,
            title: "Signed title",
            routingTrustDomainID: environment.profile.routingTrustDomainID,
            consensusProfileID: environment.profile.consensusProfileID,
            epoch: 1,
            publisherID: publisherID,
            objectID: objectID,
            hostOperatorDirective: .open,
            publisherDirective: .open
        )
        let signature = try privateKey.signature(for: transcript)
        let record = SignedNoctwebFixtureRecord(
            baseAddress: environment.welcomeURL.baseAddress,
            title: "Tampered title",
            routingTrustDomainID: environment.profile.routingTrustDomainID,
            consensusProfileID: environment.profile.consensusProfileID,
            consensusVerificationKey: environment.profile.verificationKey,
            epoch: 1,
            publisherPublicKey: publicKey,
            publisherID: publisherID,
            objectID: objectID,
            headID: DeterministicNoctwebResolver.headID(
                transcript: transcript,
                signature: signature
            ),
            hostOperatorDirective: .open,
            publisherDirective: .open,
            bundle: bundle,
            signature: signature
        )
        let resolver = try DeterministicNoctwebResolver(records: [record])

        await XCTAssertThrowsErrorAsync {
            _ = try await resolver.resolve(
                environment.welcomeURL,
                profile: environment.profile,
                visitorDirective: .open
            )
        }
    }

    func testSessionRetainsTrustDomainInHistoryAndBookmarks()
        async throws
    {
        let environment = try DeterministicNoctwebResolver
            .developmentEnvironment()
        let site = try await environment.resolver.resolve(
            environment.welcomeURL,
            profile: environment.profile,
            visitorDirective: .open
        )
        var session = try NoctwebBrowserSession(
            profiles: [environment.profile],
            selectedProfileID: environment.profile.id,
            initialAddress: environment.welcomeURL.canonicalString
        )
        session.recordVisit(site)
        session.toggleBookmark(site)
        XCTAssertEqual(
            session.history.first?.routingTrustDomainID,
            environment.profile.routingTrustDomainID
        )
        XCTAssertEqual(
            session.bookmarks.first?.routingTrustDomainID,
            environment.profile.routingTrustDomainID
        )
        let secondTab = try session.addTab()
        XCTAssertEqual(session.tabs.count, 2)
        session.closeTab(id: secondTab)
        XCTAssertEqual(session.tabs.count, 1)

        let bookmarkID = try XCTUnwrap(session.bookmarks.first?.id)
        let historyID = try XCTUnwrap(session.history.first?.id)
        session.removeBookmark(id: bookmarkID)
        session.removeHistoryEntry(id: historyID)
        XCTAssertTrue(session.bookmarks.isEmpty)
        XCTAssertTrue(session.history.isEmpty)

        let foreignEvidence = NoctwebVerificationEvidence(
            publisherID: site.evidence.publisherID,
            routingTrustDomainID:
                "sha256:\(String(repeating: "f", count: 64))",
            consensusProfileID: site.evidence.consensusProfileID,
            epoch: site.evidence.epoch,
            headID: site.evidence.headID,
            objectID: site.evidence.objectID,
            route: site.evidence.route,
            verifiedAt: site.evidence.verifiedAt
        )
        let foreignSite = VerifiedNoctwebSite(
            navigationURL: site.navigationURL,
            title: site.title,
            bundle: site.bundle,
            state: site.state,
            evidence: foreignEvidence
        )
        session.recordVisit(foreignSite)
        session.toggleBookmark(foreignSite)
        XCTAssertTrue(session.bookmarks.isEmpty)
        XCTAssertTrue(session.history.isEmpty)

        let capabilityLikeURL = try NoctwebNavigationURL(
            parsing: "noct://welcome.local-dev/private?cap=secret#fragment"
        )
        let capabilityLikeSite = VerifiedNoctwebSite(
            navigationURL: capabilityLikeURL,
            title: site.title,
            bundle: site.bundle,
            state: site.state,
            evidence: site.evidence
        )
        session.recordVisit(capabilityLikeSite)
        session.toggleBookmark(capabilityLikeSite)
        XCTAssertTrue(session.bookmarks.isEmpty)
        XCTAssertTrue(session.history.isEmpty)
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
