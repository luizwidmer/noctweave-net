import Foundation
import NoctwebBrowserCore
import NoctwebLabCore

/// Resolves deterministic built-in fixtures first, then real relay-hosted
/// publications recorded by Noctweb Lab. A relay receipt proves bounded
/// storage only, so Lab results are always labelled as hosted previews.
actor DevelopmentNoctwebResolver: NoctwebResolving {
    private static let maximumWorkspaceBytes = 32 * 1_024 * 1_024
    private static let maximumWorkspaceCount = 32
    private static let maximumSiteCount = 256

    private let fixtureResolver: DeterministicNoctwebResolver
    private let federationResolver = FederatedNoctwebResolver()
    private let labWorkspaceURL: URL

    init(
        fixtureResolver: DeterministicNoctwebResolver,
        labWorkspaceURL: URL? = nil
    ) {
        self.fixtureResolver = fixtureResolver
        self.labWorkspaceURL =
            labWorkspaceURL ?? Self.defaultLabWorkspaceURL()
    }

    func resolve(
        _ navigationURL: NoctwebNavigationURL,
        profile: NoctwebNetworkProfile,
        visitorDirective: NoctwebBrowserCore.RouteDirective
    ) async throws -> VerifiedNoctwebSite {
        do {
            return try await fixtureResolver.resolve(
                navigationURL,
                profile: profile,
                visitorDirective: visitorDirective
            )
        } catch NoctwebBrowserError.unresolvedName {
            do {
                return try await federationResolver.resolve(
                    navigationURL,
                    profile: profile,
                    visitorDirective: visitorDirective
                )
            } catch NoctwebBrowserError.unresolvedName {
                return try await resolveHostedLabPublication(
                    navigationURL,
                    profile: profile,
                    visitorDirective: visitorDirective
                )
            }
        }
    }

    private func resolveHostedLabPublication(
        _ navigationURL: NoctwebNavigationURL,
        profile: NoctwebNetworkProfile,
        visitorDirective: NoctwebBrowserCore.RouteDirective
    ) async throws -> VerifiedNoctwebSite {
        guard profile.id == "local-development" else {
            throw NoctwebBrowserError.unresolvedName(
                navigationURL.baseAddress
            )
        }
        let record = try loadSiteRecord(
            address: navigationURL.baseAddress
        )
        guard let endpoint = record.hostRelayEndpoint,
              let hostObjectID = record.hostObjectID else {
            throw NoctwebBrowserError.unresolvedName(
                navigationURL.baseAddress
            )
        }

        let client = try NoctwebHostRelayClient(endpoint: endpoint)
        let hosted: NoctwebHostedObject
        do {
            hosted = try await client.fetch(objectID: hostObjectID)
        } catch {
            throw NoctwebBrowserError.verificationFailed(
                "the host relay did not return a valid signed storage object"
            )
        }
        let publication: HostedCapsuleEnvelope
        do {
            publication = try CanonicalJSON.decode(
                HostedCapsuleEnvelope.self,
                from: hosted.payload
            ).verified()
        } catch {
            throw NoctwebBrowserError.verificationFailed(
                "the relay-hosted Lab capsule failed publisher verification"
            )
        }
        guard publication.object.address == navigationURL.baseAddress,
              publication.object.relayNamespaceID == record.relayNamespaceID,
              let sourceBundle = publication.object.bundle else {
            throw NoctwebBrowserError.verificationFailed(
                "the hosted capsule is not bound to the requested address"
            )
        }

        let bundle = try NoctwebWebsiteBundle(
            entryPath: sourceBundle.entryPath,
            files: sourceBundle.files.map {
                NoctwebWebsiteFile(
                    path: $0.path,
                    mediaType: $0.mediaType,
                    bytes: $0.bytes
                )
            }
        )
        let publisherDirective = browserDirective(
            for: publication.object.routeDirective ?? .open
        )
        let route = NoctwebBrowserCore.RoutingPolicyResolver.resolve(
            federationMode: profile.federationMode,
            federation: profile.federationDirective,
            hostOperator: .open,
            publisher: publisherDirective,
            visitor: visitorDirective
        )
        guard route.directive == .direct else {
            throw NoctwebBrowserError.verificationFailed(
                "this hosted preview requires a passthrough adapter that is not configured"
            )
        }

        return VerifiedNoctwebSite(
            navigationURL: navigationURL,
            title: publication.object.title,
            bundle: bundle,
            state: .hostedPreview,
            evidence: NoctwebVerificationEvidence(
                publisherID: publication.object.publisherID,
                routingTrustDomainID: profile.routingTrustDomainID,
                consensusProfileID: "none-hosted-preview",
                epoch: 0,
                headID: publication.headID,
                objectID: publication.head.claims.objectID,
                route: route,
                verifiedAt: Date()
            )
        )
    }

    private func loadSiteRecord(address: String) throws -> LabSiteRecord {
        let data: Data
        do {
            data = try NoctwebSecureFileIO.read(
                from: labWorkspaceURL,
                maximumBytes: Self.maximumWorkspaceBytes,
                requirePrivateOwner: true
            )
        } catch {
            throw NoctwebBrowserError.unresolvedName(address)
        }
        let workspaces = try JSONDecoder().decode(
            [LabWorkspaceRecord].self,
            from: data
        )
        guard workspaces.count <= Self.maximumWorkspaceCount else {
            throw NoctwebBrowserError.verificationFailed(
                "the local Lab workspace exceeds its profile bounds"
            )
        }
        let sites = workspaces.flatMap(\.sites)
        guard sites.count <= Self.maximumSiteCount else {
            throw NoctwebBrowserError.verificationFailed(
                "the local Lab site catalog exceeds its profile bounds"
            )
        }
        guard let site = sites.first(where: { $0.address == address }) else {
            throw NoctwebBrowserError.unresolvedName(address)
        }
        return site
    }

    private func browserDirective(
        for directive: NoctwebLabCore.RouteDirective
    ) -> NoctwebBrowserCore.RouteDirective {
        switch directive {
        case .open: .open
        case .direct: .direct
        case .passthrough: .passthrough
        }
    }

    private static func defaultLabWorkspaceURL() -> URL {
        let support = try! FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return support
            .appendingPathComponent(
                "Noctweave/Noctweb Lab",
                isDirectory: true
            )
            .appendingPathComponent("product-workspaces-v1.json")
    }
}

private struct LabWorkspaceRecord: Decodable {
    let sites: [LabSiteRecord]
}

private struct LabSiteRecord: Decodable {
    let address: String
    let relayNamespaceID: String?
    let hostRelayEndpoint: String?
    let hostObjectID: String?
}
