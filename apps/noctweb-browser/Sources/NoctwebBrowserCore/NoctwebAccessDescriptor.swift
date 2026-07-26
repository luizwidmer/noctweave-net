import CoreFoundation
import Foundation

public struct NoctwebAccessDescriptor:
    Equatable,
    Hashable,
    Sendable
{
    public static let currentVersion = 1
    public static let maximumEncodedBytes = 16 * 1_024
    public static let maximumBootstrapHints = 8

    public let version: Int
    public let navigationURL: NoctwebNavigationURL
    public let routingTrustDomainID: String
    public let expectedPublisherID: String?
    public let bootstrapHints: [URL]

    public init(
        version: Int = Self.currentVersion,
        navigationURL: NoctwebNavigationURL,
        routingTrustDomainID: String,
        expectedPublisherID: String? = nil,
        bootstrapHints: [URL] = []
    ) throws {
        guard version == Self.currentVersion else {
            throw NoctwebBrowserError.invalidAccessDescriptor("unsupported version")
        }
        guard NoctwebNetworkProfile.isDigestID(routingTrustDomainID) else {
            throw NoctwebBrowserError.invalidAccessDescriptor("invalid trust-domain identifier")
        }
        if let expectedPublisherID {
            guard NoctwebNetworkProfile.isPublisherID(expectedPublisherID) else {
                throw NoctwebBrowserError.invalidAccessDescriptor("invalid expected publisher")
            }
        }
        guard
            bootstrapHints.count <= Self.maximumBootstrapHints,
            Set(bootstrapHints).count == bootstrapHints.count,
            bootstrapHints.allSatisfy(NoctwebNetworkProfile.isSafeBootstrapEndpoint)
        else {
            throw NoctwebBrowserError.invalidAccessDescriptor("invalid bootstrap hints")
        }
        self.version = version
        self.navigationURL = navigationURL
        self.routingTrustDomainID = routingTrustDomainID
        self.expectedPublisherID = expectedPublisherID
        self.bootstrapHints = bootstrapHints
    }

    public func encodedJSON() throws -> Data {
        let object: [String: Any] = [
            "version": version,
            "url": navigationURL.canonicalString,
            "routingTrustDomainID": routingTrustDomainID,
            "expectedPublisherID": expectedPublisherID ?? NSNull(),
            "bootstrapHints": bootstrapHints.map(\.absoluteString),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        guard data.count <= Self.maximumEncodedBytes else {
            throw NoctwebBrowserError.invalidAccessDescriptor("descriptor exceeds its byte limit")
        }
        return data
    }

    public static func decodeExactJSON(_ data: Data) throws -> Self {
        guard
            !data.isEmpty,
            data.count <= maximumEncodedBytes
        else {
            throw NoctwebBrowserError.invalidAccessDescriptor("descriptor size is invalid")
        }
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        } catch {
            throw NoctwebBrowserError.invalidAccessDescriptor("malformed JSON")
        }
        guard let object = raw as? [String: Any] else {
            throw NoctwebBrowserError.invalidAccessDescriptor("expected one JSON object")
        }
        let required = Set([
            "version",
            "url",
            "routingTrustDomainID",
            "expectedPublisherID",
            "bootstrapHints",
        ])
        guard Set(object.keys) == required else {
            throw NoctwebBrowserError.invalidAccessDescriptor("field set is not exact")
        }
        guard
            let versionNumber = object["version"] as? NSNumber,
            CFGetTypeID(versionNumber) != CFBooleanGetTypeID(),
            versionNumber.intValue == currentVersion,
            versionNumber.doubleValue == Double(versionNumber.intValue),
            let urlString = object["url"] as? String,
            let trustDomainID = object["routingTrustDomainID"] as? String,
            let rawHints = object["bootstrapHints"] as? [Any],
            rawHints.allSatisfy({ $0 is String })
        else {
            throw NoctwebBrowserError.invalidAccessDescriptor("field types are invalid")
        }
        let expectedPublisherID: String?
        switch object["expectedPublisherID"] {
        case is NSNull:
            expectedPublisherID = nil
        case let value as String:
            expectedPublisherID = value
        default:
            throw NoctwebBrowserError.invalidAccessDescriptor(
                "expectedPublisherID must be a string or null"
            )
        }
        let hints = try rawHints.map { rawHint -> URL in
            guard let url = URL(string: rawHint as! String) else {
                throw NoctwebBrowserError.invalidAccessDescriptor("invalid bootstrap URL")
            }
            return url
        }
        return try Self(
            navigationURL: NoctwebNavigationURL(parsing: urlString),
            routingTrustDomainID: trustDomainID,
            expectedPublisherID: expectedPublisherID,
            bootstrapHints: hints
        )
    }
}
