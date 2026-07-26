import Foundation
import NoctwebBrowserCore
import SwiftUI

enum BrowserSidebarSection: String, CaseIterable, Identifiable {
    case bookmarks
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bookmarks: "Bookmarks"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .bookmarks: "bookmark"
        case .history: "clock"
        }
    }
}

private struct BrowserPersistentState: Codable {
    let bookmarks: [NoctwebBookmark]
    let history: [NoctwebHistoryEntry]
    let lastProfileID: String
    let lastAddress: String
}

@MainActor
final class BrowserPersistenceStore {
    static let standard = BrowserPersistenceStore(defaults: .standard)

    private let defaults: UserDefaults
    private let key = "net.noctweave.noctweb-browser.state.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    fileprivate func load() -> BrowserPersistentState? {
        guard
            let data = defaults.data(forKey: key),
            data.count <= 2 * 1_024 * 1_024
        else {
            return nil
        }
        return try? JSONDecoder().decode(BrowserPersistentState.self, from: data)
    }

    fileprivate func save(_ state: BrowserPersistentState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}

@MainActor
final class BrowserAppModel: ObservableObject {
    @Published private(set) var session: NoctwebBrowserSession
    @Published var addressText: String
    @Published var showsSidebar = true
    @Published var showsTrustInspector = false
    @Published var sidebarSection: BrowserSidebarSection = .bookmarks
    @Published private(set) var sitesByTab: [UUID: VerifiedNoctwebSite] = [:]
    @Published private(set) var errorsByTab: [UUID: String] = [:]
    @Published private(set) var blockedNoticesByTab: [UUID: String] = [:]
    @Published private(set) var reloadTokensByTab: [UUID: UUID] = [:]
    @Published private(set) var visitorDirectiveByTab:
        [UUID: RouteDirective] = [:]

    private let resolver: any NoctwebResolving
    private let persistenceStore: BrowserPersistenceStore
    private var resolutionTasksByTab: [UUID: Task<Void, Never>] = [:]
    private var resolutionGenerationByTab: [UUID: UUID] = [:]
    private var backStackByTab: [UUID: [String]] = [:]
    private var forwardStackByTab: [UUID: [String]] = [:]
    private var hasStarted = false

    init(persistenceStore: BrowserPersistenceStore = .standard) {
        let environment: (
            profile: NoctwebNetworkProfile,
            resolver: DeterministicNoctwebResolver,
            welcomeURL: NoctwebNavigationURL
        )
        do {
            environment = try DeterministicNoctwebResolver.developmentEnvironment()
        } catch {
            preconditionFailure("The built-in Noctweb development profile is invalid: \(error)")
        }

        self.persistenceStore = persistenceStore
        resolver = environment.resolver

        let persisted = persistenceStore.load()
        let initialProfileID: String
        if persisted?.lastProfileID == environment.profile.id {
            initialProfileID = environment.profile.id
        } else {
            initialProfileID = environment.profile.id
        }
        let initialAddress: String
        if let value = persisted?.lastAddress,
           (try? NoctwebNavigationURL(parsing: value)) != nil {
            initialAddress = value
        } else {
            initialAddress = environment.welcomeURL.canonicalString
        }

        do {
            session = try NoctwebBrowserSession(
                profiles: [environment.profile],
                selectedProfileID: initialProfileID,
                initialAddress: initialAddress
            )
        } catch {
            preconditionFailure("The built-in Noctweb browser session is invalid: \(error)")
        }
        addressText = initialAddress
        if let persisted {
            session.restorePersistentState(
                bookmarks: persisted.bookmarks,
                history: persisted.history
            )
        }
        visitorDirectiveByTab[session.selectedTabID] =
            environment.profile.defaultVisitorDirective
    }

    var selectedTab: NoctwebBrowserTab {
        session.selectedTab
    }

    var selectedProfile: NoctwebNetworkProfile {
        session.selectedProfile
    }

    var selectedSite: VerifiedNoctwebSite? {
        sitesByTab[session.selectedTabID]
    }

    var selectedError: String? {
        errorsByTab[session.selectedTabID]
    }

    var selectedBlockedNotice: String? {
        blockedNoticesByTab[session.selectedTabID]
    }

    var selectedReloadToken: UUID {
        reloadTokensByTab[session.selectedTabID] ?? UUID.zero
    }

    var selectedVisitorDirective: RouteDirective {
        visitorDirectiveByTab[session.selectedTabID] ??
            selectedProfile.defaultVisitorDirective
    }

    var canGoBack: Bool {
        !(backStackByTab[session.selectedTabID] ?? []).isEmpty
    }

    var canGoForward: Bool {
        !(forwardStackByTab[session.selectedTabID] ?? []).isEmpty
    }

    var isSelectedSiteBookmarked: Bool {
        guard let site = selectedSite else { return false }
        return session.bookmarks.contains {
            $0.profileID == selectedProfile.id &&
                $0.address == site.navigationURL.canonicalString
        }
    }

    var canBookmarkSelectedSite: Bool {
        guard let address = selectedSite?.navigationURL else { return false }
        return address.percentEncodedQuery == nil &&
            address.percentEncodedFragment == nil
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        navigate(to: addressText, pushCurrentAddress: false)
    }

    func navigateFromAddressBar() {
        navigate(to: addressText, pushCurrentAddress: true)
    }

    func navigate(
        to rawAddress: String,
        pushCurrentAddress: Bool = true
    ) {
        let parsed: NoctwebNavigationURL
        do {
            parsed = try NoctwebNavigationURL(
                parsing: rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        } catch {
            failSelectedTab(error)
            return
        }

        let tabID = session.selectedTabID
        let priorAddress = session.selectedTab.address
        let profile = selectedProfile
        let visitorDirective = selectedVisitorDirective
        if pushCurrentAddress, priorAddress != parsed.canonicalString {
            append(priorAddress, to: &backStackByTab, for: tabID)
            forwardStackByTab[tabID] = []
        }

        addressText = parsed.canonicalString
        beginResolution(
            tabID: tabID,
            address: parsed.canonicalString,
            profile: profile
        ) { [resolver] in
            try await resolver.resolve(
                parsed,
                profile: profile,
                visitorDirective: visitorDirective
            )
        }
    }

    func reload() {
        guard selectedTab.verificationState != .resolving else { return }
        navigate(to: selectedTab.address, pushCurrentAddress: false)
    }

    func stop() {
        let tabID = session.selectedTabID
        guard session.selectedTab.verificationState == .resolving else { return }
        resolutionTasksByTab[tabID]?.cancel()
        resolutionTasksByTab[tabID] = nil
        resolutionGenerationByTab[tabID] = nil
        errorsByTab[tabID] = "Navigation was stopped."
        try? session.updateTab(
            id: tabID,
            address: session.selectedTab.address,
            title: "Navigation stopped",
            state: .blocked
        )
    }

    func goBack() {
        let tabID = session.selectedTabID
        guard var stack = backStackByTab[tabID], let target = stack.popLast() else {
            return
        }
        backStackByTab[tabID] = stack
        append(session.selectedTab.address, to: &forwardStackByTab, for: tabID)
        navigate(to: target, pushCurrentAddress: false)
    }

    func goForward() {
        let tabID = session.selectedTabID
        guard var stack = forwardStackByTab[tabID], let target = stack.popLast() else {
            return
        }
        forwardStackByTab[tabID] = stack
        append(session.selectedTab.address, to: &backStackByTab, for: tabID)
        navigate(to: target, pushCurrentAddress: false)
    }

    func addTab() {
        do {
            let address = DeterministicNoctwebResolver.welcomeURLString
            let tabID = try session.addTab(address: address)
            visitorDirectiveByTab[tabID] =
                selectedProfile.defaultVisitorDirective
            addressText = address
            reloadTokensByTab[tabID] = UUID()
            navigate(to: address, pushCurrentAddress: false)
        } catch {
            failSelectedTab(error)
        }
    }

    func selectTab(_ id: UUID) {
        session.selectTab(id: id)
        addressText = session.selectedTab.address
        if sitesByTab[id] == nil,
           session.selectedTab.verificationState != .resolving {
            navigate(to: session.selectedTab.address, pushCurrentAddress: false)
        }
    }

    func closeTab(_ id: UUID) {
        let wasSelected = session.selectedTabID == id
        session.closeTab(id: id)
        sitesByTab[id] = nil
        errorsByTab[id] = nil
        blockedNoticesByTab[id] = nil
        reloadTokensByTab[id] = nil
        resolutionGenerationByTab[id] = nil
        resolutionTasksByTab[id]?.cancel()
        resolutionTasksByTab[id] = nil
        backStackByTab[id] = nil
        forwardStackByTab[id] = nil
        visitorDirectiveByTab[id] = nil
        if wasSelected {
            addressText = session.selectedTab.address
        }
        persist()
    }

    func selectProfile(_ id: String) {
        do {
            try session.selectProfile(id: id)
            visitorDirectiveByTab[session.selectedTabID] =
                selectedProfile.defaultVisitorDirective
            navigate(to: session.selectedTab.address, pushCurrentAddress: false)
        } catch {
            failSelectedTab(error)
        }
    }

    func toggleBookmark() {
        guard let site = selectedSite else { return }
        session.toggleBookmark(site)
        persist()
    }

    func openBookmark(_ bookmark: NoctwebBookmark) {
        openSavedAddress(
            bookmark.address,
            profileID: bookmark.profileID
        )
    }

    func openHistoryEntry(_ entry: NoctwebHistoryEntry) {
        openSavedAddress(entry.address, profileID: entry.profileID)
    }

    func removeBookmark(_ bookmark: NoctwebBookmark) {
        session.removeBookmark(id: bookmark.id)
        persist()
    }

    func removeHistoryEntry(_ entry: NoctwebHistoryEntry) {
        session.removeHistoryEntry(id: entry.id)
        persist()
    }

    func clearHistory() {
        session.clearHistory()
        persist()
    }

    func setVisitorDirective(_ directive: RouteDirective) {
        visitorDirectiveByTab[session.selectedTabID] = directive
        reload()
    }

    func toggleSidebar() {
        showsSidebar.toggle()
        if showsSidebar {
            showsTrustInspector = false
        }
    }

    func toggleTrustInspector() {
        showsTrustInspector.toggle()
        if showsTrustInspector {
            showsSidebar = false
        }
    }

    func handleOpenURL(_ url: URL) {
        hasStarted = true
        if url.scheme?.lowercased() == "noct" {
            navigate(to: url.absoluteString)
            return
        }
        guard
            url.isFileURL,
            url.pathExtension.lowercased() == "noctlink"
        else {
            failSelectedTab(
                NoctwebBrowserError.blocked(
                    "only noct:// addresses and .noctlink files are accepted"
                )
            )
            return
        }
        openAccessDescriptor(at: url)
    }

    func handleWebsiteNavigation(_ url: URL, tabID: UUID) {
        guard
            session.selectedTabID == tabID,
            url.scheme?.lowercased() == "noct"
        else {
            return
        }
        navigate(to: url.absoluteString)
    }

    func handleBlockedWebsiteNavigation(_ url: URL, tabID: UUID) {
        guard session.selectedTabID == tabID else { return }
        blockedNoticesByTab[tabID] =
            "External navigation blocked: \(url.absoluteString)"
    }

    func dismissBlockedNavigationNotice() {
        blockedNoticesByTab[session.selectedTabID] = nil
    }

    func handleRenderedNavigation(
        _ rendererURL: URL,
        publication: VerifiedNoctwebSite,
        tabID: UUID
    ) {
        guard
            session.selectedTabID == tabID,
            let current = sitesByTab[tabID],
            current.evidence.publisherID == publication.evidence.publisherID,
            current.evidence.headID == publication.evidence.headID,
            current.evidence.objectID == publication.evidence.objectID,
            let components = URLComponents(
                url: rendererURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return
        }
        let updatedURL: NoctwebNavigationURL
        do {
            updatedURL = try NoctwebNavigationURL(
                siteLabel: current.navigationURL.siteLabel,
                relaySuffix: current.navigationURL.relaySuffix,
                percentEncodedPath: components.percentEncodedPath.isEmpty
                    ? "/"
                    : components.percentEncodedPath,
                percentEncodedQuery: components.percentEncodedQuery,
                percentEncodedFragment: components.percentEncodedFragment
            )
        } catch {
            return
        }
        guard updatedURL.canonicalString != current.navigationURL.canonicalString
        else {
            return
        }
        append(
            current.navigationURL.canonicalString,
            to: &backStackByTab,
            for: tabID
        )
        forwardStackByTab[tabID] = []
        let updatedSite = VerifiedNoctwebSite(
            navigationURL: updatedURL,
            title: current.title,
            bundle: current.bundle,
            state: current.state,
            evidence: current.evidence
        )
        sitesByTab[tabID] = updatedSite
        addressText = updatedURL.canonicalString
        try? session.updateTab(
            id: tabID,
            address: updatedURL.canonicalString,
            title: current.title,
            state: current.state
        )
        session.recordVisit(updatedSite, profileID: selectedProfile.id)
        persist()
    }

    func flushPersistence() {
        persist()
    }

    private func openSavedAddress(_ address: String, profileID: String) {
        do {
            try session.selectProfile(id: profileID)
            navigate(to: address)
        } catch {
            failSelectedTab(error)
        }
    }

    private func openAccessDescriptor(at fileURL: URL) {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
            guard
                let fileSize = values.fileSize,
                fileSize > 0,
                fileSize <= NoctwebAccessDescriptor.maximumEncodedBytes
            else {
                throw NoctwebBrowserError.invalidAccessDescriptor(
                    "descriptor size is invalid"
                )
            }
            let descriptor = try NoctwebAccessDescriptor.decodeExactJSON(
                Data(contentsOf: fileURL, options: [.mappedIfSafe])
            )
            let matches = session.profiles.filter {
                $0.routingTrustDomainID == descriptor.routingTrustDomainID
            }
            guard matches.count == 1, let profile = matches.first else {
                if matches.isEmpty {
                    throw NoctwebBrowserError.profileNotFound(
                        descriptor.routingTrustDomainID
                    )
                }
                throw NoctwebBrowserError.ambiguousTrustDomain(
                    descriptor.routingTrustDomainID
                )
            }
            try session.selectProfile(id: profile.id)
            addressText = descriptor.navigationURL.canonicalString
            let tabID = session.selectedTabID
            let visitorDirective = selectedVisitorDirective
            beginResolution(
                tabID: tabID,
                address: descriptor.navigationURL.canonicalString,
                profile: profile
            ) { [resolver] in
                try await resolver.resolve(
                    descriptor,
                    profile: profile,
                    visitorDirective: visitorDirective
                )
            }
        } catch {
            failSelectedTab(error)
        }
    }

    private func beginResolution(
        tabID: UUID,
        address: String,
        profile: NoctwebNetworkProfile,
        operation: @escaping @Sendable () async throws -> VerifiedNoctwebSite
    ) {
        resolutionTasksByTab[tabID]?.cancel()
        let generation = UUID()
        resolutionGenerationByTab[tabID] = generation
        sitesByTab[tabID] = nil
        errorsByTab[tabID] = nil
        blockedNoticesByTab[tabID] = nil
        do {
            try session.updateTab(
                id: tabID,
                address: address,
                title: "Resolving…",
                state: .resolving
            )
        } catch {
            failSelectedTab(error)
            return
        }

        let task = Task { [weak self] in
            do {
                let site = try await operation()
                guard !Task.isCancelled else { return }
                self?.completeResolution(
                    site,
                    tabID: tabID,
                    profileID: profile.id,
                    generation: generation
                )
            } catch {
                guard !Task.isCancelled else { return }
                self?.completeFailure(
                    error,
                    tabID: tabID,
                    generation: generation
                )
            }
        }
        resolutionTasksByTab[tabID] = task
    }

    private func completeResolution(
        _ site: VerifiedNoctwebSite,
        tabID: UUID,
        profileID: String,
        generation: UUID
    ) {
        guard resolutionGenerationByTab[tabID] == generation else { return }
        resolutionTasksByTab[tabID] = nil
        resolutionGenerationByTab[tabID] = nil
        sitesByTab[tabID] = site
        errorsByTab[tabID] = nil
        reloadTokensByTab[tabID] = UUID()
        try? session.updateTab(
            id: tabID,
            address: site.navigationURL.canonicalString,
            title: site.title,
            state: site.state
        )
        session.recordVisit(site, profileID: profileID)
        if session.selectedTabID == tabID {
            addressText = site.navigationURL.canonicalString
        }
        persist()
    }

    private func completeFailure(
        _ error: Error,
        tabID: UUID,
        generation: UUID
    ) {
        guard resolutionGenerationByTab[tabID] == generation else { return }
        resolutionTasksByTab[tabID] = nil
        resolutionGenerationByTab[tabID] = nil
        let message = (error as? LocalizedError)?.errorDescription ??
            error.localizedDescription
        sitesByTab[tabID] = nil
        errorsByTab[tabID] = message
        try? session.updateTab(
            id: tabID,
            address: session.tabs.first(where: { $0.id == tabID })?.address ??
                DeterministicNoctwebResolver.welcomeURLString,
            title: "Unable to open",
            state: .failed
        )
    }

    private func failSelectedTab(_ error: Error) {
        let tabID = session.selectedTabID
        resolutionTasksByTab[tabID]?.cancel()
        resolutionTasksByTab[tabID] = nil
        resolutionGenerationByTab[tabID] = nil
        let message = (error as? LocalizedError)?.errorDescription ??
            error.localizedDescription
        errorsByTab[tabID] = message
        sitesByTab[tabID] = nil
        try? session.updateSelectedTab(
            address: session.selectedTab.address,
            title: "Unable to open",
            state: .failed
        )
    }

    private func persist() {
        persistenceStore.save(
            BrowserPersistentState(
                bookmarks: session.bookmarks,
                history: session.history,
                lastProfileID: selectedProfile.id,
                lastAddress: session.selectedTab.address
            )
        )
    }

    private func append(
        _ address: String,
        to stacks: inout [UUID: [String]],
        for tabID: UUID
    ) {
        var stack = stacks[tabID] ?? []
        if stack.last != address {
            stack.append(address)
        }
        if stack.count > 100 {
            stack.removeFirst(stack.count - 100)
        }
        stacks[tabID] = stack
    }
}

private extension UUID {
    static let zero = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
}
