import CryptoKit
import Foundation
import Security

public protocol PublicationPrivateKeyStore: Sendable {
    func loadPrivateKey(for publicationID: String) throws -> Data?
    func insertPrivateKey(_ privateKey: Data, for publicationID: String) throws
    func deletePrivateKey(for publicationID: String) throws
}

public struct PublicationSigningIdentity: Sendable {
    public let publicationID: String
    private let privateKey: Curve25519.Signing.PrivateKey

    public var publicKey: Data {
        privateKey.publicKey.rawRepresentation
    }

    public var publisherID: String {
        NoctwebDigest.publisherID(for: publicKey)
    }

    public init(publicationID: String, rawPrivateKey: Data) throws {
        try PublicationValidation.validateID(publicationID)
        do {
            self.privateKey = try Curve25519.Signing.PrivateKey(
                rawRepresentation: rawPrivateKey
            )
        } catch {
            throw NoctwebLabError.invalidPrivateKey(String(describing: error))
        }
        self.publicationID = publicationID
    }

    init(publicationID: String, privateKey: Curve25519.Signing.PrivateKey) {
        self.publicationID = publicationID
        self.privateKey = privateKey
    }

    public func sign(headClaims: PublisherHeadClaims) throws -> Data {
        try privateKey.signature(
            for: PublisherSignatureDomain.payload(for: headClaims)
        )
    }

    public static func verify(
        signature: Data,
        headClaims: PublisherHeadClaims
    ) -> Bool {
        do {
            let key = try Curve25519.Signing.PublicKey(
                rawRepresentation: headClaims.publisherPublicKey
            )
            return key.isValidSignature(
                signature,
                for: try PublisherSignatureDomain.payload(for: headClaims)
            )
        } catch {
            return false
        }
    }
}

public actor PublicationIdentityManager {
    private let store: any PublicationPrivateKeyStore

    public init(store: any PublicationPrivateKeyStore) {
        self.store = store
    }

    public func createIdentity(
        for publicationID: String
    ) throws -> PublicationSigningIdentity {
        try PublicationValidation.validateID(publicationID)

        if try store.loadPrivateKey(for: publicationID) != nil {
            throw NoctwebLabError.identityAlreadyExists(publicationID)
        }

        let generated = Curve25519.Signing.PrivateKey()
        do {
            try store.insertPrivateKey(
                generated.rawRepresentation,
                for: publicationID
            )
            return PublicationSigningIdentity(
                publicationID: publicationID,
                privateKey: generated
            )
        } catch NoctwebLabError.identityAlreadyExists {
            guard let winner = try store.loadPrivateKey(for: publicationID) else {
                throw NoctwebLabError.identityMissing(publicationID)
            }
            return try PublicationSigningIdentity(
                publicationID: publicationID,
                rawPrivateKey: winner
            )
        }
    }

    public func loadOrCreateIdentity(
        for publicationID: String
    ) throws -> PublicationSigningIdentity {
        try PublicationValidation.validateID(publicationID)

        if let stored = try store.loadPrivateKey(for: publicationID) {
            return try PublicationSigningIdentity(
                publicationID: publicationID,
                rawPrivateKey: stored
            )
        }
        return try createIdentity(for: publicationID)
    }

    public func loadIdentity(
        for publicationID: String,
        expectedPublisherID: String
    ) throws -> PublicationSigningIdentity {
        try PublicationValidation.validateID(publicationID)
        guard let stored = try store.loadPrivateKey(for: publicationID) else {
            throw NoctwebLabError.identityMissing(publicationID)
        }
        let identity = try PublicationSigningIdentity(
            publicationID: publicationID,
            rawPrivateKey: stored
        )
        guard identity.publisherID == expectedPublisherID else {
            throw NoctwebLabError.publisherMismatch(
                expected: expectedPublisherID,
                actual: identity.publisherID
            )
        }
        return identity
    }

    public func deleteIdentity(for publicationID: String) throws {
        try PublicationValidation.validateID(publicationID)
        try store.deletePrivateKey(for: publicationID)
    }
}

public final class InMemoryPublicationPrivateKeyStore:
    PublicationPrivateKeyStore,
    @unchecked Sendable
{
    private var keys: [String: Data]
    private let lock = NSLock()

    public init(keys: [String: Data] = [:]) {
        self.keys = keys
    }

    public func loadPrivateKey(for publicationID: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return keys[publicationID]
    }

    public func insertPrivateKey(
        _ privateKey: Data,
        for publicationID: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard keys[publicationID] == nil else {
            throw NoctwebLabError.identityAlreadyExists(publicationID)
        }
        keys[publicationID] = privateKey
    }

    public func deletePrivateKey(for publicationID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        keys.removeValue(forKey: publicationID)
    }
}

public struct KeychainPublicationIdentityStore: PublicationPrivateKeyStore {
    public static let defaultService =
        "org.noctweave.noctweb.publisher-key.v1"

    public let service: String

    public init(service: String = KeychainPublicationIdentityStore.defaultService) {
        self.service = service
    }

    public func loadPrivateKey(for publicationID: String) throws -> Data? {
        try PublicationValidation.validateID(publicationID)
        let account = publicationID.lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrGeneric as String: Data("ed25519-v1".utf8),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &result
        )
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw NoctwebLabError.keychainFailure(status)
        }
        guard let data = result as? Data else {
            throw NoctwebLabError.keychainFailure(errSecDecode)
        }
        return data
    }

    public func insertPrivateKey(
        _ privateKey: Data,
        for publicationID: String
    ) throws {
        try PublicationValidation.validateID(publicationID)
        let account = publicationID.lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Noctweb publisher identity",
            kSecAttrDescription as String:
                "Ed25519 private key for publication \(account)",
            kSecAttrGeneric as String: Data("ed25519-v1".utf8),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: privateKey,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            throw NoctwebLabError.identityAlreadyExists(publicationID)
        }
        guard status == errSecSuccess else {
            throw NoctwebLabError.keychainFailure(status)
        }
    }

    public func deletePrivateKey(for publicationID: String) throws {
        try PublicationValidation.validateID(publicationID)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: publicationID.lowercased(),
            kSecAttrGeneric as String: Data("ed25519-v1".utf8),
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NoctwebLabError.keychainFailure(status)
        }
    }
}

enum PublicationValidation {
    static func validateID(_ publicationID: String) throws {
        guard
            let uuid = UUID(uuidString: publicationID),
            uuid.uuidString.lowercased() == publicationID
        else {
            throw NoctwebLabError.invalidPublicationID(publicationID)
        }
    }

    static func validateDraft(_ draft: CapsuleSiteDraft) throws {
        try validateID(draft.publicationID)
        _ = try NoctwebAddress.parse(draft.address)
        guard
            let relayNamespaceID = draft.relayNamespaceID,
            RelayNamespace.isValidID(relayNamespaceID)
        else {
            throw NoctwebLabError.canonicalEncoding(
                "a valid relay namespace identity is required"
            )
        }
        if draft.bundle == nil, (
            draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ) {
            throw NoctwebLabError.canonicalEncoding(
                "title and body must not be empty"
            )
        }

        let accent = draft.accentHex.hasPrefix("#")
            ? String(draft.accentHex.dropFirst())
            : draft.accentHex
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard accent.count == 6, accent.unicodeScalars.allSatisfy(hex.contains) else {
            throw NoctwebLabError.canonicalEncoding(
                "accentHex must contain exactly six hexadecimal digits"
            )
        }

        if let bundle = draft.bundle {
            _ = try WebsiteBundleValidation.canonicalized(bundle)
        }
    }

    static func canonicalBundle(for draft: CapsuleSiteDraft) throws -> WebsiteBundle {
        if let bundle = draft.bundle {
            return try WebsiteBundleValidation.canonicalized(bundle)
        }

        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(draft.title))</title>
          <style>:root { color-scheme: light dark; --accent: \(draft.accentHex); } body { font-family: system-ui, sans-serif; max-width: 52rem; margin: 4rem auto; padding: 0 1.5rem; } h1 { color: var(--accent); }</style>
        </head>
        <body>
          <main>
            <h1>\(escapeHTML(draft.title))</h1>
            <p>\(escapeHTML(draft.subtitle))</p>
            <p>\(escapeHTML(draft.body))</p>
          </main>
        </body>
        </html>
        """
        return WebsiteBundle(
            entryPath: "index.html",
            files: [
                WebsiteFile(
                    path: "index.html",
                    mediaType: "text/html; charset=utf-8",
                    bytes: Data(html.utf8)
                ),
            ]
        )
    }

    static func validateObject(_ object: CapsuleObject) throws {
        try validateID(object.publicationID)
        switch object.protocolVersion {
        case CapsuleObject.currentProtocolVersion:
            _ = try NoctwebAddress.parse(object.address)
            guard
                let relayNamespaceID = object.relayNamespaceID,
                RelayNamespace.isValidID(relayNamespaceID)
            else {
                throw NoctwebLabError.canonicalEncoding(
                    "noctweb-lab-v2 objects require a relay namespace identity"
                )
            }
            guard let bundle = object.bundle else {
                throw NoctwebLabError.invalidWebsiteBundle(
                    "noctweb-lab-v2 objects require a website bundle"
                )
            }
            guard try WebsiteBundleValidation.canonicalized(bundle) == bundle else {
                throw NoctwebLabError.invalidWebsiteBundle(
                    "website files are not in canonical path order"
                )
            }
        case CapsuleObject.legacyProtocolVersion:
            try validateLegacyAddress(object.address)
            guard object.relayNamespaceID == nil else {
                throw NoctwebLabError.canonicalEncoding(
                    "legacy noctweb-lab-v1 objects cannot claim a relay namespace"
                )
            }
            guard let bundle = object.bundle else {
                throw NoctwebLabError.invalidWebsiteBundle(
                    "legacy noctweb-lab-v1 objects require a website bundle"
                )
            }
            guard try WebsiteBundleValidation.canonicalized(bundle) == bundle else {
                throw NoctwebLabError.invalidWebsiteBundle(
                    "website files are not in canonical path order"
                )
            }
        default:
            throw NoctwebLabError.canonicalEncoding(
                "unsupported Noctweb object profile \(object.protocolVersion)"
            )
        }
    }

    static func validateLegacyAddress(_ address: String) throws {
        guard
            let components = URLComponents(string: address),
            components.scheme == "noct",
            components.host?.isEmpty == false,
            components.path.isEmpty || components.path == "/"
        else {
            throw NoctwebLabError.invalidAddress(address)
        }
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
