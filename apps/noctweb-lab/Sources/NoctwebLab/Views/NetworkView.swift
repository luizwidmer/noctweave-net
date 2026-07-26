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
            .padding(24)
            .frame(maxWidth: 1_220, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var roleColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 14, alignment: .top)]
    }

    private var topologyColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140, maximum: 210), spacing: 12, alignment: .top)]
    }

    private var relayCardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)]
    }

    private var roleSummary: some View {
        LazyVGrid(columns: roleColumns, alignment: .leading, spacing: 14) {
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

    private var topology: some View {
        SectionCard("Active retrieval topology", systemImage: "point.3.connected.trianglepath.dotted") {
            LazyVGrid(columns: topologyColumns, alignment: .leading, spacing: 12) {
                topologyStep(
                    order: 1,
                    title: "Runtime",
                    relationship: "Coordinates",
                    systemImage: "laptopcomputer",
                    color: .accentColor,
                    state: "Local",
                    stateColor: .secondary
                )
                topologyRoleStep(order: 2, role: .standard, relationship: "May forward")
                topologyRoleStep(order: 3, role: .passthrough, relationship: "Retrieves")
                topologyRoleStep(order: 4, role: .host, relationship: "Renders")
                topologyStep(
                    order: 5,
                    title: "Native view",
                    relationship: "Verified output",
                    systemImage: "swift",
                    color: .orange,
                    state: "Local",
                    stateColor: .secondary
                )
            }

            Divider()

            Text("Standard relays coordinate opaque network operations. Passthrough relays provide bounded forwarding. Host relays retain immutable site objects and may advertise a Noctweb namespace. Consensus—not the host—finalizes names and publisher heads.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var relayOperations: some View {
        SectionCard("Relay operations", systemImage: "server.rack") {
            ViewThatFits(in: .horizontal) {
                relayTable
                    .frame(minWidth: 720)
                relayCards
            }
        }
    }

    private var relayTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Relay")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Role")
                    .frame(width: 140, alignment: .leading)
                Text("Endpoint")
                    .frame(width: 220, alignment: .leading)
                Text("Latency")
                    .frame(width: 78, alignment: .trailing)
                Text("Status")
                    .frame(width: 72, alignment: .trailing)
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
                        if let suffix = relay.namespaceSuffix {
                            Text(".\(suffix)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    RelayRoleBadge(role: relay.role)
                        .frame(width: 140, alignment: .leading)

                    Text(relay.endpoint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: 220, alignment: .leading)

                    Text("\(relay.latencyMilliseconds) ms")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 78, alignment: .trailing)

                    Toggle(
                        relay.isOnline ? "Online" : "Offline",
                        isOn: relayBinding(relay)
                    )
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(relay.isOnline ? "Take \(relay.name) offline" : "Bring \(relay.name) online")
                    .frame(width: 72, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 11)

                if relay.id != model.activeWorkspace?.relays.last?.id {
                    Divider()
                }
            }
        }
    }

    private var relayCards: some View {
        LazyVGrid(columns: relayCardColumns, alignment: .leading, spacing: 12) {
            ForEach(model.activeWorkspace?.relays ?? []) { relay in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(relay.name)
                                .font(.subheadline.weight(.semibold))
                            Text(relay.region)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Toggle(
                            relay.isOnline ? "Online" : "Offline",
                            isOn: relayBinding(relay)
                        )
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(relay.isOnline ? "Take \(relay.name) offline" : "Bring \(relay.name) online")
                    }

                    HStack(spacing: 10) {
                        RelayRoleBadge(role: relay.role)
                        Spacer(minLength: 8)
                        Label("\(relay.latencyMilliseconds) ms", systemImage: "speedometer")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if let suffix = relay.namespaceSuffix {
                        HStack(spacing: 8) {
                            Label(
                                ".\(suffix)",
                                systemImage: "link.badge.plus"
                            )
                            .font(.system(.caption, design: .monospaced))
                            Spacer()
                            Text(
                                suffix.hasPrefix("r-")
                                    ? "Automatic"
                                    : "Operator suffix"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Text(relay.endpoint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.72),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
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

    private func topologyRoleStep(
        order: Int,
        role: LabRelayRole,
        relationship: String
    ) -> some View {
        let online = relays(for: role).contains(where: \.isOnline)
        return topologyStep(
            order: order,
            title: role.shortTitle,
            relationship: relationship,
            systemImage: role.systemImage,
            color: online ? role.tint : .secondary,
            state: online ? "Online" : "Offline",
            stateColor: online ? .green : .red
        )
    }

    private func topologyStep(
        order: Int,
        title: String,
        relationship: String,
        systemImage: String,
        color: Color,
        state: String,
        stateColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(order)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.secondary.opacity(0.1), in: Circle())
                Spacer()
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(color)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(relationship)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(state)
                .font(.caption2.weight(.medium))
                .foregroundStyle(stateColor)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
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
