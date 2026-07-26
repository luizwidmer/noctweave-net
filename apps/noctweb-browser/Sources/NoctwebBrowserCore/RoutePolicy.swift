import Foundation

public enum FederationMode: String, Codable, CaseIterable, Hashable, Sendable {
    case solo
    case manual
    case curated
    case open
}

public enum RouteDirective: String, Codable, CaseIterable, Hashable, Sendable {
    case open
    case direct
    case passthrough
}

public enum RoutingAuthority: String, Codable, Hashable, Sendable {
    case federation
    case hostOperator
    case publisher
    case visitor
    case defaultDirect
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

    private enum CodingKeys: String, CodingKey {
        case directive
        case authority
        case federationMode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let directive = try container.decode(
            RouteDirective.self,
            forKey: .directive
        )
        guard directive != .open else {
            throw DecodingError.dataCorruptedError(
                forKey: .directive,
                in: container,
                debugDescription: "a routing decision cannot remain open"
            )
        }
        self.init(
            directive: directive,
            authority: try container.decode(
                RoutingAuthority.self,
                forKey: .authority
            ),
            federationMode: try container.decode(
                FederationMode.self,
                forKey: .federationMode
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(directive, forKey: .directive)
        try container.encode(authority, forKey: .authority)
        try container.encode(federationMode, forKey: .federationMode)
    }
}

public enum RoutingPolicyResolver {
    public static func resolve(
        federationMode: FederationMode,
        federation: RouteDirective,
        hostOperator: RouteDirective,
        publisher: RouteDirective,
        visitor: RouteDirective
    ) -> RoutingDecision {
        let candidates: [(RoutingAuthority, RouteDirective)] = [
            (.federation, federation),
            (.hostOperator, hostOperator),
            (.publisher, publisher),
            (.visitor, visitor),
        ]
        if let selected = candidates.first(where: { $0.1 != .open }) {
            return RoutingDecision(
                directive: selected.1,
                authority: selected.0,
                federationMode: federationMode
            )
        }
        return RoutingDecision(
            directive: .direct,
            authority: .defaultDirect,
            federationMode: federationMode
        )
    }
}
