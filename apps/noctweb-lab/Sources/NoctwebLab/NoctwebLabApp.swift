import NoctwebUI
import SwiftUI

@main
struct NoctwebLabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var appearance = NoctwebAppearanceStore()

    init() {
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
