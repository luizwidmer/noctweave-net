import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    "Network",
                    subtitle: "Operate the three explicit relay roles without mixing their responsibilities."
                ) {
                    StatusPill(
                        title: networkStatus,
                        systemImage: allRequiredRolesOnline ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        color: allRequiredRolesOnline ? .green : .orange
                    )
                }

                roleSummary
                topology
                relayOperations
            }
            .padding(28)
            .frame(maxWidth: 1_220, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var roleSummary: some View {
        Grid(horizontalSpacing: 14) {
            GridRow {
                ForEach(LabRelayRole.allCases) { role in
                    let nodes = relays(for: role)
                    MetricCard(
                        title: role.title,
                        value: "\(nodes.filter(\.isOnline).count)/\(nodes.count)",
                        detail: roleDescription(role),
                        systemImage: role.systemImage,
                        tint: role.tint
                    )
                }
            }
        }
    }

    private var topology: some View {
        SectionCard("Active retrieval topology", systemImage: "point.3.connected.trianglepath.dotted") {
            HStack(spacing: 12) {
                topologyEndpoint("Runtime", systemImage: "laptopcomputer", color: .accentColor)

                topologyConnector("coordinates")
                topologyRole(.standard)

                topologyConnector("may forward")
                topologyRole(.passthrough)

                topologyConnector("retrieves")
                topologyRole(.host)

                topologyConnector("renders")
                topologyEndpoint("Native view", systemImage: "swift", color: .orange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            Divider()

            Text("Standard relays coordinate opaque network operations. Passthrough relays provide bounded forwarding. Host relays retain immutable site objects. Consensus finality remains separate from all three relay roles.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var relayOperations: some View {
        SectionCard("Relay operations", systemImage: "server.rack") {
            VStack(spacing: 0) {
                HStack {
                    Text("Relay")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Role")
                        .frame(width: 150, alignment: .leading)
                    Text("Endpoint")
                        .frame(width: 240, alignment: .leading)
                    Text("Latency")
                        .frame(width: 80, alignment: .trailing)
                    Text("Status")
                        .frame(width: 90, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                Divider()

                ForEach(model.activeWorkspace?.relays ?? []) { relay in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(relay.name)
                                .font(.subheadline.weight(.medium))
                            Text(relay.region)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        RelayRoleBadge(role: relay.role)
                            .frame(width: 150, alignment: .leading)

                        Text(relay.endpoint)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 240, alignment: .leading)

                        Text("\(relay.latencyMilliseconds) ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)

                        Toggle(
                            relay.isOnline ? "Online" : "Offline",
                            isOn: relayBinding(relay)
                        )
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(relay.isOnline ? "Take \(relay.name) offline" : "Bring \(relay.name) online")
                        .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 11)

                    if relay.id != model.activeWorkspace?.relays.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private var allRequiredRolesOnline: Bool {
        LabRelayRole.allCases.allSatisfy { role in
            relays(for: role).contains(where: \.isOnline)
        }
    }

    private var networkStatus: String {
        allRequiredRolesOnline ? "All relay roles available" : "Network is degraded"
    }

    private func relays(for role: LabRelayRole) -> [LabRelayNode] {
        model.activeWorkspace?.relays.filter { $0.role == role } ?? []
    }

    private func roleDescription(_ role: LabRelayRole) -> String {
        switch role {
        case .standard: "Coordinates without hosting site bytes"
        case .passthrough: "Provides one bounded forwarding hop"
        case .host: "Retains immutable capsule objects"
        }
    }

    private func topologyEndpoint(_ title: String, systemImage: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 46, height: 46)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            Text(title)
                .font(.caption.weight(.medium))
        }
    }

    private func topologyRole(_ role: LabRelayRole) -> some View {
        let online = relays(for: role).contains(where: \.isOnline)
        return VStack(spacing: 8) {
            Image(systemName: role.systemImage)
                .font(.title2)
                .foregroundStyle(online ? role.tint : .secondary)
                .frame(width: 46, height: 46)
                .background(
                    (online ? role.tint : Color.secondary).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            Text(role.shortTitle)
                .font(.caption.weight(.medium))
            Text(online ? "Online" : "Offline")
                .font(.caption2)
                .foregroundStyle(online ? .green : .red)
        }
    }

    private func topologyConnector(_ title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.right")
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func relayBinding(_ relay: LabRelayNode) -> Binding<Bool> {
        Binding(
            get: {
                model.activeWorkspace?.relays.first(where: { $0.id == relay.id })?.isOnline ?? false
            },
            set: { model.setRelayOnline(relay.id, isOnline: $0) }
        )
    }
}
