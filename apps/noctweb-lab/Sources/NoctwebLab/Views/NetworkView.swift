import NoctwebLabCore
import NoctwebUI
import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var model: AppModel
    @State private var endpoint = "http://127.0.0.1:9440"
    @State private var showsPublishingDetails = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    "Host relays",
                    subtitle:
                        "Connect a relay to publish and verify your Noctweb sites."
                ) {
                    StatusPill(
                        title: connectedRelays.isEmpty
                            ? "Not connected"
                            : "\(connectedRelays.count) connected",
                        systemImage: connectedRelays.isEmpty
                            ? "bolt.slash"
                            : "checkmark.circle.fill",
                        color: connectedRelays.isEmpty ? .orange : .green
                    )
                }

                connectionCard
                relayList
                trustBoundary
            }
            .padding(24)
            .frame(maxWidth: 1_100, alignment: .leading)
        }
        .background(NoctwebTheme.canvas)
    }

    private var connectionCard: some View {
        SectionCard("Connect a host relay", systemImage: "link") {
            Text(
                "Enter the address shown by your relay operator. The Lab checks hosting support and relay identity before saving it."
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            DisclosureGroup("How publishing is verified", isExpanded: $showsPublishingDetails) {
                Text("The Lab reads the signed namespace configuration, publishes through the relay API, fetches the stored object, and verifies the returned receipt before reporting success.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            HStack(spacing: 10) {
                TextField(
                    "https://relay.example.org",
                    text: $endpoint
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit(addRelay)

                Button(action: addRelay) {
                    Label("Connect & Verify", systemImage: "checkmark.shield")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    Task {
                        await model.refreshHostRelays()
                    }
                } label: {
                    if model.relayRefreshInFlight {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.relayRefreshInFlight)
            }

            Text(
                "HTTPS is required for remote relays. Cleartext HTTP is accepted only on loopback for local development."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var relayList: some View {
        SectionCard("Configured endpoints", systemImage: "server.rack") {
            if relays.isEmpty {
                ContentUnavailableView(
                    "No host relays",
                    systemImage: "externaldrive.badge.plus",
                    description: Text(
                        "Enter a host relay address above. It will be verified before you create or publish a site."
                    )
                )
                .frame(minHeight: 180)
            } else {
                ForEach(relays) { relay in
                    relayRow(relay)
                    if relay.id != relays.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    private func relayRow(_ relay: LabRelayNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(
                    systemName: relay.isOnline
                        ? "externaldrive.connected.to.line.below"
                        : "externaldrive.badge.xmark"
                )
                .font(.title3)
                .foregroundStyle(relay.isOnline ? .green : .orange)
                .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(relay.name)
                        .font(.headline)
                    Text(relay.endpoint)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                StatusPill(
                    title: relay.isOnline ? "Connected" : "Unavailable",
                    systemImage: relay.isOnline
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill",
                    color: relay.isOnline ? .green : .orange
                )
            }

            if let namespace = relay.relayNamespaceID,
               let suffix = relay.namespaceSuffix {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 7) {
                    GridRow {
                        Text("Address suffix")
                            .foregroundStyle(.secondary)
                        Text(".\(suffix)")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text("Namespace")
                            .foregroundStyle(.secondary)
                        Text(namespace)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    GridRow {
                        Text("Last latency")
                            .foregroundStyle(.secondary)
                        Text("\(relay.latencyMilliseconds) ms")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .font(.caption)
            }

            HStack {
                Button {
                    Task {
                        await model.refreshHostRelay(relay.id)
                    }
                } label: {
                    Label("Check connection", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    model.removeRelay(relay.id)
                } label: {
                    Label("Remove", systemImage: "minus")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private var trustBoundary: some View {
        SectionCard("What a successful connection proves", systemImage: "checkmark.shield") {
            Label(
                "The endpoint advertises a structurally valid nw.net-host@1 configuration.",
                systemImage: "checkmark.circle"
            )
            Label(
                "Hosted bytes are content-addressed and fetched back before success is shown.",
                systemImage: "checkmark.circle"
            )
            Label(
                "The relay signs a bounded storage receipt with its advertised host key.",
                systemImage: "checkmark.circle"
            )
            Divider()
            Text(
                "A hosting receipt is not consensus finality, global name ownership, permanent availability, or permission for the relay to sign publisher content."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var relays: [LabRelayNode] {
        model.activeWorkspace?.relays ?? []
    }

    private var connectedRelays: [LabRelayNode] {
        relays.filter(\.isOnline)
    }

    private func addRelay() {
        model.addHostRelay(endpoint: endpoint)
        endpoint = ""
    }
}
