import CryptoKit
import Foundation

public protocol NoctwebResolving: Sendable {
    func resolve(
        _ navigationURL: NoctwebNavigationURL,
        profile: NoctwebNetworkProfile,
        visitorDirective: RouteDirective
    ) async throws -> VerifiedNoctwebSite

    func resolve(
        _ descriptor: NoctwebAccessDescriptor,
        profile: NoctwebNetworkProfile,
        visitorDirective: RouteDirective
    ) async throws -> VerifiedNoctwebSite
}

public extension NoctwebResolving {
    /// Safe default for resolvers that do not perform network discovery.
    ///
    /// Production network adapters should override this requirement so they
    /// can validate bootstrap IPs before connecting and enforce a publisher
    /// pin before downloading publication objects. Hints are never authority.
    func resolve(
        _ descriptor: NoctwebAccessDescriptor,
        profile: NoctwebNetworkProfile,
        visitorDirective: RouteDirective
    ) async throws -> VerifiedNoctwebSite {
        guard descriptor.routingTrustDomainID == profile.routingTrustDomainID else {
            throw NoctwebBrowserError.verificationFailed(
                "the access descriptor targets a different trust domain"
            )
        }
        let site = try await resolve(
            descriptor.navigationURL,
            profile: profile,
            visitorDirective: visitorDirective
        )
        if let expected = descriptor.expectedPublisherID,
           expected != site.evidence.publisherID {
            throw NoctwebBrowserError.verificationFailed(
                "the resolved publisher does not match the access descriptor"
            )
        }
        return site
    }

    func resolve(
        _ descriptor: NoctwebAccessDescriptor,
        profile: NoctwebNetworkProfile
    ) async throws -> VerifiedNoctwebSite {
        try await resolve(
            descriptor,
            profile: profile,
            visitorDirective: profile.defaultVisitorDirective
        )
    }
}

public struct SignedNoctwebFixtureRecord: Equatable, Sendable {
    public let baseAddress: String
    public let title: String
    public let routingTrustDomainID: String
    public let consensusProfileID: String
    public let consensusVerificationKey: Data
    public let epoch: UInt64
    public let publisherPublicKey: Data
    public let publisherID: String
    public let objectID: String
    public let headID: String
    /// Fixture-only input. Production resolvers must authenticate host policy
    /// independently rather than accepting publisher-asserted host authority.
    public let hostOperatorDirective: RouteDirective
    public let publisherDirective: RouteDirective
    public let bundle: NoctwebWebsiteBundle
    public let signature: Data

    public init(
        baseAddress: String,
        title: String,
        routingTrustDomainID: String,
        consensusProfileID: String,
        consensusVerificationKey: Data,
        epoch: UInt64,
        publisherPublicKey: Data,
        publisherID: String,
        objectID: String,
        headID: String,
        hostOperatorDirective: RouteDirective,
        publisherDirective: RouteDirective,
        bundle: NoctwebWebsiteBundle,
        signature: Data
    ) {
        self.baseAddress = baseAddress
        self.title = title
        self.routingTrustDomainID = routingTrustDomainID
        self.consensusProfileID = consensusProfileID
        self.consensusVerificationKey = consensusVerificationKey
        self.epoch = epoch
        self.publisherPublicKey = publisherPublicKey
        self.publisherID = publisherID
        self.objectID = objectID
        self.headID = headID
        self.hostOperatorDirective = hostOperatorDirective
        self.publisherDirective = publisherDirective
        self.bundle = bundle
        self.signature = signature
    }
}

public actor DeterministicNoctwebResolver: NoctwebResolving {
    public static let welcomeURLString = "noct://welcome.local-dev/"

    private let recordsByAddress: [String: SignedNoctwebFixtureRecord]

    public init(records: [SignedNoctwebFixtureRecord]) throws {
        guard
            !records.isEmpty,
            records.count <= 256,
            Set(records.map(\.baseAddress)).count == records.count
        else {
            throw NoctwebBrowserError.verificationFailed(
                "fixture records must be non-empty, bounded, and unique"
            )
        }
        recordsByAddress = Dictionary(
            uniqueKeysWithValues: records.map { ($0.baseAddress, $0) }
        )
    }

    public func resolve(
        _ navigationURL: NoctwebNavigationURL,
        profile: NoctwebNetworkProfile,
        visitorDirective: RouteDirective
    ) async throws -> VerifiedNoctwebSite {
        guard let record = recordsByAddress[navigationURL.baseAddress] else {
            throw NoctwebBrowserError.unresolvedName(navigationURL.baseAddress)
        }
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !title.isEmpty,
            title == record.title,
            title.utf8.count <= 160,
            !title.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
        else {
            throw NoctwebBrowserError.verificationFailed(
                "the publication title is invalid"
            )
        }
        guard
            record.routingTrustDomainID == profile.routingTrustDomainID,
            record.consensusProfileID == profile.consensusProfileID,
            record.consensusVerificationKey == profile.verificationKey,
            profile.supports(epoch: record.epoch)
        else {
            throw NoctwebBrowserError.verificationFailed(
                "the fixture is not bound to the selected network profile"
            )
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(
                rawRepresentation: record.publisherPublicKey
            )
        } catch {
            throw NoctwebBrowserError.verificationFailed(
                "the publisher key is invalid"
            )
        }
        guard
            Self.publisherID(for: record.publisherPublicKey) == record.publisherID
        else {
            throw NoctwebBrowserError.verificationFailed(
                "the publisher identifier does not match its key"
            )
        }
        let bundleBytes = try record.bundle.canonicalBytes()
        guard Self.hexDigest(bundleBytes) == record.objectID else {
            throw NoctwebBrowserError.verificationFailed(
                "the website object digest does not match"
            )
        }
        let transcript = Self.publisherTranscript(
            baseAddress: record.baseAddress,
            title: title,
            routingTrustDomainID: record.routingTrustDomainID,
            consensusProfileID: record.consensusProfileID,
            epoch: record.epoch,
            publisherID: record.publisherID,
            objectID: record.objectID,
            hostOperatorDirective: record.hostOperatorDirective,
            publisherDirective: record.publisherDirective
        )
        guard publicKey.isValidSignature(record.signature, for: transcript) else {
            throw NoctwebBrowserError.verificationFailed(
                "the publisher signature is invalid"
            )
        }
        guard
            Self.headID(transcript: transcript, signature: record.signature) ==
                record.headID
        else {
            throw NoctwebBrowserError.verificationFailed(
                "the publisher head identifier does not match"
            )
        }
        let route = RoutingPolicyResolver.resolve(
            federationMode: profile.federationMode,
            federation: profile.federationDirective,
            hostOperator: record.hostOperatorDirective,
            publisher: record.publisherDirective,
            visitor: visitorDirective
        )
        return VerifiedNoctwebSite(
            navigationURL: navigationURL,
            title: title,
            bundle: record.bundle,
            state: .fixtureVerified,
            evidence: NoctwebVerificationEvidence(
                publisherID: record.publisherID,
                routingTrustDomainID: record.routingTrustDomainID,
                consensusProfileID: record.consensusProfileID,
                epoch: record.epoch,
                headID: record.headID,
                objectID: record.objectID,
                route: route,
                verifiedAt: Date()
            )
        )
    }

    public static func developmentEnvironment() throws -> (
        profile: NoctwebNetworkProfile,
        resolver: DeterministicNoctwebResolver,
        welcomeURL: NoctwebNavigationURL
    ) {
        let trustSeed = Data(
            "org.noctweave.noctweb/browser-development-trust/v1".utf8
        )
        let trustKey = Data(SHA256.hash(data: trustSeed))
        let trustDomainID = "sha256:\(hexDigest(trustKey))"
        let profile = try NoctwebNetworkProfile(
            id: "local-development",
            displayName: "Local development",
            routingTrustDomainID: trustDomainID,
            consensusProfileID: "noctweb.fixture.v1",
            verificationKey: trustKey,
            bootstrapEndpoints: [
                URL(string: "http://127.0.0.1:19340/relay")!,
            ],
            supportedEpochs: [1],
            federationMode: .solo,
            federationDirective: .open,
            defaultVisitorDirective: .open
        )
        let url = try NoctwebNavigationURL(parsing: welcomeURLString)
        let bundle = try NoctwebWebsiteBundle(
            entryPath: "index.html",
            files: [
                NoctwebWebsiteFile(
                    path: "app.js",
                    mediaType: "text/javascript; charset=utf-8",
                    bytes: Data(
                        """
                        document.documentElement.dataset.noctwebReady = "true";
                        document.querySelector("#spa-route")?.addEventListener(
                          "click",
                          () => history.pushState(
                            { source: "fixture" },
                            "",
                            "/app/dashboard?mode=fixture#ready"
                          )
                        );
                        """.utf8
                    )
                ),
                NoctwebWebsiteFile(
                    path: "index.html",
                    mediaType: "text/html; charset=utf-8",
                    bytes: Data(
                        """
                        <!doctype html>
                        <html lang="en">
                        <head>
                          <meta charset="utf-8">
                          <meta name="viewport" content="width=device-width,initial-scale=1">
                          <link rel="stylesheet" href="/styles.css">
                          <title>Welcome to Noctweb</title>
                        </head>
                        <body>
                          <main>
                            <p class="eyebrow">NOCTWEB BROWSER</p>
                            <h1>A web whose identity belongs to its publishers.</h1>
                            <p class="lede">This signed fixture passed the same resolver, route-policy, digest, publisher-key, and isolated-origin boundary that production profiles will use.</p>
                            <section>
                              <strong>Verified locally</strong>
                              <span>No Chromium. No remote application shell. No relay-owned identity.</span>
                            </section>
                            <button id="spa-route" type="button">Test app navigation</button>
                          </main>
                          <script src="/app.js"></script>
                        </body>
                        </html>
                        """.utf8
                    )
                ),
                NoctwebWebsiteFile(
                    path: "styles.css",
                    mediaType: "text/css; charset=utf-8",
                    bytes: Data(
                        """
                        :root { color-scheme: light dark; --violet: #674dd9; --blue: #397ccf; --teal: #168f83; --canvas: #f5f7fc; --ink: #151827; --muted: #62697a; --surface: rgba(255,255,255,.82); font: 16px/1.6 -apple-system, BlinkMacSystemFont, sans-serif; background: var(--canvas); color: var(--ink); }
                        * { box-sizing: border-box; }
                        body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 48px; background: radial-gradient(circle at 20% 0%, #7b61ff35, transparent 38rem), var(--canvas); }
                        main { width: min(780px, 100%); }
                        .eyebrow { color: var(--violet); font-size: 12px; font-weight: 800; letter-spacing: .2em; }
                        h1 { margin: 14px 0 20px; max-width: 760px; font-size: clamp(42px, 8vw, 82px); line-height: .98; letter-spacing: -.055em; }
                        .lede { max-width: 660px; color: var(--muted); font-size: 20px; }
                        section { margin-top: 42px; padding: 18px 20px; display: grid; gap: 3px; border: 1px solid #15182722; border-radius: 14px; background: var(--surface); }
                        section strong { color: var(--blue); }
                        section span { color: var(--muted); }
                        button { margin-top: 20px; padding: 10px 14px; border: 1px solid #15182730; border-radius: 9px; background: #ffffff80; color: var(--violet); font: inherit; font-weight: 650; cursor: pointer; }
                        button:hover { background: #ffffffcc; }
                        @media (prefers-color-scheme: dark) {
                          :root { --violet: #7b61ff; --blue: #5b9cfa; --teal: #3dd5c5; --ink: #f3f5fa; --muted: #a8adbd; --canvas: #080b16; --surface: rgba(255,255,255,.07); }
                          body { background: radial-gradient(circle at 20% 0%, #7b61ff35, transparent 38rem), var(--canvas); }
                          section { border-color: #ffffff20; }
                          section strong { color: var(--blue); }
                          button { border-color: #ffffff25; background: #ffffff0c; color: var(--blue); }
                          button:hover { background: #ffffff18; }
                        }
                        """.utf8
                    )
                ),
            ]
        )
        let privateSeed = Data(
            SHA256.hash(
                data: Data(
                    "org.noctweave.noctweb/browser-development-publisher/v1".utf8
                )
            )
        )
        let privateKey = try Curve25519.Signing.PrivateKey(
            rawRepresentation: privateSeed
        )
        let publisherPublicKey = privateKey.publicKey.rawRepresentation
        let publisherID = publisherID(for: publisherPublicKey)
        let objectID = hexDigest(try bundle.canonicalBytes())
        let transcript = publisherTranscript(
            baseAddress: url.baseAddress,
            title: "Welcome to Noctweb",
            routingTrustDomainID: trustDomainID,
            consensusProfileID: profile.consensusProfileID,
            epoch: 1,
            publisherID: publisherID,
            objectID: objectID,
            hostOperatorDirective: .open,
            publisherDirective: .open
        )
        let signature = try privateKey.signature(for: transcript)
        let record = SignedNoctwebFixtureRecord(
            baseAddress: url.baseAddress,
            title: "Welcome to Noctweb",
            routingTrustDomainID: trustDomainID,
            consensusProfileID: profile.consensusProfileID,
            consensusVerificationKey: trustKey,
            epoch: 1,
            publisherPublicKey: publisherPublicKey,
            publisherID: publisherID,
            objectID: objectID,
            headID: headID(transcript: transcript, signature: signature),
            hostOperatorDirective: .open,
            publisherDirective: .open,
            bundle: bundle,
            signature: signature
        )
        return (
            profile,
            try DeterministicNoctwebResolver(records: [record]),
            url
        )
    }

    static func publisherID(for publicKey: Data) -> String {
        var input = Data("org.noctweave.noctweb/publisher-id/v1".utf8)
        input.append(0)
        input.append(publicKey)
        return "nwpub1_\(hexDigest(input))"
    }

    static func headID(transcript: Data, signature: Data) -> String {
        var input = Data("org.noctweave.noctweb/head-id/v1".utf8)
        input.append(0)
        input.append(transcript)
        input.append(signature)
        return "sha256:\(hexDigest(input))"
    }

    static func publisherTranscript(
        baseAddress: String,
        title: String,
        routingTrustDomainID: String,
        consensusProfileID: String,
        epoch: UInt64,
        publisherID: String,
        objectID: String,
        hostOperatorDirective: RouteDirective,
        publisherDirective: RouteDirective
    ) -> Data {
        var result = Data(
            "org.noctweave.noctweb/publisher-head/fixture-v1".utf8
        )
        for value in [
            baseAddress,
            title,
            routingTrustDomainID,
            consensusProfileID,
            publisherID,
            objectID,
            hostOperatorDirective.rawValue,
            publisherDirective.rawValue,
        ] {
            result.append(0)
            result.append(Data(value.utf8))
        }
        result.append(0)
        var bigEndianEpoch = epoch.bigEndian
        withUnsafeBytes(of: &bigEndianEpoch) { result.append(contentsOf: $0) }
        return result
    }

    static func hexDigest(_ data: Data) -> String {
        Data(SHA256.hash(data: data))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
