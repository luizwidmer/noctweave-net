import Foundation

public struct JSONWorkspaceRepository: @unchecked Sendable {
    private static let maximumWorkspaceBytes = 32 * 1_024 * 1_024

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
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

    public func load() throws -> WorkspaceSnapshot {
        do {
            let data = try NoctwebSecureFileIO.read(
                from: fileURL,
                maximumBytes: Self.maximumWorkspaceBytes,
                requirePrivateOwner: true
            )
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
            let data = try CanonicalJSON.encode(snapshot)
            try NoctwebSecureFileIO.writePrivate(
                data,
                to: fileURL,
                maximumBytes: Self.maximumWorkspaceBytes
            )
        } catch let error as NoctwebLabError {
            throw error
        } catch {
            throw NoctwebLabError.workspaceIO(String(describing: error))
        }
    }
}
