import CryptoKit
import Foundation

/// Stable namespace identity advertised by a host relay.
///
/// The full identifier is the security comparison. The short suffix is only
/// the human-facing component used in a `noct://` address.
public struct RelayNamespace: Equatable, Sendable {
    public static let automaticSuffixPrefix = "r-"
    public static let automaticSuffixCharacterCount = 16

    public let id: String
    public let suffix: String
    public let usesCustomSuffix: Bool

    public init(
        publicKey: Data,
        operatorSuffix: String? = nil
    ) throws {
        guard publicKey.count == 32 else {
            throw NoctwebLabError.invalidRelayTopology(
                "host relay namespace public keys must be exactly 32 bytes"
            )
        }

        let digest = Self.namespaceDigest(publicKey)
        id = "sha256:\(Self.hex(digest))"

        if let operatorSuffix {
            suffix = try Self.canonicalOperatorSuffix(operatorSuffix)
            usesCustomSuffix = true
        } else {
            suffix = Self.automaticSuffix(from: digest)
            usesCustomSuffix = false
        }
    }

    /// Accepts the operator-friendly `.example` spelling, but returns the
    /// canonical suffix without its leading dot.
    public static func canonicalOperatorSuffix(
        _ value: String
    ) throws -> String {
        let candidate = value.hasPrefix(".")
            ? String(value.dropFirst())
            : value
        guard
            !candidate.hasPrefix(automaticSuffixPrefix),
            isCanonicalLabel(candidate),
            candidate.count <= 32
        else {
            throw NoctwebLabError.invalidRelayTopology(
                "custom relay namespace suffixes must be 1-32 lowercase ASCII label characters and must not use the reserved r- prefix"
            )
        }
        return candidate
    }

    public static func isValidID(_ value: String) -> Bool {
        guard value.hasPrefix("sha256:") else { return false }
        let digest = value.dropFirst("sha256:".count)
        return digest.utf8.count == 64 && digest.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    static func deterministicLabPublicKey(seed: String) -> Data {
        var material = Data(
            "org.noctweave.noctweb/lab-relay-namespace-key/v1".utf8
        )
        material.append(0)
        material.append(Data(seed.utf8))
        return Data(SHA256.hash(data: material))
    }

    static func isCanonicalNamespaceSuffix(_ value: String) -> Bool {
        if value.hasPrefix(automaticSuffixPrefix) {
            let tag = value.dropFirst(automaticSuffixPrefix.count)
            return tag.count == automaticSuffixCharacterCount &&
                tag.allSatisfy { base32Alphabet.contains($0) }
        }
        return isCanonicalLabel(value) && value.count <= 32
    }

    private static func namespaceDigest(_ publicKey: Data) -> Data {
        var material = Data(
            "org.noctweave.noctweb/relay-namespace-id/v1".utf8
        )
        material.append(0)
        material.append(publicKey)
        return Data(SHA256.hash(data: material))
    }

    private static func automaticSuffix(from digest: Data) -> String {
        let tag = base32(Data(digest.prefix(10)))
        return "\(automaticSuffixPrefix)\(tag)"
    }

    private static let base32Alphabet = Array(
        "abcdefghijklmnopqrstuvwxyz234567"
    )

    private static func base32(_ bytes: Data) -> String {
        var accumulator = 0
        var bitCount = 0
        var output = ""

        for byte in bytes {
            accumulator = (accumulator << 8) | Int(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                let index = (accumulator >> bitCount) & 0x1f
                output.append(base32Alphabet[index])
            }
            if bitCount == 0 {
                accumulator = 0
            } else {
                accumulator &= (1 << bitCount) - 1
            }
        }
        if bitCount > 0 {
            output.append(base32Alphabet[(accumulator << (5 - bitCount)) & 0x1f])
        }
        return output
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func isCanonicalLabel(_ value: String) -> Bool {
        guard
            !value.isEmpty,
            value.count <= 63,
            value == value.lowercased(),
            value.unicodeScalars.allSatisfy(\.isASCII),
            !value.hasPrefix("xn--"),
            value.first.map({ $0.isLetter || $0.isNumber }) == true,
            value.last.map({ $0.isLetter || $0.isNumber }) == true
        else {
            return false
        }
        return value.allSatisfy { character in
            character.isLetter || character.isNumber || character == "-"
        }
    }
}

/// Canonical, relay-scoped Noctweb address.
///
/// Exactly one site label and one relay namespace suffix are accepted. This
/// deliberately excludes aliases through case, ports, credentials, escaping,
/// query strings, fragments, trailing dots, or alternate paths.
public struct NoctwebAddress:
    CustomStringConvertible,
    Equatable,
    Hashable,
    Sendable
{
    public let siteLabel: String
    public let relaySuffix: String

    public var canonicalString: String {
        "noct://\(siteLabel).\(relaySuffix)/"
    }

    public var description: String {
        canonicalString
    }

    public init(siteLabel: String, relaySuffix: String) throws {
        guard RelayNamespace.isCanonicalLabel(siteLabel) else {
            throw NoctwebLabError.invalidAddress(
                "noct://\(siteLabel).\(relaySuffix)/"
            )
        }
        guard RelayNamespace.isCanonicalNamespaceSuffix(relaySuffix) else {
            throw NoctwebLabError.invalidAddress(
                "noct://\(siteLabel).\(relaySuffix)/"
            )
        }
        self.siteLabel = siteLabel
        self.relaySuffix = relaySuffix
    }

    public static func parse(_ value: String) throws -> NoctwebAddress {
        let prefix = "noct://"
        guard value.hasPrefix(prefix), value.hasSuffix("/") else {
            throw NoctwebLabError.invalidAddress(value)
        }
        let start = value.index(value.startIndex, offsetBy: prefix.count)
        let end = value.index(before: value.endIndex)
        let authority = String(value[start..<end])

        guard
            !authority.isEmpty,
            !authority.contains(where: { "/:@?#%[]".contains($0) })
        else {
            throw NoctwebLabError.invalidAddress(value)
        }
        let labels = authority.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard labels.count == 2 else {
            throw NoctwebLabError.invalidAddress(value)
        }

        let address = try NoctwebAddress(
            siteLabel: String(labels[0]),
            relaySuffix: String(labels[1])
        )
        guard address.canonicalString == value else {
            throw NoctwebLabError.invalidAddress(value)
        }
        return address
    }
}
