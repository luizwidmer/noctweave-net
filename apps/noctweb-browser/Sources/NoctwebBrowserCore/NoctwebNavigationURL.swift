import Foundation

public struct NoctwebNavigationURL:
    Codable,
    CustomStringConvertible,
    Hashable,
    Sendable
{
    public static let maximumUTF8Bytes = 4_096
    public static let maximumPathUTF8Bytes = 2_048
    public static let maximumQueryUTF8Bytes = 1_024
    public static let maximumFragmentUTF8Bytes = 1_024

    public let siteLabel: String
    public let relaySuffix: String
    public let percentEncodedPath: String
    public let percentEncodedQuery: String?
    public let percentEncodedFragment: String?

    public var baseAddress: String {
        "noct://\(siteLabel).\(relaySuffix)/"
    }

    public var canonicalString: String {
        var value = "noct://\(siteLabel).\(relaySuffix)\(percentEncodedPath)"
        if let percentEncodedQuery {
            value += "?\(percentEncodedQuery)"
        }
        if let percentEncodedFragment {
            value += "#\(percentEncodedFragment)"
        }
        return value
    }

    public var description: String {
        canonicalString
    }

    public var requestPath: String {
        guard percentEncodedPath != "/" else { return "/" }
        return percentEncodedPath.removingPercentEncoding ?? percentEncodedPath
    }

    public init(
        siteLabel: String,
        relaySuffix: String,
        percentEncodedPath: String = "/",
        percentEncodedQuery: String? = nil,
        percentEncodedFragment: String? = nil
    ) throws {
        guard Self.isCanonicalSiteLabel(siteLabel) else {
            throw NoctwebBrowserError.invalidURL("the site label is not canonical")
        }
        guard Self.isCanonicalRelaySuffix(relaySuffix) else {
            throw NoctwebBrowserError.invalidURL("the relay suffix is not canonical")
        }
        try Self.validatePath(percentEncodedPath)
        try Self.validateOptionalComponent(
            percentEncodedQuery,
            maximumBytes: Self.maximumQueryUTF8Bytes,
            name: "query"
        )
        try Self.validateOptionalComponent(
            percentEncodedFragment,
            maximumBytes: Self.maximumFragmentUTF8Bytes,
            name: "fragment"
        )
        self.siteLabel = siteLabel
        self.relaySuffix = relaySuffix
        self.percentEncodedPath = percentEncodedPath
        self.percentEncodedQuery = percentEncodedQuery
        self.percentEncodedFragment = percentEncodedFragment
        guard canonicalString.utf8.count <= Self.maximumUTF8Bytes else {
            throw NoctwebBrowserError.invalidURL("the URL is too long")
        }
    }

    public init(parsing value: String) throws {
        guard value.utf8.count <= Self.maximumUTF8Bytes else {
            throw NoctwebBrowserError.invalidURL("the URL is too long")
        }
        guard
            let components = URLComponents(string: value),
            components.scheme == "noct",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            let host = components.host,
            !host.isEmpty,
            !components.percentEncodedPath.isEmpty
        else {
            throw NoctwebBrowserError.invalidURL("expected noct://site.relay/")
        }
        guard host == host.lowercased(), !host.hasSuffix(".") else {
            throw NoctwebBrowserError.invalidURL("the authority must be lowercase without a trailing dot")
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count == 2 else {
            throw NoctwebBrowserError.invalidURL("the authority must contain exactly a site and relay label")
        }
        try self.init(
            siteLabel: String(labels[0]),
            relaySuffix: String(labels[1]),
            percentEncodedPath: components.percentEncodedPath,
            percentEncodedQuery: components.percentEncodedQuery,
            percentEncodedFragment: components.percentEncodedFragment
        )
    }

    public func withPath(_ percentEncodedPath: String) throws -> Self {
        try Self(
            siteLabel: siteLabel,
            relaySuffix: relaySuffix,
            percentEncodedPath: percentEncodedPath,
            percentEncodedQuery: nil,
            percentEncodedFragment: nil
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(parsing: container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalString)
    }

    private static func validatePath(_ value: String) throws {
        guard
            value.hasPrefix("/"),
            value.utf8.count <= maximumPathUTF8Bytes,
            !value.contains("\\"),
            !containsControlCharacter(value)
        else {
            throw NoctwebBrowserError.invalidURL("the path is not canonical")
        }
        if value == "/" { return }
        let segments = value.dropFirst().split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !segments.isEmpty else {
            throw NoctwebBrowserError.invalidURL("the path is empty")
        }
        for encodedSegment in segments {
            guard !encodedSegment.isEmpty else {
                throw NoctwebBrowserError.invalidURL("the path contains an empty segment")
            }
            let encoded = String(encodedSegment)
            guard let decoded = encoded.removingPercentEncoding else {
                throw NoctwebBrowserError.invalidURL("the path contains invalid percent encoding")
            }
            guard
                decoded != ".",
                decoded != "..",
                !decoded.contains("/"),
                !decoded.contains("\\"),
                !decoded.unicodeScalars.contains(where: { $0.value == 0 }),
                !containsControlCharacter(decoded)
            else {
                throw NoctwebBrowserError.invalidURL("the path contains a forbidden segment")
            }
        }
    }

    private static func validateOptionalComponent(
        _ value: String?,
        maximumBytes: Int,
        name: String
    ) throws {
        guard let value else { return }
        guard
            let decoded = value.removingPercentEncoding,
            !value.isEmpty,
            value.utf8.count <= maximumBytes,
            !containsControlCharacter(value),
            !containsControlCharacter(decoded)
        else {
            throw NoctwebBrowserError.invalidURL("the \(name) is not canonical")
        }
    }

    static func isCanonicalSiteLabel(_ value: String) -> Bool {
        isCanonicalLabel(value, maximumLength: 63) &&
            !value.hasPrefix("r-")
    }

    static func isCanonicalRelaySuffix(_ value: String) -> Bool {
        if value.hasPrefix("r-") {
            let tag = value.dropFirst(2)
            return tag.count == 16 &&
                tag.allSatisfy { "abcdefghijklmnopqrstuvwxyz234567".contains($0) }
        }
        return isCanonicalLabel(value, maximumLength: 32)
    }

    private static func isCanonicalLabel(
        _ value: String,
        maximumLength: Int
    ) -> Bool {
        guard
            !value.isEmpty,
            value.count <= maximumLength,
            value == value.lowercased(),
            value.unicodeScalars.allSatisfy(\.isASCII),
            !value.hasPrefix("xn--"),
            value.first?.isLetter == true || value.first?.isNumber == true,
            value.last?.isLetter == true || value.last?.isNumber == true
        else {
            return false
        }
        return value.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "-"
        }
    }

    private static func containsControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }
}
