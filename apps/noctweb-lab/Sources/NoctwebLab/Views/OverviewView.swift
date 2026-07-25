import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    "Overview",
                    subtitle: "Build, publish, and verify Noctweb sites on a deterministic local network."
                ) {
                    Button {
                        model.createSite()
                        model.selection = .sites
                    } label: {
                        Label("New Site", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                metrics

                HStack(alignment: .top, spacing: 18) {
                    publicationSummary
                    networkSummary
                }

                HStack(alignment: .top, spacing: 18) {
                    trustSummary
                    recentRuns
                }
            }
            .padding(28)
            .frame(maxWidth: 1_280, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var metrics: some View {
        let workspace = model.activeWorkspace
        let online = workspace?.relays.filter(\.isOnline).count ?? 0
        let published = workspace?.sites.filter { $0.lastPublishedAt != nil }.count ?? 0
        let passingRuns = workspace?.runs.filter { $0.result == .passed }.count ?? 0

        return Grid(horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                MetricCard(
                    title: "Sites",
                    value: "\(workspace?.sites.count ?? 0)",
                    detail: "\(published) published",
                    systemImage: "rectangle.stack",
                    tint: .accentColor
                )
                MetricCard(
                    title: "Network",
                    value: "\(online)/\(workspace?.relays.count ?? 0)",
                    detail: "Relays online",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    tint: online == workspace?.relays.count ? .green : .orange
                )
                MetricCard(
                    title: "Test runs",
                    value: "\(passingRuns)",
                    detail: "Passing deterministic scenarios",
                    systemImage: "checkmark.circle",
                    tint: .blue
                )
                MetricCard(
                    title: "Profile",
                    value: "Native",
                    detail: "SwiftUI static site runtime",
                    systemImage: "swift",
                    tint: .orange
                )
            }
        }
    }

    private var publicationSummary: some View {
        SectionCard("Publication workflow", systemImage: "arrow.triangle.2.circlepath") {
            if let site = model.selectedSite {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(site.title)
                            .font(.title3.weight(.semibold))
                        Text(site.address)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(
                        title: site.lastPublishedAt == nil ? "Draft" : "Revision \(site.revision)",
                        systemImage: site.lastPublishedAt == nil ? "pencil" : "checkmark",
                        color: site.lastPublishedAt == nil ? .orange : .green
                    )
                }

                PublicationPipeline(
                    activeStage: model.publicationStage,
                    outcome: model.publicationOutcome
                )
                Text(model.publicationMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView(
                    "No Site Selected",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Create a site to begin the publication workflow.")
                )
                .frame(height: 150)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var networkSummary: some View {
        SectionCard("Relay topology", systemImage: "network") {
            ForEach(LabRelayRole.allCases) { role in
                let relays = model.activeWorkspace?.relays.filter { $0.role == role } ?? []
                HStack {
                    RelayRoleBadge(role: role)
                    Spacer()
                    Text("\(relays.filter(\.isOnline).count)/\(relays.count) online")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if role != LabRelayRole.allCases.last {
                    Divider()
                }
            }

            Button("Open Network") {
                model.selection = .network
            }
            .buttonStyle(.link)
        }
        .frame(width: 330)
    }

    private var trustSummary: some View {
        SectionCard("Trust evidence", systemImage: "shield") {
            ForEach(model.trustEvidence) { evidence in
                EvidenceRow(evidence: evidence, compact: true)
                if evidence.id != model.trustEvidence.last?.id {
                    Divider()
                }
            }
            Button("Inspect Evidence") {
                model.selection = .inspector
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
    }

    private var recentRuns: some View {
        SectionCard("Recent test runs", systemImage: "checklist") {
            if let runs = model.activeWorkspace?.runs.prefix(4), !runs.isEmpty {
                ForEach(Array(runs)) { run in
                    HStack(spacing: 10) {
                        Image(systemName: run.result == .passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(run.result == .passed ? .green : .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.scenarioName)
                                .font(.subheadline.weight(.medium))
                            Text(run.startedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(run.durationMilliseconds) ms")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Run a fault scenario to establish a repeatable test record.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Button("Open Test Runs") {
                model.selection = .testRuns
            }
            .buttonStyle(.link)
        }
        .frame(width: 390)
    }
}
