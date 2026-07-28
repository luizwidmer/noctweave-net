import Foundation
import NoctwebBrowserCore
import NoctwebLabCore

/// Extends the built-in development fixture with publications created by the
/// native Lab. This adapter never runs for another network profile and labels
/// every Lab result as fixture-verified rather than production-finalized.
actor DevelopmentNoctwebResolver: NoctwebResolving {
    private static let maximumWorkspaceBytes = 32 * 1_024 * 1_024
    private static let maximumWorkspaceCount = 32
    private static let maximumSiteCount = 256

    private let fixtureResolver: DeterministicNoctwebResolver
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
            return try await resolveLabPublication(
                navigationURL,
                profile: profile,
                visitorDirective: visitorDirective
            )
        }
    }

    private func resolveLabPublication(
        _ navigationURL: NoctwebNavigationURL,
        profile: NoctwebNetworkProfile,
        visitorDirective: NoctwebBrowserCore.RouteDirective
    ) async throws -> VerifiedNoctwebSite {
        guard profile.id == "local-development" else {
            throw NoctwebBrowserError.unresolvedName(
                navigationURL.baseAddress
            )
        }

        let publication = try await loadPublication(
            address: navigationURL.baseAddress
        )
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore(),
            consensusQuorum: publication.finality.quorum
        )
        try await engine.restore(publication)
        let resolved = try await engine.resolve(
            address: publication.object.address,
            preference: labPreference(for: visitorDirective)
        )

        guard let sourceBundle = resolved.object.bundle else {
            throw NoctwebBrowserError.verificationFailed(
                "the local Lab publication has no website bundle"
            )
        }
        let files = sourceBundle.files.map {
            NoctwebWebsiteFile(
                path: $0.path,
                mediaType: $0.mediaType,
                bytes: $0.bytes
            )
        }
        let bundle = try NoctwebWebsiteBundle(
            entryPath: sourceBundle.entryPath,
            files: files
        )
        let publisherDirective = browserDirective(
            for: resolved.object.routeDirective ?? .open
        )
        let route = NoctwebBrowserCore.RoutingPolicyResolver.resolve(
            federationMode: profile.federationMode,
            federation: profile.federationDirective,
            hostOperator: .open,
            publisher: publisherDirective,
            visitor: visitorDirective
        )

        return VerifiedNoctwebSite(
            navigationURL: navigationURL,
            title: resolved.object.title,
            bundle: bundle,
            state: .fixtureVerified,
            evidence: NoctwebVerificationEvidence(
                publisherID: resolved.object.publisherID,
                routingTrustDomainID: profile.routingTrustDomainID,
                consensusProfileID: profile.consensusProfileID,
                epoch: 1,
                headID: resolved.headID,
                objectID: resolved.evidence.integrity.computedObjectID,
                route: route,
                verifiedAt: Date()
            )
        )
    }

    private func loadPublication(address: String) async throws -> PublishedCapsule {
        if let publication = try loadPublicationFromWorkspace(address: address) {
            return publication
        }
        if let publication = try await loadPublicationFromBridge(address: address) {
            return publication
        }
        throw NoctwebBrowserError.unresolvedName(address)
    }

    private func loadPublicationFromWorkspace(
        address: String
    ) throws -> PublishedCapsule? {
        guard FileManager.default.fileExists(atPath: labWorkspaceURL.path) else {
            return nil
        }
        let values: URLResourceValues
        do {
            values = try labWorkspaceURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            )
        } catch CocoaError.fileNoSuchFile {
            return nil
        } catch CocoaError.fileReadNoPermission {
            return nil
        }
        guard
            values.isRegularFile == true,
            let fileSize = values.fileSize,
            (1...Self.maximumWorkspaceBytes).contains(fileSize)
        else {
            throw NoctwebBrowserError.unresolvedName(address)
        }

        let data = try Data(
            contentsOf: labWorkspaceURL,
            options: [.mappedIfSafe]
        )
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
        guard
            let envelope = sites.first(where: { $0.address == address })?
                .publishedEnvelope
        else {
            return nil
        }

        return try decodePublication(envelope)
    }

    private func loadPublicationFromBridge(
        address: String
    ) async throws -> PublishedCapsule? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = 9_477
        components.path = "/v1/publication"
        components.queryItems = [URLQueryItem(name: "address", value: address)]
        guard let url = components.url else {
            throw NoctwebBrowserError.verificationFailed(
                "the local Lab bridge request is invalid"
            )
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/vnd.noctweave.noctweb-capsule", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 1.5
        configuration.timeoutIntervalForResource = 2
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return nil
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NoctwebBrowserError.verificationFailed(
                "the local Lab bridge returned a non-HTTP response"
            )
        }
        if httpResponse.statusCode == 404 {
            return nil
        }
        guard
            httpResponse.statusCode == 200,
            data.count <= Self.maximumWorkspaceBytes,
            httpResponse.value(forHTTPHeaderField: "Content-Type")?
                .lowercased()
                .hasPrefix("application/vnd.noctweave.noctweb-capsule") == true
        else {
            throw NoctwebBrowserError.verificationFailed(
                "the local Lab bridge response is invalid"
            )
        }
        return try decodePublication(data)
    }

    private func decodePublication(_ envelope: Data) throws -> PublishedCapsule {
        do {
            return try CanonicalJSON.decode(
                PublishedCapsule.self,
                from: envelope
            )
        } catch {
            throw NoctwebBrowserError.verificationFailed(
                "the local Lab publication envelope is invalid"
            )
        }
    }

    private func labPreference(
        for directive: NoctwebBrowserCore.RouteDirective
    ) -> NoctwebLabCore.LabRoute {
        switch directive {
        case .open: .automatic
        case .direct: .direct
        case .passthrough: .passthrough
        }
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
    let publishedEnvelope: Data?
}
