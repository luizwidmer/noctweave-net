import NoctwebLabCore
import NoctwebUI
import SwiftUI

struct NetworkView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    "Network",
                    subtitle: "Inspect relay capabilities and control the hierarchy that selects direct or one-hop website retrieval."
                ) {
                    StatusPill(
                        title: networkStatus,
                        systemImage: networkHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                        color: networkHealthy ? .green : .orange
                    )
                }

                roleSummary
                topology
                routePolicy
                relayOperations
            }
            .padding(24)
            .frame(maxWidth: 1_220, alignment: .leading)
        }
        .background(NoctwebTheme.canvas)
    }

    private var roleColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 14, alignment: .top)]
    }

    private var routeColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 320), spacing: 14, alignment: .top)]
    }

    private var authorityColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 10, alignment: .top)]
    }

    private var policyColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 250), spacing: 14, alignment: .top)]
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
        SectionCard("Website retrieval", systemImage: "point.3.connected.trianglepath.dotted") {
            Text("Public website resolution has two valid paths. A standard relay is not part of either required path.")
                .font(.callout)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: routeColumns, alignment: .leading, spacing: 14) {
                routeOption(
                    title: "Direct",
                    detail: "The default when every policy level remains open.",
                    steps: [
                        RouteTopologyStep("Runtime", systemImage: "laptopcomputer", color: .accentColor),
                        RouteTopologyStep("Host", systemImage: LabRelayRole.host.systemImage, color: LabRelayRole.host.tint),
                    ],
                    available: onlineHostAvailable
                )
                routeOption(
                    title: "One-hop",
                    detail: "Used only when policy selects bounded passthrough retrieval.",
                    steps: [
                        RouteTopologyStep("Runtime", systemImage: "laptopcomputer", color: .accentColor),
                        RouteTopologyStep("Passthrough", systemImage: LabRelayRole.passthrough.systemImage, color: LabRelayRole.passthrough.tint),
                        RouteTopologyStep("Host", systemImage: LabRelayRole.host.systemImage, color: LabRelayRole.host.tint),
                    ],
                    available: onlineHostAvailable && onlinePassthroughAvailable
                )
            }

            Divider()

            Text("Routing authority · highest precedence first")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(columns: authorityColumns, alignment: .leading, spacing: 10) {
                authorityStep(order: 1, title: "Federation", detail: "Trust-domain policy")
                authorityStep(order: 2, title: "Relay operator", detail: "Host endpoint policy")
                authorityStep(order: 3, title: "Publisher", detail: "Signed revision policy")
                authorityStep(order: 4, title: "Visitor", detail: "Runtime preference")
            }

            Text("The first non-open directive wins. When all four levels are open, the runtime retrieves directly from a host.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var routePolicy: some View {
        SectionCard("Route policy", systemImage: "arrow.triangle.branch") {
            Text("Federation policy has the highest authority. Host operators and signed publisher revisions may decide only while every higher level remains open.")
                .font(.callout)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: policyColumns, alignment: .leading, spacing: 14) {
                policyControl(
                    title: "Federation mode",
                    detail: "Selects the relay trust domain."
                ) {
                    Picker("Federation mode", selection: federationModeBinding) {
                        ForEach(FederationMode.allCases, id: \.self) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                policyControl(
                    title: "Federation directive",
                    detail: federationDirectiveDetail
                ) {
                    Picker("Federation directive", selection: federationDirectiveBinding) {
                        ForEach(routeDirectiveOptions, id: \.self) { directive in
                            Text(directive.title)
                                .tag(directive)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(federationMode == .solo)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Host-capable relay operators")
                    .font(.subheadline.weight(.semibold))

                if hostRelays.isEmpty {
                    Text("No relay currently advertises host capability.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hostRelays) { relay in
                        relayPolicyRow(relay)
                        if relay.id != hostRelays.last?.id {
                            Divider()
                        }
                    }
                }
            }

            Divider()

            Label(networkHealthDetail, systemImage: networkHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(networkHealthy ? .green : .orange)
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
                Text("Capabilities")
                    .frame(width: 200, alignment: .leading)
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

                    capabilityBadges(relay)
                        .frame(width: 200, alignment: .leading)

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

                    HStack(alignment: .top, spacing: 10) {
                        capabilityBadges(relay)
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

    private var routeDirectiveOptions: [RouteDirective] {
        [.open, .direct, .passthrough]
    }

    private var federationMode: FederationMode {
        model.activeWorkspace?.resolvedFederationMode ?? .solo
    }

    private var federationDirectiveDetail: String {
        federationMode == .solo
            ? "Solo mode has no federation authority, so this level remains open."
            : "The first non-open directive stops evaluation of lower levels."
    }

    private var hostRelays: [LabRelayNode] {
        relays(for: .host)
    }

    private var routeCandidateHostRelays: [LabRelayNode] {
        guard
            let signedHostIDs =
                model.selectedWebsiteRoutingContext.hostRelayIDs
        else {
            return hostRelays
        }
        return hostRelays.filter { signedHostIDs.contains($0.id) }
    }

    private var onlineHostAvailable: Bool {
        routeCandidateHostRelays.contains(where: \.isOnline)
    }

    private var onlinePassthroughAvailable: Bool {
        relays(for: .passthrough).contains(where: \.isOnline)
    }

    private var onlineHostPolicyDecisions: [RoutingDecision] {
        guard let workspace = model.activeWorkspace else { return [] }
        let federation = FederationRoutingPolicy(
            mode: workspace.resolvedFederationMode,
            directive: workspace.resolvedFederationMode == .solo
                ? .open
                : workspace.resolvedFederationRouteDirective
        )
        let routingContext = model.selectedWebsiteRoutingContext
        return routeCandidateHostRelays.compactMap { relay in
            guard relay.isOnline else { return nil }
            return RoutingPolicyResolver.resolve(
                federation: federation,
                relayOperator: relay.resolvedOperatorRouteDirective,
                publisher: routingContext.publisherDirective,
                visitor: model.routeMode.directive
            )
        }
    }

    private var directCandidateAvailable: Bool {
        onlineHostPolicyDecisions.contains { $0.directive == .direct }
    }

    private var oneHopCandidateAvailable: Bool {
        onlinePassthroughAvailable &&
            onlineHostPolicyDecisions.contains {
                $0.directive == .passthrough
            }
    }

    private var networkHealthy: Bool {
        directCandidateAvailable || oneHopCandidateAvailable
    }

    private var networkStatus: String {
        if !onlineHostAvailable {
            return "Host unavailable"
        }
        if !networkHealthy {
            return "Passthrough unavailable"
        }
        return directCandidateAvailable
            ? "Direct route ready"
            : "One-hop route ready"
    }

    private var networkHealthDetail: String {
        if !onlineHostAvailable {
            return model.selectedWebsiteRoutingContext.usesSignedPublication
                ? "No online host retains the selected signed revision."
                : "Public website resolution requires at least one online host."
        }
        if !networkHealthy {
            return "The current policy requires one-hop retrieval, but no passthrough-capable relay is online."
        }
        if !directCandidateAvailable {
            return "The current policy selects one-hop retrieval; an online host and passthrough are available."
        }
        return "Direct retrieval is healthy. Passthrough is optional, and standard relay availability does not gate public website resolution."
    }

    private func relays(for role: LabRelayRole) -> [LabRelayNode] {
        model.activeWorkspace?.relays.filter { $0.supports(role) } ?? []
    }

    private func roleDescription(_ role: LabRelayRole) -> String {
        switch role {
        case .standard: "Private transport; not required for public website resolution"
        case .passthrough: "Optional bounded hop unless selected by policy"
        case .host: "Required capability for immutable capsule retrieval"
        }
    }

    private func routeOption(
        title: String,
        detail: String,
        steps: [RouteTopologyStep],
        available: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                StatusPill(
                    title: available ? "Available" : "Unavailable",
                    systemImage: available ? "checkmark.circle.fill" : "xmark.circle.fill",
                    color: available ? .green : .red
                )
            }

            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(steps.enumerated()), id: \.offset) { item in
                    VStack(spacing: 6) {
                        Image(systemName: item.element.systemImage)
                            .font(.headline)
                            .foregroundStyle(item.element.color)
                            .frame(height: 22)
                        Text(item.element.title)
                            .font(.caption.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    if item.offset < steps.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 5)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }

    private func authorityStep(
        order: Int,
        title: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(order)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        }
    }

    private func policyControl<Control: View>(
        title: String,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            control()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func relayPolicyRow(_ relay: LabRelayNode) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                relayPolicyIdentity(relay)
                Spacer(minLength: 12)
                Picker(
                    "Operator directive for \(relay.name)",
                    selection: relayDirectiveBinding(relay)
                ) {
                    ForEach(routeDirectiveOptions, id: \.self) { directive in
                        Text(directive.title)
                            .tag(directive)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 170)
            }

            VStack(alignment: .leading, spacing: 10) {
                relayPolicyIdentity(relay)
                Picker(
                    "Operator directive",
                    selection: relayDirectiveBinding(relay)
                ) {
                    ForEach(routeDirectiveOptions, id: \.self) { directive in
                        Text(directive.title)
                            .tag(directive)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .padding(.vertical, 4)
    }

    private func relayPolicyIdentity(_ relay: LabRelayNode) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(relay.name)
                .font(.subheadline.weight(.medium))
            capabilityBadges(relay)
        }
    }

    private func capabilityBadges(_ relay: LabRelayNode) -> some View {
        HStack(spacing: 5) {
            ForEach(LabRelayRole.allCases.filter { relay.supports($0) }) { role in
                Text(role.shortTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(role.tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(role.tint.opacity(0.1), in: Capsule())
            }
        }
    }

    private var federationModeBinding: Binding<FederationMode> {
        Binding(
            get: { model.activeWorkspace?.resolvedFederationMode ?? .solo },
            set: { model.setFederationMode($0) }
        )
    }

    private var federationDirectiveBinding: Binding<RouteDirective> {
        Binding(
            get: {
                if federationMode == .solo {
                    return .open
                }
                return model.activeWorkspace?
                    .resolvedFederationRouteDirective ?? .open
            },
            set: { model.setFederationRouteDirective($0) }
        )
    }

    private func relayDirectiveBinding(
        _ relay: LabRelayNode
    ) -> Binding<RouteDirective> {
        Binding(
            get: {
                model.activeWorkspace?.relays
                    .first(where: { $0.id == relay.id })?
                    .resolvedOperatorRouteDirective ?? .open
            },
            set: {
                model.setRelayOperatorRouteDirective($0, relayID: relay.id)
            }
        )
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

private struct RouteTopologyStep {
    let title: String
    let systemImage: String
    let color: Color

    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }
}
