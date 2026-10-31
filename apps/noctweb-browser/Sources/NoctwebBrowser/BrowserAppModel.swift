import CryptoKit
import Foundation
@preconcurrency import NoctweaveCore
import NoctwebBrowserCore
import enum NoctwebLabCore.NoctwebSecureFileIO
import enum NoctwebLabCore.NoctwebSecureFileIOError
import enum NoctwebLabCore.NoctwebEncryptedLocalData
import enum NoctwebLabCore.NoctwebEncryptedLocalDataError
import class NoctwebLabCore.NoctwebLocalKeyProvider
import SwiftUI
import WebKit

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
    var lastAddress: String
    let relayEndpoint: String?
    let relayProfile: NoctwebNetworkProfile?
}

private struct BrowserNamespaceEpochPin: Codable, Equatable {
    let routingTrustDomainID: String
    let consensusProfileID: String
    let federationMode: String
    let federationName: String?
    let relaySuffix: String
    var epoch: UInt64
    var issuedAt: Date
    var highestRecordSequence: UInt64?
    var recordStatus: String
    var recordBaseDigest: Data?
    var recordDigest: Data?
    var hasActiveIdentityClaim: Bool

    func matches(_ observation: VerifiedNamespaceObservation) -> Bool {
        routingTrustDomainID == observation.profile.routingTrustDomainID
            && consensusProfileID == observation.profile.consensusProfileID
            && federationMode == observation.profile.federationMode.rawValue
            && federationName == observation.profile.namespaceFederationName
            && relaySuffix == observation.relaySuffix
    }
}

private struct BrowserPublicationHeadPin: Codable, Equatable {
    let routingTrustDomainID: String
    let consensusProfileID: String
    let federationMode: String
    let federationName: String?
    let relaySuffix: String
    let siteLabel: String
    var namespaceEpoch: UInt64
    var publisherID: String
    var revision: UInt64
    var headID: String
    var objectID: String

    func matches(_ checkpoint: VerifiedPublicationHead) -> Bool {
        routingTrustDomainID == checkpoint.profile.routingTrustDomainID
            && consensusProfileID == checkpoint.profile.consensusProfileID
            && federationMode == checkpoint.profile.federationMode.rawValue
            && federationName == checkpoint.profile.namespaceFederationName
            && relaySuffix == checkpoint.relaySuffix
            && siteLabel == checkpoint.siteLabel
    }
}

enum BrowserRelayConnectionState: Equatable {
    case notConfigured
    case saved(String)
    case checking
    case connected(String)
    case failed(String)
}

@MainActor
final class BrowserPersistenceStore {
    static let standard = BrowserPersistenceStore(defaults: .standard)

    private let defaults: UserDefaults
    private let key = "net.noctweave.noctweb-browser.state.v1"
    private let namespaceEpochKey = "net.noctweave.noctweb-browser.namespace-checkpoints.v1"
    private let publicationHeadKey = "net.noctweave.noctweb-browser.publication-heads.v1"
    private let keyService: String
    private let keyProvider = NoctwebLocalKeyProvider()

    init(
        defaults: UserDefaults,
        keyService: String = "net.noctweave.noctweb-browser.local-data.v1"
    ) {
        self.defaults = defaults
        self.keyService = keyService
    }

    fileprivate func load() throws -> BrowserPersistentState? {
        guard let stored = defaults.data(forKey: key) else { return nil }
        guard stored.count <= 2 * 1_024 * 1_024 + NoctwebEncryptedLocalData.overheadBytes,
              NoctwebEncryptedLocalData.isSealed(stored) else {
            throw NoctwebEncryptedLocalDataError.malformed
        }
        var data = try NoctwebEncryptedLocalData.open(
            stored,
            using: NoctwebEncryptedLocalData.key(
                service: keyService, provider: keyProvider
            ),
            context: "browser-state-v1"
        )
        defer { data.resetBytes(in: 0..<data.count) }
        let state = try JSONDecoder().decode(BrowserPersistentState.self, from: data)
        let sanitized = sanitizingRestorationAddress(state)
        if sanitized.lastAddress != state.lastAddress {
            try save(sanitized)
        }
        return sanitized
    }

    fileprivate func save(_ state: BrowserPersistentState) throws {
        let state = sanitizingRestorationAddress(state)
        var data = try JSONEncoder().encode(state)
        defer { data.resetBytes(in: 0..<data.count) }
        guard data.count <= 2 * 1_024 * 1_024 else {
            throw NoctwebSecureFileIOError.tooLarge
        }
        let stored = try NoctwebEncryptedLocalData.seal(
            data,
            using: NoctwebEncryptedLocalData.key(
                service: keyService, provider: keyProvider
            ),
            context: "browser-state-v1"
        )
        defaults.set(stored, forKey: key)
    }

    func checkAndAdvanceNamespace(_ observation: VerifiedNamespaceObservation) throws {
        guard observation.epoch > 0,
              observation.issuedAt.timeIntervalSince1970.isFinite,
              observation.recordStatus == "active"
                || observation.recordStatus == "tombstoned"
                || observation.recordStatus == "absent" else {
            throw NoctwebBrowserError.verificationFailed(
                "the namespace has no valid continuity checkpoint"
            )
        }
        var pins: [BrowserNamespaceEpochPin] = try loadPins(
            forKey: namespaceEpochKey,
            context: "browser-namespace-checkpoints-v1"
        )
        guard pins.count <= 4_096, pins.allSatisfy({ $0.epoch > 0 }) else {
            throw NoctwebEncryptedLocalDataError.malformed
        }
        var candidate = BrowserNamespaceEpochPin(
            routingTrustDomainID: observation.profile.routingTrustDomainID,
            consensusProfileID: observation.profile.consensusProfileID,
            federationMode: observation.profile.federationMode.rawValue,
            federationName: observation.profile.namespaceFederationName,
            relaySuffix: observation.relaySuffix,
            epoch: observation.epoch,
            issuedAt: observation.issuedAt,
            highestRecordSequence: observation.recordSequence,
            recordStatus: observation.recordStatus,
            recordBaseDigest: observation.recordBaseDigest,
            recordDigest: observation.recordDigest,
            hasActiveIdentityClaim: observation.hasActiveIdentityClaim
        )
        if let index = pins.firstIndex(where: { $0.matches(observation) }) {
            let prior = pins[index]
            guard candidate.epoch >= prior.epoch,
                  candidate.epoch > prior.epoch
                    || candidate.issuedAt >= prior.issuedAt else {
                throw NoctwebBrowserError.verificationFailed(
                    "the relay returned an older namespace snapshot"
                )
            }
            if let priorSequence = prior.highestRecordSequence,
               let sequence = observation.recordSequence,
               sequence < priorSequence {
                throw NoctwebBrowserError.verificationFailed(
                    "the relay returned an older suffix ownership sequence"
                )
            }
            if prior.recordStatus == "tombstoned",
               candidate.recordStatus != "tombstoned" {
                throw NoctwebBrowserError.verificationFailed(
                    "the relay attempted to restore a released suffix"
                )
            }
            if prior.recordStatus == "absent",
               candidate.recordStatus == "active" {
                let lacksNewOwnershipSequence = prior.highestRecordSequence.map { priorSequence in
                    observation.recordSequence.map { $0 <= priorSequence } ?? true
                } ?? false
                let sameIssuance = candidate.epoch == prior.epoch
                    && candidate.issuedAt == prior.issuedAt
                guard !lacksNewOwnershipSequence && !sameIssuance else {
                    throw NoctwebBrowserError.verificationFailed(
                        "the relay returned conflicting suffix ownership"
                    )
                }
            }
            if prior.recordStatus == "active",
               candidate.recordStatus == "active",
               observation.recordSequence == prior.highestRecordSequence,
               candidate.recordDigest != prior.recordDigest {
                guard candidate.recordBaseDigest == prior.recordBaseDigest,
                      prior.hasActiveIdentityClaim,
                      !candidate.hasActiveIdentityClaim else {
                    throw NoctwebBrowserError.verificationFailed(
                        "the relay returned conflicting suffix ownership at one sequence"
                    )
                }
            }
            if prior.recordStatus == "active",
               candidate.recordStatus == "tombstoned",
               observation.recordSequence == prior.highestRecordSequence {
                throw NoctwebBrowserError.verificationFailed(
                    "the release did not advance the suffix ownership sequence"
                )
            }
            if prior.recordStatus == "tombstoned",
               candidate.recordStatus == "tombstoned",
               observation.recordSequence == prior.highestRecordSequence,
               candidate.recordDigest != prior.recordDigest {
                throw NoctwebBrowserError.verificationFailed(
                    "the relay returned conflicting releases at one sequence"
                )
            }
            candidate.highestRecordSequence = [
                prior.highestRecordSequence, observation.recordSequence
            ].compactMap { $0 }.max()
            candidate.issuedAt = max(prior.issuedAt, candidate.issuedAt)
            if candidate == prior { return }
            pins[index] = candidate
        } else {
            guard pins.count < 4_096 else {
                throw NoctwebBrowserError.verificationFailed(
                    "the namespace checkpoint limit has been reached"
                )
            }
            pins.append(candidate)
        }
        try savePins(
            pins,
            forKey: namespaceEpochKey,
            context: "browser-namespace-checkpoints-v1"
        )
    }

    func checkAndAdvancePublicationHead(
        _ checkpoint: VerifiedPublicationHead
    ) throws {
        guard checkpoint.revision > 0 else {
            throw NoctwebBrowserError.verificationFailed(
                "the publication has no valid revision checkpoint"
            )
        }
        var pins: [BrowserPublicationHeadPin] = try loadPins(
            forKey: publicationHeadKey,
            context: "browser-publication-heads-v1"
        )
        guard pins.count <= 4_096,
              pins.allSatisfy({ $0.revision > 0 }) else {
            throw NoctwebEncryptedLocalDataError.malformed
        }
        let candidate = BrowserPublicationHeadPin(
            routingTrustDomainID: checkpoint.profile.routingTrustDomainID,
            consensusProfileID: checkpoint.profile.consensusProfileID,
            federationMode: checkpoint.profile.federationMode.rawValue,
            federationName: checkpoint.profile.namespaceFederationName,
            relaySuffix: checkpoint.relaySuffix,
            siteLabel: checkpoint.siteLabel,
            namespaceEpoch: checkpoint.namespaceEpoch,
            publisherID: checkpoint.publisherID,
            revision: checkpoint.revision,
            headID: checkpoint.headID,
            objectID: checkpoint.objectID
        )
        if let index = pins.firstIndex(where: { $0.matches(checkpoint) }) {
            let prior = pins[index]
            guard candidate.namespaceEpoch >= prior.namespaceEpoch else {
                throw NoctwebBrowserError.verificationFailed(
                    "the publication belongs to an older namespace epoch"
                )
            }
            if candidate.namespaceEpoch == prior.namespaceEpoch,
               candidate.publisherID != prior.publisherID {
                throw NoctwebBrowserError.verificationFailed(
                    "the site publisher changed without a newer namespace epoch"
                )
            }
            if candidate.publisherID == prior.publisherID {
                guard candidate.revision >= prior.revision else {
                    throw NoctwebBrowserError.verificationFailed(
                        "the relay returned an older publication revision"
                    )
                }
                if candidate.revision == prior.revision,
                   (candidate.headID != prior.headID
                       || candidate.objectID != prior.objectID) {
                    throw NoctwebBrowserError.verificationFailed(
                        "the publisher signed conflicting heads at one revision"
                    )
                }
            }
            if candidate == prior { return }
            pins[index] = candidate
        } else {
            guard pins.count < 4_096 else {
                throw NoctwebBrowserError.verificationFailed(
                    "the publication checkpoint limit has been reached"
                )
            }
            pins.append(candidate)
        }
        try savePins(
            pins,
            forKey: publicationHeadKey,
            context: "browser-publication-heads-v1"
        )
    }

    func requireCurrentCheckpoints(
        for site: VerifiedNoctwebSite,
        profile: NoctwebNetworkProfile
    ) throws {
        guard let suffix = NoctwebRelaySuffixV1(
            rawValue: ".\(site.navigationURL.relaySuffix)"
        ) else {
            throw NoctwebBrowserError.verificationFailed(
                "the site has no valid namespace suffix"
            )
        }
        if site.evidence.epoch > 0 {
            let epochs: [BrowserNamespaceEpochPin] = try loadPins(
                forKey: namespaceEpochKey,
                context: "browser-namespace-checkpoints-v1"
            )
            guard let current = epochs.first(where: {
                $0.routingTrustDomainID == profile.routingTrustDomainID
                    && $0.consensusProfileID == profile.consensusProfileID
                    && $0.federationMode == profile.federationMode.rawValue
                    && $0.federationName == profile.namespaceFederationName
                    && $0.relaySuffix == suffix.rawValue
            }), current.epoch == site.evidence.epoch,
                current.recordStatus == "active",
                current.hasActiveIdentityClaim,
                current.highestRecordSequence == site.evidence.namespaceRecordSequence,
                current.recordDigest == site.evidence.namespaceRecordDigest else {
                throw NoctwebBrowserError.verificationFailed(
                    "the namespace advanced before this page could render"
                )
            }
        }
        let heads: [BrowserPublicationHeadPin] = try loadPins(
            forKey: publicationHeadKey,
            context: "browser-publication-heads-v1"
        )
        guard let current = heads.first(where: {
            $0.routingTrustDomainID == profile.routingTrustDomainID
                && $0.consensusProfileID == profile.consensusProfileID
                && $0.federationMode == profile.federationMode.rawValue
                && $0.federationName == profile.namespaceFederationName
                && $0.relaySuffix == suffix.rawValue
                && $0.siteLabel == site.navigationURL.siteLabel
        }), current.namespaceEpoch == site.evidence.epoch,
            current.publisherID == site.evidence.publisherID,
            current.headID == site.evidence.headID,
            current.objectID == site.evidence.objectID else {
            throw NoctwebBrowserError.verificationFailed(
                "the publication advanced before this page could render"
            )
        }
    }

    private func loadPins<Pin: Decodable>(
        forKey storageKey: String,
        context: String
    ) throws -> [Pin] {
        guard let stored = defaults.data(forKey: storageKey) else { return [] }
        guard stored.count <= 2 * 1_024 * 1_024 + NoctwebEncryptedLocalData.overheadBytes,
              NoctwebEncryptedLocalData.isSealed(stored) else {
            throw NoctwebEncryptedLocalDataError.malformed
        }
        var clear = try NoctwebEncryptedLocalData.open(
            stored,
            using: NoctwebEncryptedLocalData.key(
                service: keyService, provider: keyProvider
            ),
            context: context
        )
        defer { clear.resetBytes(in: 0..<clear.count) }
        return try JSONDecoder().decode([Pin].self, from: clear)
    }

    private func savePins<Pin: Encodable>(
        _ pins: [Pin],
        forKey storageKey: String,
        context: String
    ) throws {
        var clear = try JSONEncoder().encode(pins)
        defer { clear.resetBytes(in: 0..<clear.count) }
        guard clear.count <= 2 * 1_024 * 1_024 else {
            throw NoctwebSecureFileIOError.tooLarge
        }
        let sealed = try NoctwebEncryptedLocalData.seal(
            clear,
            using: NoctwebEncryptedLocalData.key(
                service: keyService, provider: keyProvider
            ),
            context: context
        )
        defaults.set(sealed, forKey: storageKey)
        guard defaults.synchronize() else {
            throw NoctwebBrowserError.verificationFailed(
                "the trust checkpoint could not be saved"
            )
        }
    }

    private func sanitizingRestorationAddress(
        _ state: BrowserPersistentState
    ) -> BrowserPersistentState {
        var sanitized = state
        guard let address = try? NoctwebNavigationURL(parsing: state.lastAddress),
              address.percentEncodedQuery == nil,
              address.percentEncodedFragment == nil else {
            sanitized.lastAddress = BrowserAppModel.blankAddress
            return sanitized
        }
        return sanitized
    }

    func purge() throws {
        try keyProvider.destroy(service: keyService)
        if defaults === UserDefaults.standard, let domain = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: domain)
        } else {
            defaults.removeObject(forKey: key)
            defaults.removeObject(forKey: namespaceEpochKey)
            defaults.removeObject(forKey: publicationHeadKey)
        }
    }

    func clearProcessKeyCache() {
        keyProvider.clearProcessCache()
    }
}

@MainActor
final class BrowserAppModel: ObservableObject {
    @Published private(set) var session: NoctwebBrowserSession
    @Published var addressText: String
    @Published var showsSidebar = false
    @Published var showsTrustInspector = false
    @Published var sidebarSection: BrowserSidebarSection = .bookmarks
    @Published var relayEndpointText: String
    @Published private(set) var activeRelayEndpoint: String?
    @Published private(set) var relayConnectionState:
        BrowserRelayConnectionState
    @Published private(set) var sitesByTab: [UUID: VerifiedNoctwebSite] = [:]
    @Published private(set) var errorsByTab: [UUID: String] = [:]
    @Published private(set) var blockedNoticesByTab: [UUID: String] = [:]
    @Published private(set) var reloadTokensByTab: [UUID: UUID] = [:]
    @Published private(set) var visitorDirectiveByTab:
        [UUID: RouteDirective] = [:]

    private let resolver: any NoctwebResolving
    private let persistenceStore: BrowserPersistenceStore
    private let usesDevelopmentFixtures: Bool
    private var resolutionTasksByTab: [UUID: Task<Void, Never>] = [:]
    private var resolutionGenerationByTab: [UUID: UUID] = [:]
    private var backStackByTab: [UUID: [String]] = [:]
    private var forwardStackByTab: [UUID: [String]] = [:]
    private var hasStarted = false
    private var sessionGeneration = UUID()
    @Published private(set) var isResetting = false
    @Published private(set) var storageError: String?

    init(
        persistenceStore: BrowserPersistenceStore = .standard,
        useDevelopmentFixtures: Bool = false,
        resolver: (any NoctwebResolving)? = nil
    ) {
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
        usesDevelopmentFixtures = useDevelopmentFixtures

        let persisted: BrowserPersistentState?
        do {
            persisted = try persistenceStore.load()
        } catch {
            persisted = nil
            storageError = "Saved browser data could not be opened. This prerelease build requires an encrypted state; review or remove the old browser preference in macOS settings before continuing."
        }
        let profile: NoctwebNetworkProfile
        let initialAddress: String
        if useDevelopmentFixtures {
            self.resolver = resolver ?? DevelopmentNoctwebResolver(
                fixtureResolver: environment.resolver,
                checkNamespace: { observation in
                    try await persistenceStore.checkAndAdvanceNamespace(
                        observation
                    )
                },
                checkPublicationHead: { checkpoint in
                    try await persistenceStore.checkAndAdvancePublicationHead(
                        checkpoint
                    )
                }
            )
            profile = environment.profile
            if let value = persisted?.lastAddress,
               (try? NoctwebNavigationURL(parsing: value)) != nil {
                initialAddress = value
            } else {
                initialAddress = environment.welcomeURL.canonicalString
            }
            relayEndpointText = ""
            activeRelayEndpoint = nil
            relayConnectionState = .connected(
                environment.profile.displayName
            )
        } else {
            self.resolver = resolver ?? FederatedNoctwebResolver(
                checkNamespace: { observation in
                    try await persistenceStore.checkAndAdvanceNamespace(
                        observation
                    )
                },
                checkPublicationHead: { checkpoint in
                    try await persistenceStore.checkAndAdvancePublicationHead(
                        checkpoint
                    )
                }
            )
            profile = persisted?.relayProfile
                ?? Self.unconfiguredProfile()
            let savedEndpoint = persisted?.relayEndpoint
            relayEndpointText = savedEndpoint ?? ""
            activeRelayEndpoint = savedEndpoint
            relayConnectionState = persisted?.relayProfile.map {
                .saved($0.displayName)
            } ?? .notConfigured
            if persisted?.relayProfile != nil,
               let value = persisted?.lastAddress,
               value != Self.blankAddress,
               (try? NoctwebNavigationURL(parsing: value)) != nil {
                initialAddress = value
            } else {
                initialAddress = Self.blankAddress
            }
        }

        do {
            session = try NoctwebBrowserSession(
                profiles: [profile],
                selectedProfileID: profile.id,
                initialAddress: initialAddress
            )
        } catch {
            preconditionFailure("The built-in Noctweb browser session is invalid: \(error)")
        }
        addressText = initialAddress == Self.blankAddress ? "" : initialAddress
        if let persisted {
            session.restorePersistentState(
                bookmarks: persisted.bookmarks,
                history: persisted.history
            )
        }
        showsSidebar = !session.bookmarks.isEmpty || !session.history.isEmpty
        visitorDirectiveByTab[session.selectedTabID] =
            profile.defaultVisitorDirective
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

    var relayIsConfigured: Bool {
        usesDevelopmentFixtures
            || (
                activeRelayEndpoint != nil
                    && !selectedProfile.bootstrapEndpoints.isEmpty
                    && !selectedProfile.namespaceSigners.isEmpty
            )
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
        guard storageError == nil else { return }
        guard !hasStarted else { return }
        hasStarted = true
        if usesDevelopmentFixtures {
            navigate(to: addressText, pushCurrentAddress: false)
            return
        }
        guard relayIsConfigured else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.connectRelay(
                navigateAfterConnection:
                    !self.addressText.isEmpty
            )
        }
    }

    func clearProcessKeyCache() {
        persistenceStore.clearProcessKeyCache()
    }

    func navigateFromAddressBar() {
        navigate(
            to: addressText,
            pushCurrentAddress: true,
            normalizeUserInput: true
        )
    }

    func navigate(
        to rawAddress: String,
        pushCurrentAddress: Bool = true,
        normalizeUserInput: Bool = false
    ) {
        guard !isResetting, storageError == nil else { return }
        guard relayIsConfigured else {
            failSelectedTab(
                NoctwebBrowserError.blocked(
                    "choose and verify a relay before opening Noctweb addresses"
                )
            )
            return
        }
        let parsed: NoctwebNavigationURL
        do {
            let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            parsed = normalizeUserInput
                ? try NoctwebNavigationURL(userInput: trimmed)
                : try NoctwebNavigationURL(parsing: trimmed)
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
        if parsed.canonicalString == Self.blankAddress {
            resolutionTasksByTab[tabID]?.cancel()
            resolutionTasksByTab[tabID] = nil
            resolutionGenerationByTab[tabID] = nil
            sitesByTab[tabID] = nil
            errorsByTab[tabID] = nil
            blockedNoticesByTab[tabID] = nil
            reloadTokensByTab[tabID] = nil
            try? session.updateTab(
                id: tabID,
                address: Self.blankAddress,
                title: "New Tab",
                state: .idle
            )
            addressText = ""
            showsTrustInspector = false
            persist()
            return
        }
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
        guard !isResetting else { return }
        guard selectedTab.verificationState != .resolving else { return }
        navigate(to: selectedTab.address, pushCurrentAddress: false)
    }

    func stop() {
        guard !isResetting else { return }
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
        guard !isResetting else { return }
        let tabID = session.selectedTabID
        guard var stack = backStackByTab[tabID], let target = stack.popLast() else {
            return
        }
        backStackByTab[tabID] = stack
        append(session.selectedTab.address, to: &forwardStackByTab, for: tabID)
        navigate(to: target, pushCurrentAddress: false)
    }

    func goForward() {
        guard !isResetting else { return }
        let tabID = session.selectedTabID
        guard var stack = forwardStackByTab[tabID], let target = stack.popLast() else {
            return
        }
        forwardStackByTab[tabID] = stack
        append(session.selectedTab.address, to: &backStackByTab, for: tabID)
        navigate(to: target, pushCurrentAddress: false)
    }

    func addTab() {
        guard !isResetting else { return }
        do {
            let address = Self.blankAddress
            let tabID = try session.addTab(address: address)
            visitorDirectiveByTab[tabID] =
                selectedProfile.defaultVisitorDirective
            addressText = ""
            showsTrustInspector = false
            reloadTokensByTab[tabID] = UUID()
            if relayIsConfigured {
                try? session.updateTab(
                    id: tabID,
                    address: address,
                    title: "New Tab",
                    state: .idle
                )
            }
        } catch {
            failSelectedTab(error)
        }
    }

    func connectRelay(
        navigateAfterConnection: Bool = false
    ) async {
        guard !usesDevelopmentFixtures, !isResetting, storageError == nil else { return }
        sessionGeneration = UUID()
        let generation = sessionGeneration
        let requested = relayEndpointText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        relayConnectionState = .checking
        do {
            let endpoint = try RelayEndpointParser.parse(requested)
            let canonicalEndpoint = try Self.canonicalEndpointString(endpoint)
            let response = try await RelayClient(endpoint: endpoint)
                .send(.info(), timeout: 8)
            guard generation == sessionGeneration, !isResetting else { return }
            guard response.status == .success,
                  case .relayInfo(let info)? = response.successBody,
                  try info.isStructurallyValidThrowing,
                  let identity = info.relayIdentity,
                  try identity.verifyThrowing(at: info.advertisedAt) else {
                throw NoctwebBrowserError.verificationFailed(
                    "the relay did not return a valid signed identity"
                )
            }
            let providesHosting =
                info.protocolCapabilities?.supports(
                    module: "nw.net-host",
                    version: 1
                ) == true
            let providesFederatedRetrieval =
                info.protocolCapabilities?.supports(
                    module: "nw.federation-forward",
                    version: 1
                ) == true
            guard providesHosting
                    || (
                        info.federation.mode != .solo
                            && providesFederatedRetrieval
                    ) else {
                throw NoctwebBrowserError.blocked(
                    "this relay does not advertise Noctweb hosting or federated retrieval"
                )
            }

            if canonicalEndpoint == activeRelayEndpoint,
               let pinned = selectedProfile.namespaceSigners.first,
               (
                   pinned.relayID != identity.claim.relayID.rawValue
                       || pinned.signingPublicKey
                           != identity.claim.signingPublicKey
               ) {
                throw NoctwebBrowserError.verificationFailed(
                    "the relay identity changed; forget the saved relay before trusting a replacement"
                )
            }

            let profile = try Self.makeRelayProfile(
                endpoint: endpoint,
                info: info
            )
            let priorAddress = addressText
            let profileChanged = profile != selectedProfile
            try session.replaceProfile(
                profile,
                replacing: selectedProfile.id
            )
            if profileChanged {
                invalidateRelayTabs()
            }
            activeRelayEndpoint = canonicalEndpoint
            relayEndpointText = canonicalEndpoint
            relayConnectionState = .connected(profile.displayName)
            visitorDirectiveByTab[session.selectedTabID] =
                profile.defaultVisitorDirective
            errorsByTab[session.selectedTabID] = nil
            persist()

            if navigateAfterConnection,
               !priorAddress.isEmpty {
                navigate(
                    to: priorAddress,
                    pushCurrentAddress: false
                )
            }
        } catch {
            guard generation == sessionGeneration, !isResetting else { return }
            let message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            relayConnectionState = .failed(message)
        }
    }

    func forgetRelay() {
        guard !usesDevelopmentFixtures else { return }
        invalidateRelayTabs()
        let profile = Self.unconfiguredProfile()
        try? session.replaceProfile(
            profile,
            replacing: selectedProfile.id
        )
        activeRelayEndpoint = nil
        relayEndpointText = ""
        relayConnectionState = .notConfigured
        addressText = ""
        showsTrustInspector = false
        persist()
    }

    private func invalidateRelayTabs() {
        // Every tab uses the selected relay profile. Replacing or revoking
        // that authority invalidates every rendered page and pending lookup.
        sessionGeneration = UUID()
        resolutionTasksByTab.values.forEach { $0.cancel() }
        resolutionTasksByTab.removeAll()
        resolutionGenerationByTab.removeAll()
        sitesByTab.removeAll()
        errorsByTab.removeAll()
        blockedNoticesByTab.removeAll()
        reloadTokensByTab.removeAll()
        visitorDirectiveByTab.removeAll()
        backStackByTab.removeAll()
        forwardStackByTab.removeAll()
        for tab in session.tabs {
            try? session.updateTab(
                id: tab.id,
                address: Self.blankAddress,
                title: "New Tab",
                state: .idle
            )
        }
        addressText = ""
        showsTrustInspector = false
    }

    func selectTab(_ id: UUID) {
        guard !isResetting else { return }
        invalidateStaleHostedTabs()
        session.selectTab(id: id)
        addressText = session.selectedTab.address == Self.blankAddress
            ? ""
            : session.selectedTab.address
        if sitesByTab[id] == nil {
            showsTrustInspector = false
        }
        if relayIsConfigured,
           sitesByTab[id] == nil,
           session.selectedTab.address != Self.blankAddress,
           session.selectedTab.verificationState != .resolving {
            navigate(to: session.selectedTab.address, pushCurrentAddress: false)
        }
    }

    func closeTab(_ id: UUID) {
        guard !isResetting else { return }
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
            addressText = session.selectedTab.address == Self.blankAddress
                ? ""
                : session.selectedTab.address
        }
        persist()
    }

    func selectProfile(_ id: String) {
        guard !isResetting else { return }
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
        collapseSidebarIfEmpty()
        persist()
    }

    func removeHistoryEntry(_ entry: NoctwebHistoryEntry) {
        session.removeHistoryEntry(id: entry.id)
        collapseSidebarIfEmpty()
        persist()
    }

    func clearHistory() {
        session.clearHistory()
        collapseSidebarIfEmpty()
        persist()
    }

    func purgeAndReset(clearWebData: @MainActor () async -> Void = {
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        URLCache.shared.removeAllCachedResponses()
    }) async throws {
        guard !isResetting else { return }
        isResetting = true
        defer { isResetting = false }
        sessionGeneration = UUID()
        resolutionTasksByTab.values.forEach { $0.cancel() }
        resolutionTasksByTab.removeAll()
        resolutionGenerationByTab.removeAll()
        try persistenceStore.purge()
        let profile = Self.unconfiguredProfile()
        session = try NoctwebBrowserSession(profiles: [profile], selectedProfileID: profile.id,
                                           initialAddress: Self.blankAddress)
        sitesByTab = [:]; errorsByTab = [:]; blockedNoticesByTab = [:]
        reloadTokensByTab = [:]; visitorDirectiveByTab = [:]
        backStackByTab = [:]; forwardStackByTab = [:]
        activeRelayEndpoint = nil; relayEndpointText = ""; addressText = ""
        relayConnectionState = .notConfigured
        showsSidebar = false; showsTrustInspector = false
        sidebarSection = .bookmarks
        hasStarted = true
        storageError = nil
        await clearWebData()
    }

    func setVisitorDirective(_ directive: RouteDirective) {
        guard !isResetting else { return }
        visitorDirectiveByTab[session.selectedTabID] = directive
        if relayIsConfigured {
            reload()
        }
    }

    func toggleSidebar() {
        guard !isResetting else { return }
        showsSidebar.toggle()
        if showsSidebar {
            showsTrustInspector = false
        }
    }

    func toggleTrustInspector() {
        guard !isResetting else { return }
        showsTrustInspector.toggle()
        if showsTrustInspector {
            showsSidebar = false
        }
    }

    func handleOpenURL(_ url: URL) {
        guard !isResetting else { return }
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
            let data = try NoctwebSecureFileIO.read(
                from: fileURL,
                maximumBytes: NoctwebAccessDescriptor.maximumEncodedBytes
            )
            let descriptor = try NoctwebAccessDescriptor.decodeExactJSON(
                data
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
                self?.invalidateStaleHostedTabs()
                guard !Task.isCancelled else { return }
                self?.completeResolution(
                    site,
                    tabID: tabID,
                    profileID: profile.id,
                    generation: generation
                )
            } catch {
                self?.invalidateStaleHostedTabs()
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
        guard resolutionGenerationByTab[tabID] == generation,
              let tab = session.tabs.first(where: { $0.id == tabID }),
              tab.profileID == profileID,
              let profile = session.profiles.first(where: { $0.id == profileID }),
              profile.routingTrustDomainID == site.evidence.routingTrustDomainID else { return }
        if site.state == .hostedPreview,
           !usesDevelopmentFixtures,
           site.evidence.consensusProfileID != profile.consensusProfileID {
            completeFailure(
                NoctwebBrowserError.verificationFailed(
                    "the namespace policy changed before this page could render"
                ),
                tabID: tabID,
                generation: generation
            )
            return
        }
        if site.state == .hostedPreview,
           site.evidence.consensusProfileID == profile.consensusProfileID {
            do {
                try persistenceStore.requireCurrentCheckpoints(
                    for: site, profile: profile
                )
            } catch {
                completeFailure(error, tabID: tabID, generation: generation)
                return
            }
        }
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
        invalidateStaleHostedTabs()
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
                Self.blankAddress,
            title: "Unable to open",
            state: .failed
        )
        invalidateStaleHostedTabs()
    }

    private func invalidateStaleHostedTabs() {
        for (tabID, site) in Array(sitesByTab) where site.state == .hostedPreview {
            guard let tab = session.tabs.first(where: { $0.id == tabID }),
                  let profile = session.profiles.first(where: { $0.id == tab.profileID }) else {
                markHostedTabStale(tabID)
                continue
            }
            if site.evidence.routingTrustDomainID != profile.routingTrustDomainID
                || (!usesDevelopmentFixtures
                    && site.evidence.consensusProfileID != profile.consensusProfileID) {
                markHostedTabStale(tabID)
                continue
            }
            guard site.evidence.consensusProfileID == profile.consensusProfileID else {
                continue
            }
            do {
                try persistenceStore.requireCurrentCheckpoints(for: site, profile: profile)
            } catch {
                markHostedTabStale(tabID)
            }
        }
    }

    private func markHostedTabStale(_ tabID: UUID) {
        sitesByTab[tabID] = nil
        reloadTokensByTab[tabID] = UUID()
        errorsByTab[tabID] = "A newer signed namespace or publication has made this page stale."
        try? session.updateTab(
            id: tabID,
            address: session.tabs.first(where: { $0.id == tabID })?.address
                ?? Self.blankAddress,
            title: "Stale page",
            state: .stale
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
        guard !isResetting, storageError == nil else { return }
        do {
        try persistenceStore.save(
            BrowserPersistentState(
                bookmarks: session.bookmarks,
                history: session.history,
                lastProfileID: selectedProfile.id,
                lastAddress: session.selectedTab.address,
                relayEndpoint: activeRelayEndpoint,
                relayProfile: usesDevelopmentFixtures
                    ? nil
                    : (relayIsConfigured ? selectedProfile : nil)
            )
        )
        } catch {
            storageError = "Browser data could not be saved securely. Resolve the local storage error before continuing."
        }
    }

    private func collapseSidebarIfEmpty() {
        if session.bookmarks.isEmpty && session.history.isEmpty {
            showsSidebar = false
        }
    }

    static func makeRelayProfile(
        endpoint: RelayEndpoint,
        info: RelayInfo
    ) throws -> NoctwebNetworkProfile {
        guard try info.isStructurallyValidThrowing,
              let identity = info.relayIdentity,
              try identity.verifyThrowing(at: info.advertisedAt) else {
            throw NoctwebBrowserError.verificationFailed(
                "the relay identity is invalid"
            )
        }
        guard let federationMode = NoctwebBrowserCore.FederationMode(
            rawValue: info.federation.mode.rawValue
        ) else {
            throw NoctwebBrowserError.invalidNetworkProfile(
                "the relay federation mode is unsupported"
            )
        }
        let relayID = identity.claim.relayID.rawValue
        let trustDomainID = relayTrustDomainID(relayID)
        let displayName: String
        if let relayName = info.relayName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !relayName.isEmpty,
           relayName.utf8.count <= 80 {
            displayName = relayName
        } else {
            displayName = endpoint.host
        }
        return try NoctwebNetworkProfile(
            id: Self.relayProfileID,
            displayName: displayName,
            routingTrustDomainID: trustDomainID,
            consensusProfileID: "noctweb.namespace.v1",
            verificationKey: Data(
                SHA256.hash(data: identity.claim.signingPublicKey)
            ),
            bootstrapEndpoints: [
                try canonicalEndpointURL(endpoint),
            ],
            supportedEpochs: [1],
            federationMode: federationMode,
            namespaceFederationName: info.federation.name,
            federationDirective: .open,
            defaultVisitorDirective: .open,
            namespaceSigners: [
                NoctwebNamespaceSigner(
                    relayID: relayID,
                    signingPublicKey: identity.claim.signingPublicKey
                ),
            ],
            namespaceThreshold: 1
        )
    }

    static func canonicalEndpointString(
        _ endpoint: RelayEndpoint
    ) throws -> String {
        try canonicalEndpointURL(endpoint).absoluteString
    }

    nonisolated static func relayTrustDomainID(_ relayID: String) -> String {
        "sha256:" + String(relayID.dropFirst(4))
    }

    private static func canonicalEndpointURL(
        _ endpoint: RelayEndpoint
    ) throws -> URL {
        var components = URLComponents()
        switch endpoint.transport {
        case .tcp:
            components.scheme = endpoint.useTLS ? "tls" : "tcp"
        case .http:
            components.scheme = endpoint.useTLS ? "https" : "http"
        case .websocket:
            components.scheme = endpoint.useTLS ? "wss" : "ws"
        }
        components.host = endpoint.host
        components.port = Int(endpoint.port)
        guard let url = components.url else {
            throw NoctwebBrowserError.invalidNetworkProfile(
                "the relay endpoint is invalid"
            )
        }
        return url
    }

    private static func unconfiguredProfile() -> NoctwebNetworkProfile {
        do {
            return try NoctwebNetworkProfile(
                id: relayProfileID,
                displayName: "No relay selected",
                routingTrustDomainID:
                    "sha256:" + String(repeating: "0", count: 64),
                consensusProfileID: "noctweb.unconfigured",
                verificationKey: Data(repeating: 0, count: 32),
                bootstrapEndpoints: [],
                supportedEpochs: [1],
                federationMode: .solo,
                federationDirective: .open,
                defaultVisitorDirective: .open
            )
        } catch {
            preconditionFailure(
                "The built-in empty browser profile is invalid: \(error)"
            )
        }
    }

    private static let relayProfileID = "selected-relay"
    fileprivate static let blankAddress = "noct://start.unconfigured/"

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
