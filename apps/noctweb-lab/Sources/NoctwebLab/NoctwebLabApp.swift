import NoctwebUI
import SwiftUI

@main
struct NoctwebLabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: AppModel
    @StateObject private var appearance = NoctwebAppearanceStore()
    private let publicationBridge: LocalPublicationBridge

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        publicationBridge = LocalPublicationBridge { [weak model] address in
            await MainActor.run {
                model?.publishedEnvelope(for: address)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(appearance)
                .noctwebAppearance(appearance.selection)
                .frame(minWidth: 900, minHeight: 650)
                .task {
                    publicationBridge.start()
                }
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
                .frame(width: 620, height: 460)
        }
    }
}
