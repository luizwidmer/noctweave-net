import CryptoKit
import Foundation
import LocalAuthentication
import Security

public enum NoctwebEncryptedLocalDataError: Error {
    case malformed
    case authenticationFailed
    case keychain(OSStatus)
}

public final class NoctwebLocalKeyProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String: SymmetricKey] = [:]

    public init() {}

    public func clearProcessCache() {
        lock.lock()
        keys.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    public func loadOrCreate(service: String) throws -> SymmetricKey {
        lock.lock()
        defer { lock.unlock() }
        if let key = keys[service] { return key }
        if let key = try load(service: service) {
            keys[service] = key
            return key
        }
        let key = SymmetricKey(size: .bits256)
        var material = key.withUnsafeBytes { Data($0) }
        defer { material.resetBytes(in: 0..<material.count) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "local-data-v1",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: material,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            guard let winner = try load(service: service) else {
                throw NoctwebEncryptedLocalDataError.keychain(status)
            }
            keys[service] = winner
            return winner
        }
        guard status == errSecSuccess else {
            throw NoctwebEncryptedLocalDataError.keychain(status)
        }
        keys[service] = key
        return key
    }

    public func loadExisting(service: String) throws -> SymmetricKey? {
        lock.lock()
        defer { lock.unlock() }
        return try load(service: service)
    }

    public func destroy(service: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "local-data-v1",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseAuthenticationContext as String: context,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NoctwebEncryptedLocalDataError.keychain(status)
        }
        keys.removeValue(forKey: service)
    }

    private func load(service: String) throws -> SymmetricKey? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "local-data-v1",
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, var data = result as? Data,
              data.count == 32 else {
            throw NoctwebEncryptedLocalDataError.keychain(status)
        }
        defer { data.resetBytes(in: 0..<data.count) }
        return SymmetricKey(data: data)
    }
}

/// Authenticated, whole-record encryption for app-owned metadata and drafts.
/// Files contain only this fixed format marker and an AES-GCM combined box.
public enum NoctwebEncryptedLocalData {
    private static let marker = Data("NWEL1".utf8)
    public static let overheadBytes = 5 + 12 + 16

    public static func key(
        service: String,
        provider: NoctwebLocalKeyProvider
    ) throws -> SymmetricKey {
        try provider.loadOrCreate(service: service)
    }

    public static func seal(
        _ plaintext: Data,
        using key: SymmetricKey,
        context: String = ""
    ) throws -> Data {
        let box = try AES.GCM.seal(
            plaintext, using: key, authenticating: Data(context.utf8)
        )
        guard let combined = box.combined else {
            throw NoctwebEncryptedLocalDataError.malformed
        }
        var output = marker
        output.append(combined)
        return output
    }

    public static func open(
        _ stored: Data,
        using key: SymmetricKey,
        context: String = ""
    ) throws -> Data {
        guard stored.count >= overheadBytes,
              stored.starts(with: marker) else {
            throw NoctwebEncryptedLocalDataError.malformed
        }
        do {
            let box = try AES.GCM.SealedBox(combined: stored.dropFirst(marker.count))
            return try AES.GCM.open(
                box, using: key, authenticating: Data(context.utf8)
            )
        } catch {
            throw NoctwebEncryptedLocalDataError.authenticationFailed
        }
    }

    public static func isSealed(_ data: Data) -> Bool {
        data.starts(with: marker)
    }
}
