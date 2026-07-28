import NoctwebBrowserCore
import NoctwebUI
import SwiftUI

struct BrowserWindowView: View {
    @EnvironmentObject private var model: BrowserAppModel
    @FocusState private var addressFieldIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            browserToolbar
            Divider()
            tabStrip
            Divider()
            HStack(spacing: 0) {
                if model.showsSidebar {
                    BrowserSidebar()
                    Divider()
                }
                browserContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showsTrustInspector {
                    Divider()
                    TrustInspector()
                }
            }
        }
        .frame(minWidth: 780, minHeight: 540)
        .background(NoctwebTheme.canvas)
        .task {
            model.startIfNeeded()
        }
        .onChange(of: model.session.selectedTabID) {
            addressFieldIsFocused = false
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .noctwebFocusAddressField
            )
        ) { _ in
            addressFieldIsFocused = true
        }
    }

    private var browserToolbar: some View {
        HStack(spacing: 7) {
            toolbarButton(
                systemImage: "sidebar.left",
                help: model.showsSidebar ? "Hide sidebar" : "Show sidebar"
            ) { model.toggleSidebar() }

            HStack(spacing: 1) {
                toolbarButton(
                    systemImage: "chevron.left",
                    help: "Back",
                    disabled: !model.canGoBack,
                    action: model.goBack
                )
                toolbarButton(
                    systemImage: "chevron.right",
                    help: "Forward",
                    disabled: !model.canGoForward,
                    action: model.goForward
                )
            }

            HStack(spacing: 8) {
                Button {
                    model.toggleTrustInspector()
                } label: {
                    Image(systemName: verificationSymbol)
                        .foregroundStyle(verificationColor)
                        .frame(width: 17)
                }
                .buttonStyle(.plain)
                .help(verificationLabel)

                TextField(
                    "noct://site.relay/",
                    text: $model.addressText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .focused($addressFieldIsFocused)
                .onSubmit(model.navigateFromAddressBar)

                if model.selectedTab.verificationState == .resolving {
                    Button(action: model.stop) {
                        Image(systemName: "xmark")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("Stop")
                } else {
                    Button(action: model.reload) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Reload")
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(NoctwebTheme.input)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.primary.opacity(0.1))
            }
            .frame(maxWidth: .infinity)

            Menu {
                ForEach(model.session.profiles) { profile in
                    Button {
                        model.selectProfile(profile.id)
                    } label: {
                        if profile.id == model.selectedProfile.id {
                            Label(profile.displayName, systemImage: "checkmark")
                        } else {
                            Text(profile.displayName)
                        }
                    }
                }
                Divider()
                Section("Visitor route preference") {
                    ForEach(RouteDirective.allCases, id: \.self) { directive in
                        Button {
                            model.setVisitorDirective(directive)
                        } label: {
                            if directive == model.selectedVisitorDirective {
                                Label(
                                    visitorDirectiveTitle(directive),
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(visitorDirectiveTitle(directive))
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "network")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(
                "Network: \(model.selectedProfile.displayName) · Visitor route: \(visitorDirectiveTitle(model.selectedVisitorDirective))"
            )

            toolbarButton(
                systemImage: model.isSelectedSiteBookmarked
                    ? "bookmark.fill"
                    : "bookmark",
                help: model.isSelectedSiteBookmarked
                    ? "Remove bookmark"
                    : (
                        model.canBookmarkSelectedSite
                            ? "Bookmark this site"
                            : "Query and fragment addresses stay out of bookmarks"
                    ),
                disabled: !model.canBookmarkSelectedSite,
                action: model.toggleBookmark
            )

            toolbarButton(
                systemImage: "checkmark.shield",
                help: model.showsTrustInspector
                    ? "Hide verification details"
                    : "Show verification details"
            ) { model.toggleTrustInspector() }

            toolbarButton(
                systemImage: "plus",
                help: "New tab",
                action: model.addTab
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(NoctwebTheme.navigation)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(model.session.tabs) { tab in
                    BrowserTabButton(
                        tab: tab,
                        isSelected: tab.id == model.session.selectedTabID,
                        canClose: model.session.tabs.count > 1,
                        select: { model.selectTab(tab.id) },
                        close: { model.closeTab(tab.id) }
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .scrollIndicators(.hidden)
        .background(NoctwebTheme.navigation)
    }

    @ViewBuilder
    private var browserContent: some View {
        switch model.selectedTab.verificationState {
        case .resolving:
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Resolving through \(model.selectedProfile.displayName)")
                    .font(.headline)
                Text("Checking the trust domain, publisher head, bundle digest, and route policy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        case .failed, .blocked:
            ContentUnavailableView {
                Label("Noctweb site unavailable", systemImage: "exclamationmark.shield")
            } description: {
                Text(
                    model.selectedError ??
                        "This address could not be verified by the selected network profile."
                )
            } actions: {
                Button("Try Again", action: model.reload)
            }
        default:
            if let site = model.selectedSite {
                let tabID = model.selectedTab.id
                ZStack(alignment: .top) {
                    VerifiedNoctwebWebsiteView(
                        site: site,
                        reloadToken: model.selectedReloadToken,
                        onNoctNavigation: {
                            model.handleWebsiteNavigation($0, tabID: tabID)
                        },
                        onInternalNavigation: {
                            model.handleRenderedNavigation(
                                $0,
                                publication: site,
                                tabID: tabID
                            )
                        },
                        onBlockedNavigation: {
                            model.handleBlockedWebsiteNavigation(
                                $0,
                                tabID: tabID
                            )
                        }
                    )
                    if let message = model.selectedBlockedNotice {
                        BlockedNavigationBanner(
                            message: message,
                            dismiss: model.dismissBlockedNavigationNotice
                        )
                        .padding(12)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Enter a Noctweb address",
                    systemImage: "network",
                    description: Text(
                        "Open a noct:// address or a trusted .noctlink file."
                    )
                )
            }
        }
    }

    private var verificationSymbol: String {
        switch model.selectedTab.verificationState {
        case .fixtureVerified: "checkmark.seal"
        case .finalized: "checkmark.shield.fill"
        case .hostedPreview: "eye"
        case .offlineVerifiedCache: "checkmark.icloud"
        case .stale: "clock.badge.exclamationmark"
        case .failed, .blocked: "exclamationmark.shield"
        case .resolving: "ellipsis.shield"
        case .idle: "shield"
        }
    }

    private var verificationColor: Color {
        switch model.selectedTab.verificationState {
        case .finalized, .offlineVerifiedCache: .green
        case .fixtureVerified: .indigo
        case .hostedPreview, .stale: .orange
        case .failed, .blocked: .red
        default: .secondary
        }
    }

    private var verificationLabel: String {
        switch model.selectedTab.verificationState {
        case .fixtureVerified: "Development fixture verified"
        case .finalized: "Consensus-finalized publication"
        case .hostedPreview: "Hosted preview"
        case .offlineVerifiedCache: "Verified offline cache"
        case .stale: "Verification is stale"
        case .failed: "Verification failed"
        case .blocked: "Navigation blocked"
        case .resolving: "Resolving"
        case .idle: "Not yet resolved"
        }
    }

    private func toolbarButton(
        systemImage: String,
        help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private func visitorDirectiveTitle(
        _ directive: RouteDirective
    ) -> String {
        switch directive {
        case .open: "Follow higher policy"
        case .direct: "Prefer direct"
        case .passthrough: "Require passthrough"
        }
    }
}

private struct BlockedNavigationBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "network.slash")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.orange.opacity(0.3))
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }
}

private struct BrowserTabButton: View {
    let tab: NoctwebBrowserTab
    let isSelected: Bool
    let canClose: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: stateSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(stateColor)
            Text(tab.title)
                .lineLimit(1)
                .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                .frame(maxWidth: 150, alignment: .leading)
            if canClose {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 15, height: 15)
                }
                .buttonStyle(.plain)
                .help("Close tab")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, canClose ? 6 : 10)
        .frame(height: 27)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isSelected
                        ? Color(nsColor: .controlBackgroundColor)
                        : .clear
                )
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture(perform: select)
        .contextMenu {
            Button("Close Tab", action: close)
                .disabled(!canClose)
        }
    }

    private var stateSymbol: String {
        switch tab.verificationState {
        case .resolving: "ellipsis"
        case .fixtureVerified: "checkmark.seal.fill"
        case .finalized: "checkmark.shield.fill"
        case .failed, .blocked: "exclamationmark.triangle.fill"
        default: "circle.fill"
        }
    }

    private var stateColor: Color {
        switch tab.verificationState {
        case .fixtureVerified: .indigo
        case .finalized, .offlineVerifiedCache: .green
        case .failed, .blocked: .red
        case .hostedPreview, .stale: .orange
        default: .secondary.opacity(0.6)
        }
    }
}

private struct BrowserSidebar: View {
    @EnvironmentObject private var model: BrowserAppModel

    var body: some View {
        VStack(spacing: 0) {
            Picker("Library", selection: $model.sidebarSection) {
                ForEach(BrowserSidebarSection.allCases) { section in
                    Image(systemName: section.systemImage)
                        .tag(section)
                        .help(section.title)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            switch model.sidebarSection {
            case .bookmarks:
                bookmarkList
            case .history:
                historyList
            }
        }
        .frame(width: 230)
        .background(NoctwebTheme.surface)
    }

    @ViewBuilder
    private var bookmarkList: some View {
        if model.session.bookmarks.isEmpty {
            ContentUnavailableView(
                "No Bookmarks",
                systemImage: "bookmark",
                description: Text("Save verified sites from the toolbar.")
            )
            .controlSize(.small)
        } else {
            List {
                ForEach(model.session.bookmarks) { bookmark in
                    LibraryRow(
                        title: bookmark.title,
                        address: bookmark.address,
                        systemImage: "bookmark.fill",
                        open: { model.openBookmark(bookmark) },
                        delete: { model.removeBookmark(bookmark) }
                    )
                }
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var historyList: some View {
        if model.session.history.isEmpty {
            ContentUnavailableView(
                "No History",
                systemImage: "clock",
                description: Text("Verified visits appear here.")
            )
            .controlSize(.small)
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", action: model.clearHistory)
                        .buttonStyle(.plain)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                Divider()
                List {
                    ForEach(model.session.history) { entry in
                        LibraryRow(
                            title: entry.title,
                            address: entry.address,
                            detail: entry.visitedAt.formatted(
                                date: .omitted,
                                time: .shortened
                            ),
                            systemImage: "clock",
                            open: { model.openHistoryEntry(entry) },
                            delete: { model.removeHistoryEntry(entry) }
                        )
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

private struct LibraryRow: View {
    let title: String
    let address: String
    var detail: String?
    let systemImage: String
    let open: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(title)
                                .lineLimit(1)
                            if let detail {
                                Spacer(minLength: 4)
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(address)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .contextMenu {
            Button("Open", action: open)
            Divider()
            Button("Delete", role: .destructive, action: delete)
        }
    }
}

private struct TrustInspector: View {
    @EnvironmentObject private var model: BrowserAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(
                        trustTitle,
                        systemImage: model.selectedSite == nil
                            ? "shield"
                            : "checkmark.shield"
                    )
                    .font(.headline)
                    Spacer()
                    Button {
                        model.showsTrustInspector = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }

                if let site = model.selectedSite {
                    if site.state == .fixtureVerified {
                        InspectorNotice(
                            title: "Development fixture",
                            message: "Cryptographically verified locally, but not claimed as production consensus finalization."
                        )
                    }
                    InspectorSection("Publisher") {
                        InspectorValue(
                            label: "Identity",
                            value: site.evidence.publisherID
                        )
                        InspectorValue(
                            label: "Signed head",
                            value: site.evidence.headID
                        )
                        InspectorValue(
                            label: "Object digest",
                            value: site.evidence.objectID
                        )
                    }
                    InspectorSection("Network") {
                        InspectorValue(
                            label: "Profile",
                            value: model.selectedProfile.displayName
                        )
                        InspectorValue(
                            label: "Trust domain",
                            value: site.evidence.routingTrustDomainID
                        )
                        InspectorValue(
                            label: "Consensus profile",
                            value: site.evidence.consensusProfileID
                        )
                        InspectorValue(
                            label: "Epoch",
                            value: String(site.evidence.epoch)
                        )
                    }
                    InspectorSection("Route") {
                        InspectorValue(
                            label: "Visitor preference",
                            value: model.selectedVisitorDirective.rawValue
                        )
                        InspectorValue(
                            label: "Directive",
                            value: site.evidence.route.directive.rawValue
                        )
                        InspectorValue(
                            label: "Authority",
                            value: site.evidence.route.authority.rawValue
                        )
                        InspectorValue(
                            label: "Federation",
                            value: site.evidence.route.federationMode.rawValue
                        )
                    }
                    Text(
                        "Verified \(site.evidence.verifiedAt.formatted(date: .abbreviated, time: .shortened))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("Verification evidence appears after a publication resolves.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .frame(width: 286)
        .background(NoctwebTheme.surface)
    }

    private var trustTitle: String {
        switch model.selectedTab.verificationState {
        case .fixtureVerified: "Fixture verified"
        case .finalized: "Publication finalized"
        case .hostedPreview: "Hosted preview"
        case .failed, .blocked: "Verification failed"
        default: "Verification"
        }
    }
}

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct InspectorValue: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }
}

private struct InspectorNotice: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(NoctwebTheme.status)
        )
    }
}

extension Notification.Name {
    static let noctwebFocusAddressField = Notification.Name(
        "net.noctweave.noctweb-browser.focus-address"
    )
}
