import CryptoKit
import Foundation
import XCTest
@testable import NoctwebLabCore

final class NoctwebLabCoreTests: XCTestCase {
    private func draft(
        publicationID: String = UUID().uuidString.lowercased()
    ) -> CapsuleSiteDraft {
        CapsuleSiteDraft(
            publicationID: publicationID,
            address: "noct://quiet-garden/",
            title: "Quiet Garden",
            subtitle: "A native Noctweb publication",
            body: "Verified structured content.",
            accentHex: "#4f8f77"
        )
    }

    func testRelayTopologyHasExactlyTheThreeRolesAndModules() throws {
        let topology = RelayTopology.labDefault
        XCTAssertEqual(Set(topology.nodes.map(\.role)), Set(RelayRole.allCases))
        XCTAssertEqual(RelayRole.standard.module.rawValue, "nw.opaque-route@2")
        XCTAssertEqual(
            RelayRole.passthrough.module.rawValue,
            "nw.net-passthrough@1"
        )
        XCTAssertEqual(RelayRole.host.module.rawValue, "nw.net-host@1")
    }

    func testPublishAndResolveThroughDirectAndPassthroughRoutes() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let publication = try await engine.publish(
            draft: draft(),
            at: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(publication.hostRelayIDs.count, 2)

        let direct = try await engine.resolve(
            address: publication.object.address,
            preference: .direct
        )
        XCTAssertTrue(direct.evidence.integrity.verified)
        XCTAssertTrue(direct.evidence.publisher.signatureValid)
        XCTAssertTrue(direct.evidence.publisher.identityBound)
        XCTAssertTrue(direct.evidence.finality.finalized)
        guard case .direct = direct.route else {
            return XCTFail("expected direct host route")
        }

        let passthrough = try await engine.resolve(
            address: publication.object.address,
            preference: .passthrough
        )
        guard case .passthrough = passthrough.route else {
            return XCTFail("expected bounded passthrough route")
        }
    }

    func testHostFailoverUsesSecondReplica() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let publication = try await engine.publish(draft: draft())
        try await engine.setRelayOnline(false, relayID: "host-lisbon")

        let result = try await engine.resolve(
            address: publication.object.address,
            preference: .direct
        )
        XCTAssertEqual(result.route.hostRelayID, "host-salvador")
    }

    func testCorruptedOnlyReplicaFailsClosed() async throws {
        let engine = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        let publication = try await engine.publish(draft: draft())
        try await engine.corruptReplica(
            address: publication.object.address,
            hostRelayID: "host-lisbon"
        )
        try await engine.setRelayOnline(false, relayID: "host-salvador")

        do {
            _ = try await engine.resolve(
                address: publication.object.address,
                preference: .direct
            )
            XCTFail("corrupt bytes must never reach the renderer")
        } catch let error as NoctwebLabError {
            guard case .integrityMismatch = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testTamperedHeadDoesNotVerify() throws {
        let publicationID = UUID().uuidString.lowercased()
        let identity = try PublicationSigningIdentity(
            publicationID: publicationID,
            rawPrivateKey: Data(repeating: 7, count: 32)
        )
        let claims = PublisherHeadClaims(
            publicationID: publicationID,
            address: "noct://quiet-garden/",
            publisherID: identity.publisherID,
            publisherPublicKey: identity.publicKey,
            objectID: "sha256:" + String(repeating: "a", count: 64),
            revision: 1,
            previousHeadID: nil,
            issuedAtMilliseconds: 1_700_000_000_000
        )
        let signature = try identity.sign(headClaims: claims)
        XCTAssertTrue(
            PublicationSigningIdentity.verify(
                signature: signature,
                headClaims: claims
            )
        )

        let tampered = PublisherHeadClaims(
            publicationID: publicationID,
            address: claims.address,
            publisherID: claims.publisherID,
            publisherPublicKey: claims.publisherPublicKey,
            objectID: "sha256:" + String(repeating: "b", count: 64),
            revision: claims.revision,
            previousHeadID: claims.previousHeadID,
            issuedAtMilliseconds: claims.issuedAtMilliseconds
        )
        XCTAssertFalse(
            PublicationSigningIdentity.verify(
                signature: signature,
                headClaims: tampered
            )
        )
    }

    func testExistingPublicationNeverSilentlyRegeneratesMissingKey() async throws {
        let firstStore = InMemoryPublicationPrivateKeyStore()
        let first = try NoctwebLabEngine(identityStore: firstStore)
        let published = try await first.publish(draft: draft())

        let replacement = try NoctwebLabEngine(
            identityStore: InMemoryPublicationPrivateKeyStore()
        )
        do {
            _ = try await replacement.publish(
                draft: CapsuleSiteDraft(
                    publicationID: published.object.publicationID,
                    address: published.object.address,
                    title: published.object.title,
                    subtitle: published.object.subtitle,
                    body: published.object.body,
                    accentHex: published.object.accentHex
                ),
                expectedPublisherID: published.object.publisherID
            )
            XCTFail("missing established identity must block publishing")
        } catch let error as NoctwebLabError {
            XCTAssertEqual(
                error,
                .identityMissing(published.object.publicationID)
            )
        }
    }

    func testWorkspaceRepositoryRoundTripsAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = JSONWorkspaceRepository(
            fileURL: directory.appendingPathComponent("workspace.json")
        )
        let snapshot = WorkspaceSnapshot(
            selectedPublicationID: nil,
            publications: [],
            relays: RelayTopology.labDefault.nodes
        )
        try repository.save(snapshot)
        XCTAssertEqual(try repository.load(), snapshot)
    }
}
