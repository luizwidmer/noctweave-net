import Foundation
import NoctwebLabCore
import XCTest

@testable import NoctwebLab

@MainActor
final class AppModelTests: XCTestCase {
    func testDeletingLastSitePersistsEmptyWorkspaceAndKeepsPublisherKey() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let model = AppModel(
            engine: fixture.engine,
            workspaceFileURL: fixture.workspaceURL
        )
        let siteID = try XCTUnwrap(model.selectedSite?.id)
        let publicationID = siteID.uuidString.lowercased()
        let publisherID = try await fixture.engine.preparePublisherIdentity(
            for: publicationID
        )

        XCTAssertTrue(model.deleteSite(siteID))
        XCTAssertEqual(model.activeWorkspace?.sites, [])
        XCTAssertNil(model.selectedSiteID)

        let decoded = try decodeWorkspaces(at: fixture.workspaceURL)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].sites, [])

        let retainedPublisherID = try await fixture.engine.preparePublisherIdentity(
            for: publicationID
        )
        XCTAssertEqual(retainedPublisherID, publisherID)
    }

    func testDeletingOnlyWorkspacePersistsAnEmptyProduct() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let model = AppModel(
            engine: fixture.engine,
            workspaceFileURL: fixture.workspaceURL
        )
        let workspaceID = try XCTUnwrap(model.activeWorkspaceID)

        XCTAssertTrue(model.deleteWorkspace(workspaceID))
        XCTAssertTrue(model.workspaces.isEmpty)
        XCTAssertNil(model.activeWorkspaceID)
        XCTAssertNil(model.selectedSiteID)
        XCTAssertEqual(try decodeWorkspaces(at: fixture.workspaceURL), [])

        let reopened = AppModel(
            engine: fixture.engine,
            workspaceFileURL: fixture.workspaceURL
        )
        XCTAssertTrue(reopened.workspaces.isEmpty)
        XCTAssertNil(reopened.activeWorkspaceID)
    }

    func testDraftEditCannotClearPublicationInFlightGuard() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let model = AppModel(
            engine: fixture.engine,
            workspaceFileURL: fixture.workspaceURL
        )
        let siteID = try XCTUnwrap(model.selectedSiteID)

        model.publishSelectedSite()
        XCTAssertTrue(model.publicationInFlight)

        model.updateSelectedVisualSite { site in
            var blocks = site.resolvedBlocks
            blocks[0].heading = "A newer local draft"
            site.blocks = blocks
        }

        XCTAssertTrue(model.publicationInFlight)
        XCTAssertFalse(model.deleteSite(siteID))
        XCTAssertTrue(
            model.operationError?.contains("publication") == true
        )

        for _ in 0..<100 where model.publicationInFlight {
            await Task.yield()
        }
        XCTAssertFalse(model.publicationInFlight)
        XCTAssertEqual(model.publicationOutcome, .ready)
        XCTAssertTrue(
            model.publicationMessage.contains("newer draft")
        )
        model.flushPersistence()
    }

    func testRelayFailureDoesNotDisableHealthyPublisherIdentity() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let model = AppModel(
            engine: fixture.engine,
            workspaceFileURL: fixture.workspaceURL
        )
        let siteID = try XCTUnwrap(model.selectedSiteID)
        let publisherID = try await fixture.engine.preparePublisherIdentity(
            for: siteID.uuidString.lowercased()
        )
        model.updateSelectedSite { site in
            site.publisherID = publisherID
            site.publicationIdentity = .ready
        }

        let topology = try await fixture.engine.topology()
        for host in topology.nodes where host.role == .host {
            try await fixture.engine.setRelayOnline(
                false,
                relayID: host.id
            )
        }

        model.publishSelectedSite()
        for _ in 0..<100 where model.publicationInFlight {
            await Task.yield()
        }

        XCTAssertFalse(model.publicationInFlight)
        XCTAssertEqual(model.publicationOutcome, .failed)
        XCTAssertEqual(
            model.selectedSite?.publicationIdentity,
            .ready
        )
        model.flushPersistence()
    }

    func testDestroyDoesNotDeleteKeyWhenTombstoneCannotBeSaved() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let seeded = try await seedReadyWorkspace(in: fixture)

        let model = AppModel(
            engine: fixture.engine,
            workspaceFileURL: fixture.workspaceURL
        )
        let journalURL = AppModel.publisherIdentityDeletionJournalURL(
            for: fixture.workspaceURL
        )
        try FileManager.default.createDirectory(
            at: journalURL,
            withIntermediateDirectories: false
        )

        let destroyed = await model.destroyPublisherIdentity(
            for: seeded.siteID
        )
        XCTAssertFalse(destroyed)
        XCTAssertNotNil(
            try fixture.store.loadPrivateKey(
                for: seeded.siteID.uuidString.lowercased()
            )
        )
        XCTAssertTrue(
            model.operationError?.contains(
                "deletion request could not be saved"
            ) == true
        )
    }

    func testDestroyedKeyReconcilesFromJournalAfterWorkspaceSaveFailure() async throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }
        let seeded = try await seedReadyWorkspace(in: fixture)

        let model = AppModel(
            engine: fixture.engine,
            workspaceFileURL: fixture.workspaceURL
        )
        try FileManager.default.removeItem(at: fixture.workspaceURL)
        try FileManager.default.createDirectory(
            at: fixture.workspaceURL,
            withIntermediateDirectories: false
        )

        let destroyed = await model.destroyPublisherIdentity(
            for: seeded.siteID
        )
        XCTAssertTrue(destroyed)
        XCTAssertNil(
            try fixture.store.loadPrivateKey(
                for: seeded.siteID.uuidString.lowercased()
            )
        )
        XCTAssertTrue(
            model.operationError?.contains(
                "publisher key was destroyed"
            ) == true
        )
        XCTAssertFalse(
            model.operationError?.contains(
                "publisher key was not destroyed"
            ) == true
        )

        let journalURL = AppModel.publisherIdentityDeletionJournalURL(
            for: fixture.workspaceURL
        )
        XCTAssertEqual(
            try decodeDeletionJournal(at: journalURL).pending.map(\.siteID),
            [seeded.siteID]
        )

        try FileManager.default.removeItem(at: fixture.workspaceURL)
        try writeWorkspaces([seeded.workspace], to: fixture.workspaceURL)
        let reopened = AppModel(
            engine: fixture.engine,
            workspaceFileURL: fixture.workspaceURL
        )

        for _ in 0..<500 {
            if
                reopened.selectedSite?.publicationIdentity == .unavailable,
                let journal = try? decodeDeletionJournal(at: journalURL),
                journal.pending.isEmpty
            {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(
            reopened.selectedSite?.publicationIdentity,
            .unavailable
        )
        XCTAssertEqual(
            try decodeDeletionJournal(at: journalURL),
            .empty
        )
        XCTAssertNil(
            try fixture.store.loadPrivateKey(
                for: seeded.siteID.uuidString.lowercased()
            )
        )
    }

    func testDeletionWaitsForPublisherIdentityPreparation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        var workspace = Workspace.starter()
        workspace.sites = []
        let workspaceURL = root.appendingPathComponent("workspaces.json")
        try writeWorkspaces([workspace], to: workspaceURL)

        let store = BlockingPublicationPrivateKeyStore()
        defer { store.releaseLoads() }
        let model = AppModel(
            engine: try NoctwebLabEngine(identityStore: store),
            workspaceFileURL: workspaceURL
        )
        model.createSite()
        let siteID = try XCTUnwrap(model.selectedSiteID)

        for _ in 0..<500
        where !model.identityPreparationSiteIDs.contains(siteID) {
            await Task.yield()
        }
        XCTAssertTrue(
            model.identityPreparationSiteIDs.contains(siteID)
        )

        XCTAssertFalse(model.deleteSite(siteID))
        XCTAssertTrue(
            model.operationError?.contains("preparation") == true
        )
        let destroyedDuringPreparation =
            await model.destroyPublisherIdentity(for: siteID)
        XCTAssertFalse(destroyedDuringPreparation)
        XCTAssertTrue(
            model.operationError?.contains("finish preparing") == true
        )
        XCTAssertFalse(model.deleteWorkspace(workspace.id))
        XCTAssertTrue(
            model.operationError?.contains("preparation") == true
        )

        store.releaseLoads()
        for _ in 0..<500
        where model.identityPreparationSiteIDs.contains(siteID) {
            await Task.yield()
        }

        XCTAssertFalse(
            model.identityPreparationSiteIDs.contains(siteID)
        )
        XCTAssertEqual(model.selectedSite?.publicationIdentity, .ready)
        XCTAssertNotNil(model.selectedSite?.publisherID)
    }

    func testImportPreservesReactStyleProductionBuildFiles() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let buildURL = fixture.root.appendingPathComponent(
            "dist",
            isDirectory: true
        )
        let assetsURL = buildURL.appendingPathComponent(
            "assets",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: assetsURL,
            withIntermediateDirectories: true
        )

        let html = """
        <!doctype html>
        <html><body><div id="root"></div><script type="module" src="/assets/app.js"></script></body></html>
        """
        let javascript =
            "import{c as createElement}from'./vendor-4ac891.js';window.__ready=!!createElement;"
        let vendorJavaScript =
            "const c=(tag,props)=>({tag,props});export{c};"
        let imageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        try Data(html.utf8).write(
            to: buildURL.appendingPathComponent("index.html")
        )
        try Data(javascript.utf8).write(
            to: assetsURL.appendingPathComponent("app.js")
        )
        try Data(vendorJavaScript.utf8).write(
            to: assetsURL.appendingPathComponent("vendor-4ac891.js")
        )
        try imageBytes.write(
            to: assetsURL.appendingPathComponent("mark.png")
        )

        let files = try WebsiteProjectBuilder.importDirectory(at: buildURL)
        let fileMap = Dictionary(uniqueKeysWithValues: files.map {
            ($0.path, $0.bytes)
        })

        XCTAssertEqual(fileMap["index.html"], Data(html.utf8))
        XCTAssertEqual(fileMap["assets/app.js"], Data(javascript.utf8))
        XCTAssertEqual(
            fileMap["assets/vendor-4ac891.js"],
            Data(vendorJavaScript.utf8)
        )
        XCTAssertEqual(fileMap["assets/mark.png"], imageBytes)
        XCTAssertEqual(
            files.first(where: { $0.path == "assets/app.js" })?.mediaType,
            "text/javascript"
        )
    }

    func testImportRejectsSymbolicLinkedDirectories() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let buildURL = fixture.root.appendingPathComponent(
            "dist",
            isDirectory: true
        )
        let outsideURL = fixture.root.appendingPathComponent(
            "outside",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: buildURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outsideURL,
            withIntermediateDirectories: true
        )
        try Data("<!doctype html>".utf8).write(
            to: buildURL.appendingPathComponent("index.html")
        )
        try Data("secret".utf8).write(
            to: outsideURL.appendingPathComponent("outside.txt")
        )
        try FileManager.default.createSymbolicLink(
            at: buildURL.appendingPathComponent("linked-assets"),
            withDestinationURL: outsideURL
        )

        XCTAssertThrowsError(
            try WebsiteProjectBuilder.importDirectory(at: buildURL)
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("Symbolic links")
            )
        }
    }

    func testImportRejectsOversizedFileBeforeReadingIt() throws {
        let fixture = try makeFixture()
        defer { fixture.remove() }

        let buildURL = fixture.root.appendingPathComponent(
            "dist",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: buildURL,
            withIntermediateDirectories: true
        )
        try Data("<!doctype html>".utf8).write(
            to: buildURL.appendingPathComponent("index.html")
        )
        let oversizedURL = buildURL.appendingPathComponent("oversized.bin")
        XCTAssertTrue(
            FileManager.default.createFile(
                atPath: oversizedURL.path,
                contents: nil
            )
        )
        let handle = try FileHandle(forWritingTo: oversizedURL)
        try handle.truncate(
            atOffset: UInt64(WebsiteProjectBuilder.maximumBundleBytes + 1)
        )
        try handle.close()

        XCTAssertThrowsError(
            try WebsiteProjectBuilder.importDirectory(at: buildURL)
        ) { error in
            XCTAssertTrue(
                error.localizedDescription.contains("16 MB")
            )
        }
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let store = InMemoryPublicationPrivateKeyStore()
        return Fixture(
            root: root,
            workspaceURL: root.appendingPathComponent("workspaces.json"),
            store: store,
            engine: try NoctwebLabEngine(
                identityStore: store
            )
        )
    }

    private func seedReadyWorkspace(
        in fixture: Fixture
    ) async throws -> (
        workspace: Workspace,
        siteID: UUID,
        publisherID: String
    ) {
        var workspace = Workspace.starter()
        let siteID = try XCTUnwrap(workspace.sites.first?.id)
        let publisherID = try await fixture.engine.preparePublisherIdentity(
            for: siteID.uuidString.lowercased()
        )
        workspace.sites[0].publisherID = publisherID
        workspace.sites[0].publicationIdentity = .ready
        try writeWorkspaces([workspace], to: fixture.workspaceURL)
        return (workspace, siteID, publisherID)
    }

    private func writeWorkspaces(
        _ workspaces: [Workspace],
        to url: URL
    ) throws {
        try JSONEncoder().encode(workspaces).write(
            to: url,
            options: .atomic
        )
    }

    private func decodeWorkspaces(at url: URL) throws -> [Workspace] {
        try JSONDecoder().decode(
            [Workspace].self,
            from: Data(contentsOf: url)
        )
    }

    private func decodeDeletionJournal(
        at url: URL
    ) throws -> PublisherIdentityDeletionJournal {
        try JSONDecoder().decode(
            PublisherIdentityDeletionJournal.self,
            from: Data(contentsOf: url)
        )
    }
}

private struct Fixture {
    let root: URL
    let workspaceURL: URL
    let store: InMemoryPublicationPrivateKeyStore
    let engine: NoctwebLabEngine

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class BlockingPublicationPrivateKeyStore:
    PublicationPrivateKeyStore,
    @unchecked Sendable
{
    private let condition = NSCondition()
    private var blocksLoads = true
    private var keys: [String: Data] = [:]

    func loadPrivateKey(for publicationID: String) throws -> Data? {
        condition.lock()
        defer { condition.unlock() }
        while blocksLoads {
            condition.wait()
        }
        return keys[publicationID]
    }

    func insertPrivateKey(
        _ privateKey: Data,
        for publicationID: String
    ) throws {
        condition.lock()
        defer { condition.unlock() }
        guard keys[publicationID] == nil else {
            throw NoctwebLabError.identityAlreadyExists(publicationID)
        }
        keys[publicationID] = privateKey
    }

    func deletePrivateKey(for publicationID: String) throws {
        condition.lock()
        keys.removeValue(forKey: publicationID)
        condition.unlock()
    }

    func releaseLoads() {
        condition.lock()
        blocksLoads = false
        condition.broadcast()
        condition.unlock()
    }
}
