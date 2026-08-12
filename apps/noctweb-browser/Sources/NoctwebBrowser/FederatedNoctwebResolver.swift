import Foundation
@preconcurrency import NoctweaveCore
import NoctwebBrowserCore
import NoctwebLabCore

/// Resolves `noct://site.suffix/` through an authenticated federation
/// namespace, then asks the selected home relay to retrieve the signed name
/// mapping and immutable hosted object from the destination relay.
actor FederatedNoctwebResolver: NoctwebResolving {
    func resolve(
        _ navigationURL: NoctwebNavigationURL,
        profile: NoctwebNetworkProfile,
        visitorDirective: NoctwebBrowserCore.RouteDirective
    ) async throws -> VerifiedNoctwebSite {
        guard let suffix = NoctwebRelaySuffixV1(
            rawValue: ".\(navigationURL.relaySuffix)"
        ) else {
            throw NoctwebBrowserError.unresolvedName(
                navigationURL.baseAddress
            )
        }
        let homeEndpoints = try profile.bootstrapEndpoints.map(
            relayEndpoint
        )
        guard let homeEndpoint = homeEndpoints.first else {
            throw NoctwebBrowserError.unresolvedName(
                navigationURL.baseAddress
            )
        }

        let namespace = try await resolveNamespace(
            suffix: suffix,
            profile: profile,
            bootstrapEndpoints: homeEndpoints
        )
        let nameRequest = NoctweaveNetHostNameRequestV1(
            relaySuffix: suffix,
            siteLabel: navigationURL.siteLabel
        )
        let resolution = try await resolveName(
            request: nameRequest,
            identity: namespace.identity,
            destination: namespace.endpoint,
            home: homeEndpoint
        )
        let hosted = try await fetchObject(
            objectID: resolution.objectID,
            identity: namespace.identity,
            destination: namespace.endpoint,
            home: homeEndpoint
        )
        let publication: HostedCapsuleEnvelope
        do {
            publication = try CanonicalJSON.decode(
                HostedCapsuleEnvelope.self,
                from: hosted.payload
            ).verified()
        } catch {
            throw NoctwebBrowserError.verificationFailed(
                "the hosted publication failed publisher verification"
            )
        }
        guard publication.object.address == navigationURL.baseAddress,
              publication.object.publisherID == resolution.publisherID,
              publication.headID == resolution.headID,
              publication.object.revision == resolution.revision,
              let sourceBundle = publication.object.bundle else {
            throw NoctwebBrowserError.verificationFailed(
                "the signed name mapping does not match the publication"
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
        let route = NoctwebBrowserCore.RoutingPolicyResolver.resolve(
            federationMode: profile.federationMode,
            federation: profile.federationDirective,
            hostOperator: .open,
            publisher: browserDirective(
                publication.object.routeDirective ?? .open
            ),
            visitor: visitorDirective
        )
        guard route.directive == .direct else {
            throw NoctwebBrowserError.verificationFailed(
                "this publication requires a passthrough adapter that is not configured"
            )
        }

        return VerifiedNoctwebSite(
            navigationURL: navigationURL,
            title: publication.object.title,
            bundle: bundle,
            state: namespace.isConsensusVerified
                ? .finalized
                : .hostedPreview,
            evidence: NoctwebVerificationEvidence(
                publisherID: publication.object.publisherID,
                routingTrustDomainID: profile.routingTrustDomainID,
                consensusProfileID: profile.consensusProfileID,
                epoch: namespace.epoch,
                headID: publication.headID,
                objectID: publication.head.claims.objectID,
                route: route,
                verifiedAt: Date()
            )
        )
    }

    private func resolveNamespace(
        suffix: NoctwebRelaySuffixV1,
        profile: NoctwebNetworkProfile,
        bootstrapEndpoints: [RelayEndpoint]
    ) async throws -> ResolvedNamespace {
        if profile.federationMode == .solo,
           profile.namespaceSigners.count == 1 {
            return try await resolvePinnedSoloNamespace(
                suffix: suffix,
                profile: profile,
                bootstrapEndpoints: bootstrapEndpoints
            )
        }
        if !profile.namespaceSigners.isEmpty {
            return try await resolveConsensusNamespace(
                suffix: suffix,
                profile: profile,
                bootstrapEndpoints: bootstrapEndpoints
            )
        }
        guard profile.id == "local-development",
              bootstrapEndpoints.allSatisfy(isLoopback) else {
            throw NoctwebBrowserError.verificationFailed(
                "this network profile has no trusted namespace signer policy"
            )
        }
        for endpoint in bootstrapEndpoints {
            let response = try await RelayClient(endpoint: endpoint)
                .send(.info())
            guard case .relayInfo(let info)? = response.successBody,
                  let identity = info.relayIdentity,
                  try identity.verifyThrowing(at: info.advertisedAt),
                  identity.claim.noctwebSuffix == suffix,
                  info.protocolCapabilities?.supports(
                    module: "nw.net-host",
                    version: 1
                  ) == true else {
                continue
            }
            return ResolvedNamespace(
                identity: identity,
                endpoint: endpoint,
                epoch: 0,
                isConsensusVerified: false
            )
        }
        throw NoctwebBrowserError.unresolvedName(
            "no authenticated local relay owns \(suffix.rawValue)"
        )
    }

    private func resolvePinnedSoloNamespace(
        suffix: NoctwebRelaySuffixV1,
        profile: NoctwebNetworkProfile,
        bootstrapEndpoints: [RelayEndpoint]
    ) async throws -> ResolvedNamespace {
        guard let signer = profile.namespaceSigners.first,
              let expectedRelayID = RelayIdentityIDV1(
                rawValue: signer.relayID
              ) else {
            throw NoctwebBrowserError.verificationFailed(
                "the selected relay profile has no valid identity pin"
            )
        }
        for endpoint in bootstrapEndpoints {
            do {
                let response = try await RelayClient(endpoint: endpoint)
                    .send(.info())
                guard case .relayInfo(let info)? = response.successBody,
                      let identity = info.relayIdentity,
                      try identity.verifyThrowing(at: info.advertisedAt),
                      identity.claim.relayID == expectedRelayID,
                      identity.claim.signingPublicKey
                        == signer.signingPublicKey,
                      identity.claim.noctwebSuffix == suffix,
                      info.protocolCapabilities?.supports(
                        module: "nw.net-host",
                        version: 1
                      ) == true else {
                    continue
                }
                return ResolvedNamespace(
                    identity: identity,
                    endpoint: preferredHostEndpoint(
                        from: identity.claim.advertisedEndpoints
                    ) ?? endpoint,
                    epoch: UInt64(max(1, identity.claim.sequence)),
                    isConsensusVerified: false
                )
            } catch {
                continue
            }
        }
        throw NoctwebBrowserError.unresolvedName(
            "the selected relay does not own \(suffix.rawValue)"
        )
    }

    private func resolveConsensusNamespace(
        suffix: NoctwebRelaySuffixV1,
        profile: NoctwebNetworkProfile,
        bootstrapEndpoints: [RelayEndpoint]
    ) async throws -> ResolvedNamespace {
        guard let federationMode = NoctweaveCore.FederationMode(
            rawValue: profile.federationMode.rawValue
        ) else {
            throw NoctwebBrowserError.verificationFailed(
                "the federation mode is unsupported"
            )
        }
        let signers = try profile.namespaceSigners.map { signer in
            guard let relayID = RelayIdentityIDV1(
                rawValue: signer.relayID
            ), relayID == RelayIdentityIDV1.derived(
                from: signer.signingPublicKey
            ) else {
                throw NoctwebBrowserError.verificationFailed(
                    "a namespace signer identity does not match its key"
                )
            }
            return NoctwebNamespaceConsensusSignerV1(
                relayID: relayID,
                signingPublicKey: signer.signingPublicKey
            )
        }
        let policy = NoctwebNamespaceConsensusPolicyV1(
            federationMode: federationMode,
            federationName: profile.namespaceFederationName,
            signers: signers,
            threshold: profile.namespaceThreshold
        )
        guard try policy.isStructurallyValidThrowing else {
            throw NoctwebBrowserError.verificationFailed(
                "the namespace consensus policy is invalid"
            )
        }
        let request = RelayRequest.getNoctwebNamespaceSnapshotV1(
            NoctwebNamespaceSnapshotRequestV1(
                federationMode: federationMode,
                federationName: profile.namespaceFederationName
            )
        )
        var candidates: [NoctwebNamespaceSnapshotV1] = []
        for endpoint in bootstrapEndpoints {
            do {
                let response = try await RelayClient(endpoint: endpoint)
                    .send(request)
                if case .noctwebNamespaceSnapshot(let snapshot)? =
                    response.successBody {
                    candidates.append(snapshot)
                }
            } catch {
                continue
            }
        }
        guard let snapshot = try NoctwebNamespaceSnapshotCollectorV1
            .verifiedSnapshot(
                from: candidates,
                policy: policy
            ),
            let record = try snapshot.record(
                for: suffix,
                policy: policy
            ),
            record.status == .active,
            let identity = record.activeIdentityClaim,
            try identity.verifyThrowing(),
            identity.claim.relayID == record.ownerRelayID,
            identity.claim.noctwebSuffix == suffix,
            let endpoint = preferredHostEndpoint(
                from: identity.claim.advertisedEndpoints
            ) else {
            throw NoctwebBrowserError.unresolvedName(
                "the federation has no live owner for \(suffix.rawValue)"
            )
        }
        return ResolvedNamespace(
            identity: identity,
            endpoint: endpoint,
            epoch: UInt64(snapshot.payload.epoch),
            isConsensusVerified: true
        )
    }

    private func resolveName(
        request: NoctweaveNetHostNameRequestV1,
        identity: SignedRelayIdentityClaimV1,
        destination: RelayEndpoint,
        home: RelayEndpoint
    ) async throws -> NoctweaveNetHostNameResolutionV1 {
        let response: RelayResponse
        if sameEndpoint(home, destination) {
            response = try await RelayClient(endpoint: destination).send(
                .resolveNetHostName(request)
            )
            guard case .netHostNameResolution(let resolution)? =
                response.successBody,
                try resolution.verifyThrowing(
                    expectedRelayIdentity: identity
                ) else {
                throw NoctwebBrowserError.verificationFailed(
                    "the destination relay returned an invalid signed name"
                )
            }
            return resolution
        }
        response = try await RelayClient(endpoint: home).send(
            .resolveFederatedNetHostNameV1(
                FederatedNetHostNameReadRequestV1(
                    destinationRelayID: identity.claim.relayID,
                    destination: destination,
                    request: request
                )
            )
        )
        guard case .federatedNetHostNameResolution(let federated)? =
            response.successBody,
            try federated.verifyThrowing(
                expectedRelayID: identity.claim.relayID
            ),
            sameRelayAuthority(
                federated.destinationIdentity,
                as: identity
            ) else {
            throw NoctwebBrowserError.verificationFailed(
                "the home relay returned an unauthenticated name result"
            )
        }
        return federated.resolution
    }

    private func fetchObject(
        objectID: String,
        identity: SignedRelayIdentityClaimV1,
        destination: RelayEndpoint,
        home: RelayEndpoint
    ) async throws -> NoctweaveNetHostFetchResponse {
        let request = NoctweaveNetHostObjectRequest(
            objectID: objectID
        )
        if sameEndpoint(home, destination) {
            let response = try await RelayClient(endpoint: destination)
                .send(.getNetHostObject(request))
            guard case .netHostObject(let object)? = response.successBody,
                  object.isStructurallyValid,
                  identity.claim.hostSigningPublicKey
                    == object.receipt.signingPublicKey else {
                throw NoctwebBrowserError.verificationFailed(
                    "the destination relay returned an invalid hosted object"
                )
            }
            return object
        }
        let response = try await RelayClient(endpoint: home).send(
            .getFederatedNetHostObjectV1(
                FederatedNetHostReadRequestV1(
                    destinationRelayID: identity.claim.relayID,
                    destination: destination,
                    request: request
                )
            )
        )
        guard case .federatedNetHostObject(let federated)? =
            response.successBody,
            try federated.verifyThrowing(
                expectedRelayID: identity.claim.relayID
            ),
            sameRelayAuthority(
                federated.destinationIdentity,
                as: identity
            ) else {
            throw NoctwebBrowserError.verificationFailed(
                "the home relay returned an unauthenticated hosted object"
            )
        }
        return federated.object
    }

    /// Relay identity claims are short-lived, signed advertisements. Their
    /// sequence, issuance window, and endpoint set can advance without changing
    /// the cryptographic authority anchored by the namespace snapshot.
    private func sameRelayAuthority(
        _ live: SignedRelayIdentityClaimV1,
        as anchored: SignedRelayIdentityClaimV1
    ) -> Bool {
        live.claim.relayID == anchored.claim.relayID
            && live.claim.signingPublicKey
                == anchored.claim.signingPublicKey
            && live.claim.hostSigningPublicKey
                == anchored.claim.hostSigningPublicKey
            && live.claim.noctwebSuffix
                == anchored.claim.noctwebSuffix
            && live.claim.federationMode
                == anchored.claim.federationMode
            && live.claim.federationName
                == anchored.claim.federationName
    }

    private func relayEndpoint(_ url: URL) throws -> RelayEndpoint {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            throw NoctwebBrowserError.invalidNetworkProfile(
                "invalid bootstrap endpoint"
            )
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let canonical = components.url else {
            throw NoctwebBrowserError.invalidNetworkProfile(
                "invalid bootstrap endpoint"
            )
        }
        return try RelayEndpointParser.parse(canonical.absoluteString)
    }

    private func preferredHostEndpoint(
        from endpoints: [RelayEndpoint]
    ) -> RelayEndpoint? {
        endpoints.first {
            $0.transport == .http || $0.transport == .websocket
        } ?? endpoints.first
    }

    private func sameEndpoint(
        _ lhs: RelayEndpoint,
        _ rhs: RelayEndpoint
    ) -> Bool {
        lhs.host.caseInsensitiveCompare(rhs.host) == .orderedSame
            && lhs.port == rhs.port
            && lhs.useTLS == rhs.useTLS
            && lhs.transport == rhs.transport
    }

    private func isLoopback(_ endpoint: RelayEndpoint) -> Bool {
        let host = endpoint.host.lowercased()
        if host == "localhost" || host == "::1" {
            return true
        }
        let octets = host.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard octets.count == 4, octets[0] == "127" else {
            return false
        }
        return octets.allSatisfy { component in
            guard let value = UInt8(component), String(value) == component else {
                return false
            }
            return true
        }
    }

    private func browserDirective(
        _ directive: NoctwebLabCore.RouteDirective
    ) -> NoctwebBrowserCore.RouteDirective {
        switch directive {
        case .open: .open
        case .direct: .direct
        case .passthrough: .passthrough
        }
    }
}

private struct ResolvedNamespace {
    let identity: SignedRelayIdentityClaimV1
    let endpoint: RelayEndpoint
    let epoch: UInt64
    let isConsensusVerified: Bool
}
