import CryptoKit
import Foundation
@preconcurrency import NoctweaveCore
import Security

public struct NoctwebHostRelayConfiguration: Codable, Equatable, Sendable {
    public let version: Int
    public let relayNamespaceID: String
    public let relaySuffix: String
    public let usesCustomSuffix: Bool
    public let hostSigningPublicKey: String
    public let hostModule: String
    public let hostModuleVersion: Int
    public let maximumObjectBytes: Int
    public let minimumRetentionSeconds: Int
    public let maximumRetentionSeconds: Int

    public var signingPublicKey: Data? {
        Data(base64Encoded: hostSigningPublicKey)
    }

    public var relayNamespace: RelayNamespace? {
        guard let signingPublicKey else { return nil }
        guard let namespace = try? RelayNamespace(
            publicKey: signingPublicKey,
            operatorSuffix: usesCustomSuffix ? relaySuffix : nil
        ), namespace.suffix == relaySuffix else {
            return nil
        }
        return namespace
    }

    public var isValid: Bool {
        version == 1
            && RelayNamespace.isValidID(relayNamespaceID)
            && relayNamespace?.id == relayNamespaceID
            && hostModule == "nw.net-host"
            && hostModuleVersion == 1
            && (1...1_048_576).contains(maximumObjectBytes)
            && (60...maximumRetentionSeconds).contains(minimumRetentionSeconds)
            && maximumRetentionSeconds <= 2_592_000
    }
}

public struct NoctwebHostingReceipt: Codable, Equatable, Hashable, Sendable {
    public let objectID: String
    public let byteCount: UInt64
    public let storedAt: Date
    public let expiresAt: Date
    public let signingPublicKey: Data
    public let signatureAlgorithm: String
    public let signature: Data

    public func verify(
        expectedObjectID: String,
        expectedByteCount: Int,
        expectedSigningPublicKey: Data,
        maximumRetentionSeconds: Int
    ) throws {
        guard objectID == expectedObjectID,
              byteCount == UInt64(expectedByteCount),
              signingPublicKey == expectedSigningPublicKey,
              signatureAlgorithm == "Ed25519",
              signature.count == 64,
              expiresAt > storedAt,
              expiresAt.timeIntervalSince(storedAt)
                  <= TimeInterval(maximumRetentionSeconds),
              floor(storedAt.timeIntervalSince1970)
                  == storedAt.timeIntervalSince1970,
              floor(expiresAt.timeIntervalSince1970)
                  == expiresAt.timeIntervalSince1970 else {
            throw NoctwebHostRelayError.invalidReceipt
        }
        let publicKey = try Curve25519.Signing.PublicKey(
            rawRepresentation: signingPublicKey
        )
        guard publicKey.isValidSignature(signature, for: signingPayload) else {
            throw NoctwebHostRelayError.invalidReceipt
        }
    }

    private var signingPayload: Data {
        var data = Data("org.noctweave.net/hosting-receipt/v1".utf8)
        data.append(0)
        data.append(Data(objectID.utf8))
        var count = byteCount.bigEndian
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        var stored = UInt64(storedAt.timeIntervalSince1970).bigEndian
        withUnsafeBytes(of: &stored) { data.append(contentsOf: $0) }
        var expires = UInt64(expiresAt.timeIntervalSince1970).bigEndian
        withUnsafeBytes(of: &expires) { data.append(contentsOf: $0) }
        return data
    }
}

public struct NoctwebHostedObject: Codable, Equatable, Sendable {
    public let receipt: NoctwebHostingReceipt
    public let payload: Data
}

public struct NoctwebHostPutResult: Sendable {
    public let receipt: NoctwebHostingReceipt
    public let releaseCapability: Data
}

public struct NoctwebHostNameBindingReceipt:
    Equatable,
    Sendable
{
    public let relayID: String
    public let relaySuffix: String
    public let siteLabel: String
    public let objectID: String
    public let publisherID: String
    public let headID: String?
    public let revision: UInt64
    public let expiresAt: Date
}

public enum NoctwebHostRelayError: LocalizedError, Sendable {
    case invalidEndpoint
    case insecureRemoteEndpoint
    case invalidConfiguration
    case requestFailed(Int)
    case invalidResponse
    case relayRejected(String)
    case invalidReceipt
    case objectTooLarge
    case randomGenerationFailed

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "Enter a valid HTTP or HTTPS relay URL."
        case .insecureRemoteEndpoint:
            "Cleartext HTTP is allowed only for loopback development relays."
        case .invalidConfiguration:
            "The endpoint does not advertise a valid nw.net-host@1 configuration."
        case .requestFailed(let status):
            "The relay HTTP request failed with status \(status)."
        case .invalidResponse:
            "The relay returned an invalid or uncorrelated response."
        case .relayRejected(let message):
            message
        case .invalidReceipt:
            "The relay hosting receipt failed verification."
        case .objectTooLarge:
            "The signed publication exceeds this relay's object limit."
        case .randomGenerationFailed:
            "Secure random generation failed."
        }
    }
}

public actor NoctwebHostRelayClient {
    public let baseURL: URL
    private let relayEndpoint: RelayEndpoint
    private let session: URLSession
    private var cachedConfiguration: NoctwebHostRelayConfiguration?
    private var cachedRelayIdentity: SignedRelayIdentityClaimV1?

    public init(endpoint: String) throws {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty else {
            throw NoctwebHostRelayError.invalidEndpoint
        }
        if scheme == "http", !Self.isLoopback(host) {
            throw NoctwebHostRelayError.insecureRemoteEndpoint
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let baseURL = components.url else {
            throw NoctwebHostRelayError.invalidEndpoint
        }
        self.baseURL = baseURL
        self.relayEndpoint = try RelayEndpointParser.parse(
            baseURL.absoluteString
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    public func discover(force: Bool = false) async throws
        -> NoctwebHostRelayConfiguration
    {
        if !force, let cachedConfiguration {
            return cachedConfiguration
        }
        let url = baseURL.appendingPathComponent("noctweb/config.json")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw NoctwebHostRelayError.requestFailed(
                (response as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
        let configuration = try JSONDecoder().decode(
            NoctwebHostRelayConfiguration.self,
            from: data
        )
        guard configuration.isValid else {
            throw NoctwebHostRelayError.invalidConfiguration
        }
        cachedConfiguration = configuration
        return configuration
    }

    public func put(
        payload: Data,
        ttlSeconds: Int,
        authorization: String
    ) async throws -> NoctwebHostPutResult {
        let configuration = try await discover()
        guard !payload.isEmpty,
              payload.count <= configuration.maximumObjectBytes else {
            throw NoctwebHostRelayError.objectTooLarge
        }
        let ttl = min(
            max(ttlSeconds, configuration.minimumRetentionSeconds),
            configuration.maximumRetentionSeconds
        )
        let releaseCapability = try Self.randomData(count: 32)
        let releaseDigest = Self.releaseCapabilityDigest(releaseCapability)
        let objectID = Self.objectID(for: payload)
        let body = HostPutBody(
            objectID: objectID,
            payload: payload,
            ttlSeconds: ttl,
            releaseCapabilityDigest: releaseDigest,
            idempotencyKey: try Self.randomData(count: 32)
        )
        let response: HostPutResponse = try await send(
            method: "put",
            body: body,
            authorization: authorization
        )
        guard let signingKey = configuration.signingPublicKey else {
            throw NoctwebHostRelayError.invalidConfiguration
        }
        try response.receipt.verify(
            expectedObjectID: objectID,
            expectedByteCount: payload.count,
            expectedSigningPublicKey: signingKey,
            maximumRetentionSeconds: configuration.maximumRetentionSeconds
        )
        return NoctwebHostPutResult(
            receipt: response.receipt,
            releaseCapability: releaseCapability
        )
    }

    /// Atomically publishes the human-facing name after the immutable object
    /// has been retained. The relay signs the resulting mapping with its
    /// persistent ML-DSA identity; this method verifies that identity and the
    /// returned mapping before reporting success.
    public func bindName(
        relaySuffix: String,
        siteLabel: String,
        objectID: String,
        publisherID: String,
        headID: String?,
        revision: UInt64,
        previousObjectID: String?,
        authorization: String
    ) async throws -> NoctwebHostNameBindingReceipt {
        let identity = try await authenticatedRelayIdentity()
        guard let suffix = NoctwebRelaySuffixV1(
            rawValue: relaySuffix.hasPrefix(".")
                ? relaySuffix
                : ".\(relaySuffix)"
        ), identity.claim.noctwebSuffix == suffix else {
            throw NoctwebHostRelayError.invalidConfiguration
        }
        let binding = NoctweaveNetHostNameBindingRequestV1(
            relaySuffix: suffix,
            siteLabel: siteLabel,
            objectID: objectID,
            publisherID: publisherID,
            headID: headID,
            revision: revision,
            previousObjectID: previousObjectID,
            idempotencyKey: try Self.randomData(count: 32)
        )
        guard binding.isStructurallyValid else {
            throw NoctwebHostRelayError.invalidResponse
        }
        let response = try await RelayClient(
            endpoint: relayEndpoint,
            authToken: authorization.isEmpty ? nil : authorization
        ).send(.bindNetHostName(binding))
        guard case .netHostNameResolution(let resolution)? =
            response.successBody,
            try resolution.verifyThrowing(
                expectedRelayIdentity: identity
            ),
            resolution.relaySuffix == suffix,
            resolution.siteLabel == siteLabel,
            resolution.objectID == objectID,
            resolution.publisherID == publisherID,
            resolution.headID == headID,
            resolution.revision == revision else {
            throw NoctwebHostRelayError.invalidResponse
        }
        return NoctwebHostNameBindingReceipt(
            relayID: resolution.relayID.rawValue,
            relaySuffix: resolution.relaySuffix.rawValue,
            siteLabel: resolution.siteLabel,
            objectID: resolution.objectID,
            publisherID: resolution.publisherID,
            headID: resolution.headID,
            revision: resolution.revision,
            expiresAt: resolution.expiresAt
        )
    }

    public func fetch(objectID: String) async throws -> NoctwebHostedObject {
        let configuration = try await discover()
        let response: HostObjectResponse = try await send(
            method: "get",
            body: HostObjectBody(objectID: objectID),
            authorization: nil
        )
        let hosted = response.object
        guard Self.objectID(for: hosted.payload) == objectID,
              let signingKey = configuration.signingPublicKey else {
            throw NoctwebHostRelayError.invalidResponse
        }
        try hosted.receipt.verify(
            expectedObjectID: objectID,
            expectedByteCount: hosted.payload.count,
            expectedSigningPublicKey: signingKey,
            maximumRetentionSeconds: configuration.maximumRetentionSeconds
        )
        return hosted
    }

    public func contains(objectID: String) async throws -> Bool {
        let response: HostPresenceResponse = try await send(
            method: "has",
            body: HostObjectBody(objectID: objectID),
            authorization: nil
        )
        guard response.presence.objectID == objectID else {
            throw NoctwebHostRelayError.invalidResponse
        }
        return response.presence.present
    }

    public func release(
        objectID: String,
        releaseCapability: Data,
        authorization: String
    ) async throws -> Bool {
        guard releaseCapability.count == 32 else {
            throw NoctwebHostRelayError.invalidResponse
        }
        let response: HostReleaseResponse = try await send(
            method: "release",
            body: HostReleaseBody(
                objectID: objectID,
                releaseCapability: releaseCapability
            ),
            authorization: authorization
        )
        guard response.release.objectID == objectID else {
            throw NoctwebHostRelayError.invalidResponse
        }
        return response.release.released
    }

    public static func objectID(for payload: Data) -> String {
        SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func authenticatedRelayIdentity(
        force: Bool = false
    ) async throws -> SignedRelayIdentityClaimV1 {
        if !force, let cachedRelayIdentity,
           (try? cachedRelayIdentity.verifyThrowing()) == true {
            return cachedRelayIdentity
        }
        let response = try await RelayClient(endpoint: relayEndpoint)
            .send(.info())
        guard case .relayInfo(let info)? = response.successBody,
              let identity = info.relayIdentity,
              try identity.verifyThrowing(at: info.advertisedAt),
              info.authenticatedRelayID == identity.claim.relayID,
              info.authenticatedNoctwebSuffix
                == identity.claim.noctwebSuffix,
              info.protocolCapabilities?.supports(
                module: "nw.net-host",
                version: 1
              ) == true else {
            throw NoctwebHostRelayError.invalidConfiguration
        }
        let configuration = try await discover()
        guard identity.claim.noctwebSuffix?.rawValue
            == ".\(configuration.relaySuffix)" else {
            throw NoctwebHostRelayError.invalidConfiguration
        }
        cachedRelayIdentity = identity
        return identity
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        method: String,
        body: RequestBody,
        authorization: String?
    ) async throws -> ResponseBody {
        let requestID = UUID()
        let envelope = HostWireRequest(
            requestID: requestID,
            method: method,
            body: body,
            authToken: authorization?.isEmpty == false ? authorization : nil
        )
        var request = URLRequest(
            url: baseURL.appendingPathComponent("relay")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder().encode(envelope)
        let (data, urlResponse) = try await session.data(for: request)
        guard let http = urlResponse as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw NoctwebHostRelayError.requestFailed(
                (urlResponse as? HTTPURLResponse)?.statusCode ?? 0
            )
        }
        let response = try Self.decoder().decode(
            HostWireResponse<ResponseBody>.self,
            from: data
        )
        guard response.requestID == requestID,
              response.module == "nw.net-host",
              response.version == 1,
              response.method == method else {
            throw NoctwebHostRelayError.invalidResponse
        }
        guard response.status == "success", let body = response.body else {
            throw NoctwebHostRelayError.relayRejected(
                response.error?.message ?? "The relay rejected the request."
            )
        }
        return body
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw NoctwebHostRelayError.randomGenerationFailed
        }
        return Data(bytes)
    }

    private static func releaseCapabilityDigest(_ capability: Data) -> Data {
        var data = Data("org.noctweave.net/host-release/v1".utf8)
        data.append(0)
        data.append(capability)
        return Data(SHA256.hash(data: data))
    }

    private static func isLoopback(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "localhost"
            || normalized == "::1"
            || normalized.hasPrefix("127.")
    }
}

private struct HostWireRequest<Body: Encodable>: Encodable {
    let requestID: UUID
    let method: String
    let body: Body
    let authToken: String?

    enum CodingKeys: String, CodingKey {
        case requestID, module, version, method, body, authToken
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(requestID, forKey: .requestID)
        try values.encode("nw.net-host", forKey: .module)
        try values.encode(1, forKey: .version)
        try values.encode(method, forKey: .method)
        try values.encode(body, forKey: .body)
        if let authToken {
            try values.encode(authToken, forKey: .authToken)
        } else {
            try values.encodeNil(forKey: .authToken)
        }
    }
}

private struct HostWireResponse<Body: Decodable>: Decodable {
    let requestID: UUID
    let module: String
    let version: Int
    let method: String
    let status: String
    let body: Body?
    let error: HostWireError?
}

private struct HostWireError: Decodable {
    let message: String
}

private struct HostPutBody: Encodable {
    let objectID: String
    let payload: Data
    let ttlSeconds: Int
    let releaseCapabilityDigest: Data
    let idempotencyKey: Data
}

private struct HostObjectBody: Codable {
    let objectID: String
}

private struct HostPutResponse: Decodable {
    let receipt: NoctwebHostingReceipt
}

private struct HostObjectResponse: Decodable {
    let object: NoctwebHostedObject
}

private struct HostPresenceResponse: Decodable {
    let presence: HostPresence
}

private struct HostReleaseBody: Encodable {
    let objectID: String
    let releaseCapability: Data
}

private struct HostReleaseResponse: Decodable {
    let release: HostRelease
}

private struct HostRelease: Decodable {
    let objectID: String
    let released: Bool
}

private struct HostPresence: Decodable {
    let objectID: String
    let present: Bool
    let expiresAt: Date?
}
