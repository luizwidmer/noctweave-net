import Foundation

public enum NoctwebVerificationState:
    String,
    Codable,
    CaseIterable,
    Hashable,
    Sendable
{
    case idle
    case resolving
    case fixtureVerified
    case finalized
    case hostedPreview
    case stale
    case offlineVerifiedCache
    case blocked
    case failed
}

public struct NoctwebVerificationEvidence:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let publisherID: String
    public let routingTrustDomainID: String
    public let consensusProfileID: String
    public let epoch: UInt64
    public let headID: String
    public let objectID: String
    public let route: RoutingDecision
    public let verifiedAt: Date

    public init(
        publisherID: String,
        routingTrustDomainID: String,
        consensusProfileID: String,
        epoch: UInt64,
        headID: String,
        objectID: String,
        route: RoutingDecision,
        verifiedAt: Date
    ) {
        self.publisherID = publisherID
        self.routingTrustDomainID = routingTrustDomainID
        self.consensusProfileID = consensusProfileID
        self.epoch = epoch
        self.headID = headID
        self.objectID = objectID
        self.route = route
        self.verifiedAt = verifiedAt
    }
}

public struct VerifiedNoctwebSite: Equatable, Sendable {
    public let navigationURL: NoctwebNavigationURL
    public let title: String
    public let bundle: NoctwebWebsiteBundle
    public let state: NoctwebVerificationState
    public let evidence: NoctwebVerificationEvidence

    public init(
        navigationURL: NoctwebNavigationURL,
        title: String,
        bundle: NoctwebWebsiteBundle,
        state: NoctwebVerificationState,
        evidence: NoctwebVerificationEvidence
    ) {
        self.navigationURL = navigationURL
        self.title = title
        self.bundle = bundle
        self.state = state
        self.evidence = evidence
    }
}

public struct NoctwebBrowserTab:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public var profileID: String
    public var address: String
    public var title: String
    public var verificationState: NoctwebVerificationState
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        profileID: String,
        address: String,
        title: String = "New Tab",
        verificationState: NoctwebVerificationState = .idle,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.address = address
        self.title = title
        self.verificationState = verificationState
        self.createdAt = createdAt
    }
}

public struct NoctwebBookmark:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public let profileID: String
    public let routingTrustDomainID: String
    public let address: String
    public var title: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        profileID: String,
        routingTrustDomainID: String,
        address: String,
        title: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.profileID = profileID
        self.routingTrustDomainID = routingTrustDomainID
        self.address = address
        self.title = title
        self.createdAt = createdAt
    }
}

public struct NoctwebHistoryEntry:
    Codable,
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public let profileID: String
    public let routingTrustDomainID: String
    public let address: String
    public let title: String
    public let visitedAt: Date
    public let verificationState: NoctwebVerificationState

    public init(
        id: UUID = UUID(),
        profileID: String,
        routingTrustDomainID: String,
        address: String,
        title: String,
        visitedAt: Date = Date(),
        verificationState: NoctwebVerificationState
    ) {
        self.id = id
        self.profileID = profileID
        self.routingTrustDomainID = routingTrustDomainID
        self.address = address
        self.title = title
        self.visitedAt = visitedAt
        self.verificationState = verificationState
    }
}
