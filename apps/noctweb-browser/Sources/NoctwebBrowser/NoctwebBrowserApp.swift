import AppKit
import NoctwebUI
import SwiftUI

@main
struct NoctwebBrowserApp: App {
    @StateObject private var support = AppSupportStore.shared

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: BrowserAppModel
    @StateObject private var appearance = NoctwebAppearanceStore()

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "NOCTWEB_BROWSER_UI_TEST_SUITE"),
           arguments.indices.contains(index + 1),
           let defaults = UserDefaults(suiteName: arguments[index + 1]) {
            _model = StateObject(wrappedValue: BrowserAppModel(
                persistenceStore: BrowserPersistenceStore(defaults: defaults)
            ))
            return
        }
        #endif
        _model = StateObject(wrappedValue: BrowserAppModel())
    }

    var body: some Scene {
        WindowGroup {
            BrowserWindowView()
                .disabled(model.isResetting)
                .environmentObject(model)
                .environmentObject(appearance)
                .noctwebAppearance(appearance.selection)
                .onOpenURL(perform: model.handleOpenURL)
                .onChange(of: scenePhase) {
                    if scenePhase != .active {
                        model.flushPersistence()
                    }
                }
        }
        .defaultSize(width: 1_180, height: 760)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab", action: model.addTab)
                    .keyboardShortcut("t", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button("Open Location…") {
                    NotificationCenter.default.post(
                        name: .noctwebFocusAddressField,
                        object: nil
                    )
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Reload", action: model.reload)
                    .keyboardShortcut("r", modifiers: .command)

                Button("Stop", action: model.stop)
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(
                        model.selectedTab.verificationState != .resolving
                    )

                Divider()

                Button(
                    model.isSelectedSiteBookmarked
                        ? "Remove Bookmark"
                        : "Add Bookmark",
                    action: model.toggleBookmark
                )
                .keyboardShortcut("d", modifiers: .command)
                .disabled(!model.canBookmarkSelectedSite)
            }
            CommandMenu("View") {
                Button(
                    model.showsSidebar ? "Hide Sidebar" : "Show Sidebar"
                ) {
                    model.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Button(
                    model.showsTrustInspector
                        ? "Hide Verification Details"
                        : "Show Verification Details"
                ) {
                    model.toggleTrustInspector()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }

        Settings {
            BrowserSettingsView()
                .environmentObject(model)
                .environmentObject(appearance)
                .noctwebAppearance(appearance.selection)
        }
    }
}

private struct BrowserSettingsView: View {
    @EnvironmentObject private var model: BrowserAppModel
    @EnvironmentObject private var appearance: NoctwebAppearanceStore
    @State private var showsResetConfirmation = false
    @State private var resetConfirmation = ""
    @State private var resetError: String?

    private let columns = [
        GridItem(.adaptive(minimum: 300), spacing: 18, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Browser Settings")
                        .font(.largeTitle.weight(.semibold))
                    Text("Appearance, relay selection, and the website runtime boundary.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                BrowserSettingsCard(
                    "Appearance",
                    systemImage: "circle.lefthalf.filled"
                ) {
                    Picker("Theme", selection: $appearance.selection) {
                        ForEach(NoctwebAppearance.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("System follows macOS. Light and Dark remain explicit choices and are remembered by Noctweb Browser.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                AppSupportCard()

                BrowserSettingsCard("Reset app", systemImage: "trash") {
                    Text("Delete bookmarks, history, open tabs, saved relays, website data, and app settings. Files you downloaded or exported remain unchanged.")
                        .foregroundStyle(.secondary)
                    Button("Purge and Reset App…", role: .destructive) {
                        resetConfirmation = ""
                        showsResetConfirmation = true
                    }
                    .disabled(model.isResetting)
                    .accessibilityIdentifier("app.purgeAndReset")
                    if model.isResetting { ProgressView("Resetting…") }
                    if let resetError { Text(resetError).foregroundStyle(.red) }
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    BrowserSettingsCard(
                        "Network profile",
                        systemImage: "network"
                    ) {
                        settingsRows([
                            ("Selected", model.selectedProfile.displayName),
                            ("Federation mode", model.selectedProfile.federationMode.rawValue),
                            ("Consensus profile", model.selectedProfile.consensusProfileID)
                        ])
                    }

                    BrowserSettingsCard(
                        "Runtime boundary",
                        systemImage: "shield.lefthalf.filled"
                    ) {
                        settingsRows([
                            ("Website storage", "Non-persistent"),
                            ("Process scope", "Per publication"),
                            ("Native bridge", "Unavailable")
                        ])

                        Text("Only verified bundle bytes run. External network requests, new windows, and native bridges are blocked by runtime policy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(NoctwebTheme.canvas)
        .frame(minWidth: 700, minHeight: 520)
        .alert("Purge and reset Noctweb Browser?", isPresented: $showsResetConfirmation) {
            TextField("Type RESET to confirm", text: $resetConfirmation)
            Button("Cancel", role: .cancel) {}
            Button("Purge and Reset", role: .destructive) {
                Task {
                    do {
                        try await model.purgeAndReset()
                        appearance.reset()
                        resetError = nil
                    } catch { resetError = "Reset could not finish: \(error.localizedDescription)" }
                }
            }
            .disabled(resetConfirmation != "RESET")
        } message: {
            Text("All local browsing data and settings will be deleted. This cannot be undone.")
        }
    }

    private func settingsRows(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(row.1)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(.callout)
                .padding(.vertical, 9)

                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
    }
}

private struct BrowserSettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .tint(NoctwebTheme.accent)

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            NoctwebTheme.card,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NoctwebTheme.border, lineWidth: 1)
        }
        .shadow(color: NoctwebTheme.softShadow, radius: 16, y: 7)
    }
}
