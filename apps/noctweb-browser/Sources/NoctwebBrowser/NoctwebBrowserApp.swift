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
        }
    }
}

private struct BrowserSettingsView: View {
    @EnvironmentObject private var model: BrowserAppModel
    @EnvironmentObject private var appearance: NoctwebAppearanceStore

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance.selection) {
                    ForEach(NoctwebAppearance.allCases) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text("System follows macOS. An explicit Light or Dark choice is remembered by this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Network profile") {
                LabeledContent(
                    "Selected",
                    value: model.selectedProfile.displayName
                )
                LabeledContent(
                    "Federation mode",
                    value: model.selectedProfile.federationMode.rawValue
                )
                LabeledContent("Consensus profile") {
                    Text(model.selectedProfile.consensusProfileID)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
            Section("Runtime boundary") {
                Label(
                    "Websites run in a non-persistent, publication-scoped WebKit process.",
                    systemImage: "checkmark.shield"
                )
                Label(
                    "External network requests, new windows, and native bridges are disabled.",
                    systemImage: "network.slash"
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 560, height: 370)
    }
}
