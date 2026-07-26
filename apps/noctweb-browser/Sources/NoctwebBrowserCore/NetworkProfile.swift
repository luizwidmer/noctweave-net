import Foundation

public struct NoctwebNetworkProfile:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public static let currentVersion = 1
    public static let maximumBootstrapEndpoints = 8
    public static let maximumSupportedEpochs = 16

    public let version: Int
    public let id: String
    public let displayName: String
    public let routingTrustDomainID: String
    public let consensusProfileID: String
    public let verificationKey: Data
    public let bootstrapEndpoints: [URL]
    public let supportedEpochs: [UInt64]
    public let federationMode: FederationMode
    public let federationDirective: RouteDirective
    public let defaultVisitorDirective: RouteDirective

    public init(
        version: Int = Self.currentVersion,
        id: String,
        displayName: String,
        routingTrustDomainID: String,
        consensusProfileID: String,
        verificationKey: Data,
        bootstrapEndpoints: [URL],
        supportedEpochs: [UInt64],
        federationMode: FederationMode,
        federationDirective: RouteDirective,
        defaultVisitorDirective: RouteDirective
    ) throws {
        guard version == Self.currentVersion else {
            throw NoctwebBrowserError.invalidNetworkProfile("unsupported version")
        }
        guard Self.isIdentifier(id, maximum: 64) else {
            throw NoctwebBrowserError.invalidNetworkProfile("invalid profile identifier")
        }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !name.isEmpty,
            name.utf8.count <= 80,
            !name.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
        else {
            throw NoctwebBrowserError.invalidNetworkProfile("invalid display name")
        }
        guard Self.isDigestID(routingTrustDomainID) else {
            throw NoctwebBrowserError.invalidNetworkProfile("invalid routing trust-domain identifier")
        }
        guard Self.isIdentifier(consensusProfileID, maximum: 80) else {
            throw NoctwebBrowserError.invalidNetworkProfile("invalid consensus profile identifier")
        }
        guard verificationKey.count == 32 else {
            throw NoctwebBrowserError.invalidNetworkProfile("verification keys must contain 32 bytes")
        }
        guard
            bootstrapEndpoints.count <= Self.maximumBootstrapEndpoints,
            Set(bootstrapEndpoints).count == bootstrapEndpoints.count,
            bootstrapEndpoints.allSatisfy(Self.isSafeBootstrapEndpoint)
        else {
            throw NoctwebBrowserError.invalidNetworkProfile("invalid bootstrap endpoints")
        }
        guard
            !supportedEpochs.isEmpty,
            supportedEpochs.count <= Self.maximumSupportedEpochs,
            supportedEpochs == Array(Set(supportedEpochs)).sorted(),
            supportedEpochs.first != 0
        else {
            throw NoctwebBrowserError.invalidNetworkProfile("epochs must be unique, sorted, non-zero, and bounded")
        }
        guard
            federationMode != .solo || federationDirective == .open
        else {
            throw NoctwebBrowserError.invalidNetworkProfile(
                "solo mode must leave federation routing open"
            )
        }
        self.version = version
        self.id = id
        self.displayName = name
        self.routingTrustDomainID = routingTrustDomainID
        self.consensusProfileID = consensusProfileID
        self.verificationKey = verificationKey
        self.bootstrapEndpoints = bootstrapEndpoints
        self.supportedEpochs = supportedEpochs
        self.federationMode = federationMode
        self.federationDirective = federationDirective
        self.defaultVisitorDirective = defaultVisitorDirective
    }

    public func supports(epoch: UInt64) -> Bool {
        supportedEpochs.contains(epoch)
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case id
        case displayName
        case routingTrustDomainID
        case consensusProfileID
        case verificationKey
        case bootstrapEndpoints
        case supportedEpochs
        case federationMode
        case federationDirective
        case defaultVisitorDirective
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            version: container.decode(Int.self, forKey: .version),
            id: container.decode(String.self, forKey: .id),
            displayName: container.decode(String.self, forKey: .displayName),
            routingTrustDomainID: container.decode(
                String.self,
                forKey: .routingTrustDomainID
            ),
            consensusProfileID: container.decode(
                String.self,
                forKey: .consensusProfileID
            ),
            verificationKey: container.decode(
                Data.self,
                forKey: .verificationKey
            ),
            bootstrapEndpoints: container.decode(
                [URL].self,
                forKey: .bootstrapEndpoints
            ),
            supportedEpochs: container.decode(
                [UInt64].self,
                forKey: .supportedEpochs
            ),
            federationMode: container.decode(
                FederationMode.self,
                forKey: .federationMode
            ),
            federationDirective: container.decode(
                RouteDirective.self,
                forKey: .federationDirective
            ),
            defaultVisitorDirective: container.decode(
                RouteDirective.self,
                forKey: .defaultVisitorDirective
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(
            routingTrustDomainID,
            forKey: .routingTrustDomainID
        )
        try container.encode(consensusProfileID, forKey: .consensusProfileID)
        try container.encode(verificationKey, forKey: .verificationKey)
        try container.encode(bootstrapEndpoints, forKey: .bootstrapEndpoints)
        try container.encode(supportedEpochs, forKey: .supportedEpochs)
        try container.encode(federationMode, forKey: .federationMode)
        try container.encode(
            federationDirective,
            forKey: .federationDirective
        )
        try container.encode(
            defaultVisitorDirective,
            forKey: .defaultVisitorDirective
        )
    }

    static func isDigestID(_ value: String) -> Bool {
        guard value.hasPrefix("sha256:") else { return false }
        let digest = value.dropFirst("sha256:".count)
        return digest.utf8.count == 64 && digest.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    static func isPublisherID(_ value: String) -> Bool {
        guard value.hasPrefix("nwpub1_") else { return false }
        let digest = value.dropFirst("nwpub1_".count)
        return digest.utf8.count == 64 && digest.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    static func isSafeBootstrapEndpoint(_ endpoint: URL) -> Bool {
        guard
            endpoint.user == nil,
            endpoint.password == nil,
            endpoint.fragment == nil,
            endpoint.query == nil,
            let scheme = endpoint.scheme?.lowercased(),
            let host = endpoint.host?.lowercased(),
            !host.isEmpty
        else {
            return false
        }
        if scheme == "https" { return true }
        return scheme == "http" && (
            host == "localhost" ||
                host == "127.0.0.1" ||
                host == "::1"
        )
    }

    private static func isIdentifier(_ value: String, maximum: Int) -> Bool {
        let bytes = Array(value.utf8)
        guard
            !bytes.isEmpty,
            bytes.count <= maximum,
            isASCIIAlphanumeric(bytes[0]),
            isASCIIAlphanumeric(bytes[bytes.count - 1])
        else {
            return false
        }
        return bytes.allSatisfy {
            isASCIIAlphanumeric($0) || $0 == 46 || $0 == 45 || $0 == 95
        }
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (48...57).contains(byte) || (97...122).contains(byte)
    }
}
