import CryptoKit
import Foundation

public enum CanonicalJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(value)
        } catch {
            throw NoctwebLabError.canonicalEncoding(String(describing: error))
        }
    }

    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw NoctwebLabError.canonicalEncoding(String(describing: error))
        }
    }
}

public enum NoctwebDigest {
    public static func objectID(for canonicalObject: Data) -> String {
        "sha256:\(hexDigest(canonicalObject))"
    }

    public static func headID(for head: PublisherHead) throws -> String {
        var material = Data("org.noctweave.noctweb/head-hash/v1".utf8)
        material.append(0)
        material.append(try PublisherSignatureDomain.payload(for: head.claims))
        material.append(head.signature)
        return "sha256:\(hexDigest(material))"
    }

    public static func publisherID(for publicKey: Data) -> String {
        var material = Data("org.noctweave.noctweb/publisher-id/v1".utf8)
        material.append(0)
        material.append(publicKey)
        return "nwpub1_\(hexDigest(material))"
    }

    public static func finalityReceiptID(
        headID: String,
        round: UInt64,
        quorum: Int,
        confirmations: [String]
    ) throws -> String {
        let claim = FinalityReceiptClaim(
            domain: "noctweb.mock-consensus.v0",
            headID: headID,
            round: round,
            quorum: quorum,
            confirmations: confirmations.sorted()
        )
        return "consensus:\(hexDigest(try CanonicalJSON.encode(claim)))"
    }

    private static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct FinalityReceiptClaim: Codable, Equatable, Sendable {
    let domain: String
    let headID: String
    let round: UInt64
    let quorum: Int
    let confirmations: [String]
}

enum PublisherSignatureDomain {
    static func payload(for claims: PublisherHeadClaims) throws -> Data {
        guard claims.publisherPublicKey.count == 32 else {
            throw NoctwebLabError.canonicalEncoding(
                "publisher public key must be exactly 32 bytes"
            )
        }
        var transcript = BinaryTranscript()
        let isCurrentProfile: Bool
        switch claims.protocolVersion {
        case CapsuleObject.currentProtocolVersion:
            isCurrentProfile = true
            guard
                let relayNamespaceID = claims.relayNamespaceID,
                RelayNamespace.isValidID(relayNamespaceID)
            else {
                throw NoctwebLabError.canonicalEncoding(
                    "noctweb-lab-v2 heads require a relay namespace identity"
                )
            }
            try transcript.append(
                Data("org.noctweave.noctweb/signed-head/v2".utf8),
                maximum: 64
            )
        case CapsuleObject.legacyProtocolVersion:
            isCurrentProfile = false
            guard claims.relayNamespaceID == nil else {
                throw NoctwebLabError.canonicalEncoding(
                    "legacy noctweb-lab-v1 heads cannot claim a relay namespace"
                )
            }
            try transcript.append(
                Data("org.noctweave.noctweb/signed-head/v1".utf8),
                maximum: 64
            )
        default:
            throw NoctwebLabError.canonicalEncoding(
                "unsupported publisher-head profile \(claims.protocolVersion)"
            )
        }
        transcript.data.append(1) // Ed25519 in the temporary lab-v0 registry.
        try transcript.append(claims.protocolVersion, maximum: 64)
        try transcript.append(claims.publicationID, maximum: 64)
        try transcript.append(claims.address, maximum: 2_048)
        if isCurrentProfile {
            try transcript.append(claims.relayNamespaceID!, maximum: 80)
        }
        try transcript.append(claims.publisherID, maximum: 128)
        try transcript.append(claims.publisherPublicKey, maximum: 32)
        try transcript.append(claims.objectID, maximum: 128)
        transcript.append(claims.revision)
        try transcript.appendOptional(claims.previousHeadID, maximum: 128)
        transcript.append(claims.issuedAtMilliseconds)
        return transcript.data
    }
}

private struct BinaryTranscript {
    var data = Data()

    mutating func append(_ value: String, maximum: Int) throws {
        try append(Data(value.utf8), maximum: maximum)
    }

    mutating func append(_ value: Data, maximum: Int) throws {
        guard value.count <= maximum else {
            throw NoctwebLabError.canonicalEncoding(
                "publisher-head transcript field exceeds its bound"
            )
        }
        guard let count = UInt32(exactly: value.count) else {
            throw NoctwebLabError.canonicalEncoding(
                "publisher-head transcript field exceeds UInt32"
            )
        }
        var bigEndianCount = count.bigEndian
        Swift.withUnsafeBytes(of: &bigEndianCount) {
            data.append(contentsOf: $0)
        }
        data.append(value)
    }

    mutating func append(_ value: UInt64) {
        var bigEndianValue = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndianValue) {
            data.append(contentsOf: $0)
        }
    }

    mutating func appendOptional(
        _ value: String?,
        maximum: Int
    ) throws {
        if let value {
            data.append(1)
            try append(value, maximum: maximum)
        } else {
            data.append(0)
        }
    }
}
