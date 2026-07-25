import Foundation

public struct JSONWorkspaceRepository: @unchecked Sendable {
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
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(
                WorkspaceSnapshot.self,
                from: data
            )
            guard
                snapshot.schemaVersion ==
                    WorkspaceSnapshot.currentSchemaVersion
            else {
                throw NoctwebLabError.workspaceSchema(
                    snapshot.schemaVersion
                )
            }
            return snapshot
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
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try CanonicalJSON.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch let error as NoctwebLabError {
            throw error
        } catch {
            throw NoctwebLabError.workspaceIO(String(describing: error))
        }
    }
}
