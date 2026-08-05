import NoctwebUI
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var workspacePendingDeletion: Workspace?

    var body: some View {
        NavigationSplitView {
            labSidebar
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
        } detail: {
            ZStack {
                NoctwebTheme.canvas
                    .ignoresSafeArea()
                Group {
                    switch model.selection ?? .sites {
                    case .overview:
                        SitesView()
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
            }
        }
        .navigationSplitViewStyle(.prominentDetail)
        .tint(NoctwebTheme.accent)
        .background(NoctwebTheme.canvas)
        .noctwebChrome()
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
                "This removes \(workspace.sites.count) local site projects. Published revisions may remain on host relays. Choose whether to retain or permanently destroy every publisher key in the workspace."
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

    private var labSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                NoctwebProductIcon(.lab)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Noctweb Lab")
                        .font(.headline)
                    Text("Build and publish")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 16)

            workspaceMenu
                .padding(.horizontal, 10)

            Button {
                model.createSite()
                model.selection = .sites
            } label: {
                Label("New Site", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                LinearGradient(
                    colors: [NoctwebTheme.accent, NoctwebTheme.accent.opacity(0.78)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .disabled(model.activeWorkspace == nil)

            VStack(spacing: 5) {
                ForEach(primarySections) { destination in
                    LabSidebarButton(
                        destination: destination,
                        selected: model.selection == destination
                    ) {
                        model.selection = destination
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 14)

            Spacer(minLength: 20)

            if let workspace = model.activeWorkspace {
                HStack(spacing: 8) {
                    Circle()
                        .fill(workspace.relays.contains(where: \.isOnline) ? .green : .secondary)
                        .frame(width: 7, height: 7)
                    Text(workspace.relays.isEmpty ? "No relay connected" : relaySummary(workspace))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }

            LabSidebarButton(
                destination: .settings,
                selected: model.selection == .settings
            ) {
                model.selection = .settings
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .background(NoctwebTheme.navigation)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(NoctwebTheme.border)
                .frame(width: 1)
        }
    }

    private var workspaceMenu: some View {
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

            Divider()

            Button {
                model.createWorkspace()
            } label: {
                Label("New Workspace", systemImage: "plus")
            }

            if let workspace = model.activeWorkspace {
                Button(role: .destructive) {
                    workspacePendingDeletion = workspace
                } label: {
                    Label("Remove Workspace…", systemImage: "trash")
                }
                .disabled(
                    model.publicationInFlight ||
                        model.identityOperationSiteID != nil ||
                        workspace.sites.contains {
                            model.identityPreparationSiteIDs.contains($0.id)
                        }
                )
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up")
                    .foregroundStyle(NoctwebTheme.accent)
                Text(model.activeWorkspace?.name ?? "Choose workspace")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(
                NoctwebTheme.surface,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08))
            }
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
    }

    private var primarySections: [ProductSection] {
        [.sites, .runtime, .network]
    }

    private func relaySummary(_ workspace: Workspace) -> String {
        let online = workspace.relays.filter(\.isOnline).count
        return "\(online) of \(workspace.relays.count) relays online"
    }
}

private struct LabSidebarButton: View {
    let destination: ProductSection
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: destination.systemImage)
                    .frame(width: 18)
                Text(destination.title)
                Spacer()
            }
            .font(.subheadline.weight(selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 11)
            .frame(height: 40)
            .contentShape(Rectangle())
            .background(
                selected ? NoctwebTheme.status : Color.clear,
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
