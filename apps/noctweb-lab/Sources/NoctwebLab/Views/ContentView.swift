import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var workspacePendingDeletion: Workspace?

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
                        if model.workspaces.isEmpty {
                            Text("No local workspaces")
                        } else {
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
                        }

                        Divider()

                        Button {
                            model.createWorkspace()
                        } label: {
                            Label("New Workspace", systemImage: "plus")
                        }

                        if let workspace = model.activeWorkspace {
                            Divider()
                            Button(role: .destructive) {
                                workspacePendingDeletion = workspace
                            } label: {
                                Label("Remove Workspace…", systemImage: "trash")
                            }
                            .disabled(
                                model.publicationInFlight ||
                                    model.identityOperationSiteID != nil ||
                                    workspace.sites.contains {
                                        model.identityPreparationSiteIDs
                                            .contains($0.id)
                                    }
                            )
                        }
                    } label: {
                        Label(
                            model.activeWorkspace?.name ?? "No Workspace",
                            systemImage: "square.stack.3d.up"
                        )
                    }
                    .help("Switch workspace")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Color(hex: "#4F8F77"))
        .confirmationDialog(
            "Remove \(workspacePendingDeletion?.name ?? "workspace") from this Mac?",
            isPresented: workspaceDeletionBinding,
            titleVisibility: .visible,
            presenting: workspacePendingDeletion
        ) { workspace in
            Button("Remove Workspace, Keep Keys", role: .destructive) {
                _ = model.deleteWorkspace(workspace.id)
                workspacePendingDeletion = nil
            }
            .disabled(
                workspace.sites.contains {
                    model.identityPreparationSiteIDs.contains($0.id)
                }
            )
            Button("Destroy Keys & Remove Workspace", role: .destructive) {
                workspacePendingDeletion = nil
                Task {
                    for site in workspace.sites {
                        guard await model.destroyPublisherIdentity(for: site.id) else {
                            return
                        }
                    }
                    _ = model.deleteWorkspace(workspace.id)
                }
            }
            .disabled(
                workspace.sites.contains {
                    model.identityPreparationSiteIDs.contains($0.id)
                }
            )
            Button("Cancel", role: .cancel) {
                workspacePendingDeletion = nil
            }
        } message: { workspace in
            Text(
                "This removes \(workspace.sites.count) local site projects and \(workspace.runs.count) saved test runs. Published revisions may remain on host relays. Choose whether to retain or permanently destroy every publisher key in the workspace."
            )
        }
        .alert(
            "Action Couldn’t Be Completed",
            isPresented: operationErrorBinding
        ) {
            Button("OK") {
                model.clearOperationError()
            }
        } message: {
            Text(model.operationError ?? "An unknown error occurred.")
        }
    }

    private var workspaceDeletionBinding: Binding<Bool> {
        Binding(
            get: { workspacePendingDeletion != nil },
            set: { if !$0 { workspacePendingDeletion = nil } }
        )
    }

    private var operationErrorBinding: Binding<Bool> {
        Binding(
            get: { model.operationError != nil },
            set: { if !$0 { model.clearOperationError() } }
        )
    }
}
