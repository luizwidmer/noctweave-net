import NoctwebUI
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    "Overview",
                    subtitle: "Build, host, fetch, and verify Noctweb sites through a real relay."
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

                LazyVGrid(columns: summaryColumns, alignment: .leading, spacing: 18) {
                    publicationSummary
                    networkSummary
                    trustSummary
                }
            }
            .padding(24)
            .frame(maxWidth: 1_280, alignment: .leading)
        }
        .background(NoctwebTheme.canvas)
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 190, maximum: 300), spacing: 14, alignment: .top)]
    }

    private var summaryColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 360), spacing: 18, alignment: .top)]
    }

    private var metrics: some View {
        let workspace = model.activeWorkspace
        let online = workspace?.relays.filter(\.isOnline).count ?? 0
        let hosted = workspace?.sites.filter { $0.lastPublishedAt != nil }.count ?? 0
        return LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
            MetricCard(
                title: "Sites",
                value: "\(workspace?.sites.count ?? 0)",
                detail: "\(hosted) hosted",
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
                title: "Profile",
                value: "Website",
                detail: "Signed JS and React-ready bundles",
                systemImage: "globe",
                tint: .orange
            )
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
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .layoutPriority(1)
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
        SectionCard("Host relay", systemImage: "network") {
            let relays = model.activeWorkspace?.relays ?? []
            if relays.isEmpty {
                Text("No host relay configured")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(relays) { relay in
                HStack {
                        Label(
                            relay.name,
                            systemImage: relay.isOnline
                                ? "externaldrive.connected.to.line.below"
                                : "externaldrive.badge.xmark"
                        )
                    Spacer()
                        Text(relay.isOnline ? "Connected" : "Unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                    if relay.id != relays.last?.id {
                        Divider()
                    }
                }
            }

            Button("Open Network") {
                model.selection = .network
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity)
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

}
