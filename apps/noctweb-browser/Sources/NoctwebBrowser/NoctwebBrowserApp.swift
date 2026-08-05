import AppKit
import NoctwebUI
import SwiftUI

@main
struct NoctwebBrowserApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = BrowserAppModel()
    @StateObject private var appearance = NoctwebAppearanceStore()

    var body: some Scene {
        WindowGroup {
            BrowserWindowView()
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
                .tint(NoctwebTheme.quantumViolet)

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
