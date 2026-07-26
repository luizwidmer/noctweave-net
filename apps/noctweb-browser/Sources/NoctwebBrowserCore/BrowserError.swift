import Foundation

public enum NoctwebBrowserError: Error, Equatable, Sendable {
    case invalidURL(String)
    case invalidNetworkProfile(String)
    case invalidAccessDescriptor(String)
    case invalidWebsiteBundle(String)
    case profileNotFound(String)
    case ambiguousTrustDomain(String)
    case unresolvedName(String)
    case verificationFailed(String)
    case blocked(String)
    case resourceNotFound(String)
}

extension NoctwebBrowserError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidURL(reason):
            "Invalid Noctweb URL: \(reason)"
        case let .invalidNetworkProfile(reason):
            "Invalid network profile: \(reason)"
        case let .invalidAccessDescriptor(reason):
            "Invalid Noctweb link: \(reason)"
        case let .invalidWebsiteBundle(reason):
            "Invalid website bundle: \(reason)"
        case let .profileNotFound(identifier):
            "No installed network profile can resolve \(identifier)."
        case let .ambiguousTrustDomain(identifier):
            "Multiple network profiles claim \(identifier). Choose a trust domain explicitly."
        case let .unresolvedName(address):
            "No finalized publication was found for \(address)."
        case let .verificationFailed(reason):
            "Noctweb verification failed: \(reason)"
        case let .blocked(reason):
            "Navigation blocked: \(reason)"
        case let .resourceNotFound(path):
            "The verified publication does not contain \(path)."
        }
    }
}
