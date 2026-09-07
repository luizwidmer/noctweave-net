import NoctwebUI
import NoctwebLabCore
import SwiftUI

@main
struct NoctwebLabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var appearance = NoctwebAppearanceStore()

    init() {
        #if DEBUG
        // Isolated UI runs must not read the user's workspace or Keychain.
        // Release builds ignore this argument and use production persistence.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "NOCTWEB_LAB_UI_TEST_WORKSPACE"),
           arguments.indices.contains(index + 1),
           arguments[index + 1].hasPrefix("/"),
           let engine = try? NoctwebLabEngine(identityStore: InMemoryPublicationPrivateKeyStore()) {
            _model = StateObject(wrappedValue: AppModel(
                engine: engine,
                workspaceFileURL: URL(fileURLWithPath: arguments[index + 1]),
                useLiveRelay: true
            ))
            return
        }
        #endif
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(appearance)
                .noctwebAppearance(appearance.selection)
                .frame(minWidth: 900, minHeight: 650)
                .onChange(of: scenePhase) {
                    if scenePhase != .active {
                        model.flushPersistence()
                    }
                }
        }
        .defaultSize(width: 1_360, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Site") {
                    model.createSite()
                    model.selection = .sites
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(model.activeWorkspace == nil)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(appearance)
                .noctwebAppearance(appearance.selection)
                .frame(minWidth: 760, minHeight: 600)
        }
    }
}
