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
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
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
                    Menu {
                        ForEach(model.workspaces) { workspace in
                            Button {
                                model.selectWorkspace(workspace.id)
                            } label: {
                                if model.activeWorkspaceID == workspace.id {
                                    Label(workspace.name, systemImage: "checkmark")
                                } else {
                                    Text(workspace.name)
                                }
                            }
                        }
                    } label: {
                        Label(
                            model.activeWorkspace?.name ?? "Workspace",
                            systemImage: "square.stack.3d.up"
                        )
                    }
                    .help("Switch workspace")

                    Button {
                        model.createWorkspace()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Workspace")
                    .help("Create a local workspace")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Color(hex: "#4F8F77"))
    }
}
