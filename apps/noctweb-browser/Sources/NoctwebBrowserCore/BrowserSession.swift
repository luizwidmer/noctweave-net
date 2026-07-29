import Foundation

public struct NoctwebBrowserSession: Equatable, Sendable {
    public static let maximumTabs = 32
    public static let maximumHistoryEntries = 2_000
    public static let maximumBookmarks = 1_000

    public private(set) var profiles: [NoctwebNetworkProfile]
    public private(set) var selectedProfileID: String
    public private(set) var tabs: [NoctwebBrowserTab]
    public private(set) var selectedTabID: UUID
    public private(set) var bookmarks: [NoctwebBookmark]
    public private(set) var history: [NoctwebHistoryEntry]

    public init(
        profiles: [NoctwebNetworkProfile],
        selectedProfileID: String,
        initialAddress: String
    ) throws {
        guard
            !profiles.isEmpty,
            profiles.count <= 32,
            Set(profiles.map(\.id)).count == profiles.count,
            profiles.contains(where: { $0.id == selectedProfileID })
        else {
            throw NoctwebBrowserError.invalidNetworkProfile(
                "session profiles must be unique and include the selection"
            )
        }
        _ = try NoctwebNavigationURL(parsing: initialAddress)
        let tab = NoctwebBrowserTab(
            profileID: selectedProfileID,
            address: initialAddress
        )
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
        self.tabs = [tab]
        self.selectedTabID = tab.id
        self.bookmarks = []
        self.history = []
    }

    public var selectedProfile: NoctwebNetworkProfile {
        profiles.first { $0.id == selectedProfileID }!
    }

    public var selectedTab: NoctwebBrowserTab {
        tabs.first { $0.id == selectedTabID }!
    }

    public mutating func selectProfile(id: String) throws {
        guard profiles.contains(where: { $0.id == id }) else {
            throw NoctwebBrowserError.profileNotFound(id)
        }
        selectedProfileID = id
        if let index = tabs.firstIndex(where: { $0.id == selectedTabID }) {
            tabs[index].profileID = id
        }
    }

    public mutating func replaceProfile(
        _ profile: NoctwebNetworkProfile,
        replacing profileID: String
    ) throws {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }),
              profile.id == profileID else {
            throw NoctwebBrowserError.profileNotFound(profileID)
        }
        let savedBookmarks = bookmarks
        let savedHistory = history
        profiles[index] = profile
        restorePersistentState(
            bookmarks: savedBookmarks,
            history: savedHistory
        )
    }

    @discardableResult
    public mutating func addTab(address: String? = nil) throws -> UUID {
        guard tabs.count < Self.maximumTabs else {
            throw NoctwebBrowserError.blocked("the tab limit has been reached")
        }
        let value = address ?? selectedTab.address
        _ = try NoctwebNavigationURL(parsing: value)
        let tab = NoctwebBrowserTab(
            profileID: selectedProfileID,
            address: value
        )
        tabs.append(tab)
        selectedTabID = tab.id
        return tab.id
    }

    public mutating func selectTab(id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
        selectedProfileID = selectedTab.profileID
    }

    public mutating func closeTab(id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        let wasSelected = selectedTabID == id
        tabs.remove(at: index)
        if wasSelected {
            let replacement = tabs[min(index, tabs.count - 1)]
            selectedTabID = replacement.id
            selectedProfileID = replacement.profileID
        }
    }

    public mutating func updateSelectedTab(
        address: String,
        title: String,
        state: NoctwebVerificationState
    ) throws {
        try updateTab(
            id: selectedTabID,
            address: address,
            title: title,
            state: state
        )
    }

    public mutating func updateTab(
        id: UUID,
        address: String,
        title: String,
        state: NoctwebVerificationState
    ) throws {
        _ = try NoctwebNavigationURL(parsing: address)
        guard let index = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        tabs[index].address = address
        tabs[index].title = title
        tabs[index].verificationState = state
    }

    public mutating func recordVisit(
        _ site: VerifiedNoctwebSite,
        profileID: String? = nil
    ) {
        guard Self.isPersistenceEligible(site.navigationURL) else { return }
        let profile = profiles.first {
            $0.id == (profileID ?? selectedProfile.id)
        }
        guard
            let profile,
            profile.routingTrustDomainID ==
                site.evidence.routingTrustDomainID
        else {
            return
        }
        let entry = NoctwebHistoryEntry(
            profileID: profile.id,
            routingTrustDomainID: site.evidence.routingTrustDomainID,
            address: site.navigationURL.canonicalString,
            title: site.title,
            verificationState: site.state
        )
        history.insert(entry, at: 0)
        if history.count > Self.maximumHistoryEntries {
            history.removeLast(history.count - Self.maximumHistoryEntries)
        }
    }

    public mutating func toggleBookmark(_ site: VerifiedNoctwebSite) {
        guard
            Self.isPersistenceEligible(site.navigationURL),
            selectedProfile.routingTrustDomainID ==
                site.evidence.routingTrustDomainID
        else {
            return
        }
        if let index = bookmarks.firstIndex(where: {
            $0.profileID == selectedProfile.id &&
                $0.address == site.navigationURL.canonicalString
        }) {
            bookmarks.remove(at: index)
            return
        }
        guard bookmarks.count < Self.maximumBookmarks else { return }
        bookmarks.insert(
            NoctwebBookmark(
                profileID: selectedProfile.id,
                routingTrustDomainID: site.evidence.routingTrustDomainID,
                address: site.navigationURL.canonicalString,
                title: site.title
            ),
            at: 0
        )
    }

    public mutating func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
    }

    public mutating func removeHistoryEntry(id: UUID) {
        history.removeAll { $0.id == id }
    }

    public mutating func clearHistory() {
        history.removeAll(keepingCapacity: false)
    }

    public mutating func restorePersistentState(
        bookmarks: [NoctwebBookmark],
        history: [NoctwebHistoryEntry]
    ) {
        let profilesByID = Dictionary(
            uniqueKeysWithValues: profiles.map { ($0.id, $0) }
        )
        self.bookmarks = Array(
            bookmarks.lazy.filter { item in
                guard
                    let profile = profilesByID[item.profileID],
                    profile.routingTrustDomainID == item.routingTrustDomainID
                else {
                    return false
                }
                guard
                    let address = try? NoctwebNavigationURL(
                        parsing: item.address
                    )
                else {
                    return false
                }
                return Self.isPersistenceEligible(address)
            }
            .prefix(Self.maximumBookmarks)
        )
        self.history = Array(
            history.lazy.filter { item in
                guard
                    let profile = profilesByID[item.profileID],
                    profile.routingTrustDomainID == item.routingTrustDomainID
                else {
                    return false
                }
                guard
                    let address = try? NoctwebNavigationURL(
                        parsing: item.address
                    )
                else {
                    return false
                }
                return Self.isPersistenceEligible(address)
            }
            .prefix(Self.maximumHistoryEntries)
        )
    }

    private static func isPersistenceEligible(
        _ address: NoctwebNavigationURL
    ) -> Bool {
        address.percentEncodedQuery == nil &&
            address.percentEncodedFragment == nil
    }
}
