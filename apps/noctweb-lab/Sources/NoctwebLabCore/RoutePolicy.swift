import Foundation

/// Noctweave's federation configuration is a routing-policy trust domain,
/// never an additional relay hop or content authority.
public enum FederationMode: String, Codable, CaseIterable, Hashable, Sendable {
    case solo
    case manual
    case curated
    case open
}

/// A hard route choice. `open` delegates to the next authority.
public enum RouteDirective: String, Codable, CaseIterable, Hashable, Sendable {
    case open
    case direct
    case passthrough
}

public enum RoutingAuthority: String, Codable, Hashable, Sendable {
    case federation
    case relayOperator
    case publisher
    case visitor
    case defaultDirect
}

public struct FederationRoutingPolicy:
    Codable, Equatable, Hashable, Sendable
{
    public var mode: FederationMode
    public var directive: RouteDirective

    public init(mode: FederationMode, directive: RouteDirective) {
        self.mode = mode
        self.directive = directive
    }

    public static let soloOpen = FederationRoutingPolicy(
        mode: .solo,
        directive: .open
    )
}

public struct RoutingDecision: Codable, Equatable, Hashable, Sendable {
    public let directive: RouteDirective
    public let authority: RoutingAuthority
    public let federationMode: FederationMode

    public init(
        directive: RouteDirective,
        authority: RoutingAuthority,
        federationMode: FederationMode
    ) {
        precondition(directive != .open)
        self.directive = directive
        self.authority = authority
        self.federationMode = federationMode
    }
}

/// A complete mutable relay-state snapshot applied atomically by the lab.
public struct RelayRuntimeConfiguration: Equatable, Sendable {
    public let relayID: String
    public let advertisedModules: [RelayModule]
    public let operatorRouteDirective: RouteDirective
    public let isOnline: Bool

    public init(
        relayID: String,
        advertisedModules: [RelayModule],
        operatorRouteDirective: RouteDirective,
        isOnline: Bool
    ) {
        self.relayID = relayID
        self.advertisedModules = advertisedModules
        self.operatorRouteDirective = operatorRouteDirective
        self.isOnline = isOnline
    }
}

public enum RoutingPolicyResolver {
    /// The first authority that does not leave the choice open wins.
    /// If every authority delegates, direct retrieval is deterministic.
    public static func resolve(
        federation: FederationRoutingPolicy,
        relayOperator: RouteDirective,
        publisher: RouteDirective,
        visitor: RouteDirective
    ) -> RoutingDecision {
        let candidates: [(RoutingAuthority, RouteDirective)] = [
            (.federation, federation.directive),
            (.relayOperator, relayOperator),
            (.publisher, publisher),
            (.visitor, visitor),
        ]
        if let selected = candidates.first(where: { $0.1 != .open }) {
            return RoutingDecision(
                directive: selected.1,
                authority: selected.0,
                federationMode: federation.mode
            )
        }
        return RoutingDecision(
            directive: .direct,
            authority: .defaultDirect,
            federationMode: federation.mode
        )
    }
}

public extension LabRoute {
    var directive: RouteDirective {
        switch self {
        case .automatic: .open
        case .direct: .direct
        case .passthrough: .passthrough
        }
    }
}

public extension RelayRoute {
    var directive: RouteDirective {
        switch self {
        case .direct: .direct
        case .passthrough: .passthrough
        }
    }
}
