import CryptoKit
import Foundation

public struct JSONWorkspaceRepository: @unchecked Sendable {
    private static let maximumWorkspaceBytes = 32 * 1_024 * 1_024

    public let fileURL: URL
    private let keyProvider: NoctwebLocalKeyProvider
    private let keyService: String

    public init(
        fileURL: URL,
        keyProvider: NoctwebLocalKeyProvider = NoctwebLocalKeyProvider(),
        keyService: String = "net.noctweave.noctweb-lab-core.workspace.v1"
    ) {
        self.fileURL = fileURL
        self.keyProvider = keyProvider
        self.keyService = keyService
    }

    public static func applicationSupport() throws -> JSONWorkspaceRepository {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return JSONWorkspaceRepository(
            fileURL: support
                .appendingPathComponent(
                    "Noctweave/Noctweb Lab",
                    isDirectory: true
                )
                .appendingPathComponent("workspace-v1.json")
        )
    }

    static func keyServiceForFileURL(_ fileURL: URL) -> String {
        let path = fileURL.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        let suffix = digest.map { String(format: "%02x", $0) }.joined()
        return "net.noctweave.noctweb-lab-core.workspace.path.\(suffix)"
    }

    public func load() throws -> WorkspaceSnapshot {
        do {
            guard FileManager.default.fileExists(
                atPath: fileURL.deletingLastPathComponent().path
            ) else { return .empty }
            let stored = try NoctwebSecureFileIO.read(
                from: fileURL,
                maximumBytes: Self.maximumWorkspaceBytes + NoctwebEncryptedLocalData.overheadBytes,
                requirePrivateOwner: true
            )
            guard NoctwebEncryptedLocalData.isSealed(stored) else {
                throw NoctwebEncryptedLocalDataError.malformed
            }
            var data = try NoctwebEncryptedLocalData.open(
                stored,
                using: NoctwebEncryptedLocalData.key(
                    service: keyService, provider: keyProvider
                ),
                context: "lab-core-workspace-v1"
            )
            defer { data.resetBytes(in: 0..<data.count) }
            let snapshot = try JSONDecoder().decode(
                WorkspaceSnapshot.self,
                from: data
            )
            guard snapshot.schemaVersion == 2 ||
                snapshot.schemaVersion ==
                    WorkspaceSnapshot.currentSchemaVersion
            else {
                throw NoctwebLabError.workspaceSchema(
                    snapshot.schemaVersion
                )
            }
            if
                snapshot.schemaVersion ==
                    WorkspaceSnapshot.currentSchemaVersion
            {
                return snapshot
            }
            return WorkspaceSnapshot(
                selectedPublicationID: snapshot.selectedPublicationID,
                publications: snapshot.publications,
                relays: snapshot.relays,
                federationPolicy: snapshot.federationPolicy
            )
        } catch NoctwebSecureFileIOError.notFound {
            return .empty
        } catch let error as NoctwebLabError {
            throw error
        } catch {
            throw NoctwebLabError.workspaceIO(String(describing: error))
        }
    }

    public func save(_ snapshot: WorkspaceSnapshot) throws {
        guard
            snapshot.schemaVersion ==
                WorkspaceSnapshot.currentSchemaVersion
        else {
            throw NoctwebLabError.workspaceSchema(snapshot.schemaVersion)
        }
        _ = try RelayTopology(
            nodes: snapshot.relays,
            federationPolicy: snapshot.federationPolicy
        )
        do {
            var data = try CanonicalJSON.encode(snapshot)
            defer { data.resetBytes(in: 0..<data.count) }
            guard data.count <= Self.maximumWorkspaceBytes else {
                throw NoctwebSecureFileIOError.tooLarge
            }
            let stored = try NoctwebEncryptedLocalData.seal(
                data,
                using: NoctwebEncryptedLocalData.key(
                    service: keyService, provider: keyProvider
                ),
                context: "lab-core-workspace-v1"
            )
            try NoctwebSecureFileIO.writePrivate(
                stored,
                to: fileURL,
                maximumBytes: Self.maximumWorkspaceBytes + NoctwebEncryptedLocalData.overheadBytes
            )
        } catch let error as NoctwebLabError {
            throw error
        } catch {
            throw NoctwebLabError.workspaceIO(String(describing: error))
        }
    }
}
