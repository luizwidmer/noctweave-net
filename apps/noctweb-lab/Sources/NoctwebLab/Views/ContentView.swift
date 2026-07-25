import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(selection: $model.selection) {
                Section {
                    ForEach(ProductSection.allCases.filter { $0 != .settings }) { destination in
                        Label(destination.title, systemImage: destination.systemImage)
                            .tag(destination)
                    }
                }

                Section("Workspace") {
                    if let workspace = model.activeWorkspace {
                        LabeledContent("Sites", value: "\(workspace.sites.count)")
                        LabeledContent(
                            "Relays online",
                            value: "\(workspace.relays.filter(\.isOnline).count)/\(workspace.relays.count)"
                        )
                    }
                }
            }
            .navigationTitle("Noctweb Lab")
            .navigationSplitViewColumnWidth(min: 210, ideal: 235, max: 280)
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.selection = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
        } detail: {
            Group {
                switch model.selection ?? .overview {
                case .overview:
                    OverviewView()
                case .sites:
                    SitesView()
                case .runtime:
                    RuntimeView()
                case .network:
                    NetworkView()
                case .testRuns:
                    TestRunsView()
                case .inspector:
                    InspectorView()
                case .settings:
                    SettingsView()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Workspace", selection: workspaceSelection) {
                        ForEach(model.workspaces) { workspace in
                            Text(workspace.name)
                                .tag(Optional(workspace.id))
                        }
                    }
                    .frame(width: 190)

                    Button {
                        model.createWorkspace()
                    } label: {
                        Label("New Workspace", systemImage: "plus")
                    }
                    .help("Create a local workspace")
                }
            }
        }
        .tint(Color(hex: "#4F8F77"))
    }

    private var workspaceSelection: Binding<UUID?> {
        Binding(
            get: { model.activeWorkspaceID },
            set: { model.selectWorkspace($0) }
        )
    }
}
