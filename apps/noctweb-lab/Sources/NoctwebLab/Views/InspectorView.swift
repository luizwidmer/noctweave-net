import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                "Inspector",
                subtitle: "Review publication state and each independent trust claim."
            ) {
                if let site = model.selectedSite {
                    StatusPill(
                        title: site.objectID == nil ? "No finalized object" : "Object available",
                        systemImage: site.objectID == nil ? "circle.dashed" : "checkmark.shield",
                        color: site.objectID == nil ? .secondary : .green
                    )
                }
            }
            .padding(24)

            Divider()

            HSplitView {
                evidenceList
                    .frame(minWidth: 280, idealWidth: 330, maxWidth: 390)
                inspectorDetail
                    .frame(minWidth: 650)
            }
        }
    }

    private var evidenceList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Trust Claims")
                .font(.headline)
                .padding(16)
            Divider()
            List(selection: $model.inspectorEvidenceID) {
                ForEach(model.trustEvidence) { evidence in
                    HStack(spacing: 10) {
                        Image(systemName: evidence.kind.systemImage)
                            .foregroundStyle(evidence.state.color)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(evidence.kind.title)
                                .font(.subheadline.weight(.medium))
                            Text(evidence.state.title)
                                .font(.caption)
                                .foregroundStyle(evidence.state.color)
                        }
                    }
                    .padding(.vertical, 5)
                    .tag(Optional(evidence.id))
                }
            }
            .listStyle(.inset)
        }
        .background(.regularMaterial)
    }

    private var inspectorDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let evidence = model.selectedEvidence {
                    SectionCard(evidence.kind.title, systemImage: evidence.kind.systemImage) {
                        HStack {
                            StatusPill(
                                title: evidence.state.title,
                                systemImage: evidence.state == .accepted ? "checkmark.circle.fill" : "circle.dashed",
                                color: evidence.state.color
                            )
                            Spacer()
                            if let checkedAt = evidence.checkedAt {
                                Text("Checked \(checkedAt.formatted(date: .omitted, time: .standard))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(evidence.summary)
                            .font(.title3.weight(.semibold))
                        Text(evidence.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let site = model.selectedSite {
                    publicationObject(site)
                    publicationIdentity(site)
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func publicationObject(_ site: SiteProject) -> some View {
        SectionCard("Finalized object", systemImage: "cube") {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    fieldLabel("Address")
                    selectableValue(site.address)
                }
                GridRow {
                    fieldLabel("Object identifier")
                    selectableValue(site.objectID ?? "Not finalized")
                }
                GridRow {
                    fieldLabel("Revision")
                    selectableValue(site.revision == 0 ? "Unpublished" : "\(site.revision)")
                }
                GridRow {
                    fieldLabel("Profile")
                    selectableValue("Native static capsule")
                }
                GridRow {
                    fieldLabel("Rendered by")
                    selectableValue("SwiftUI")
                }
            }
        }
    }

    private func publicationIdentity(_ site: SiteProject) -> some View {
        SectionCard("Publication identity", systemImage: "signature") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: site.publicationIdentity.systemImage)
                    .font(.title2)
                    .foregroundStyle(site.publicationIdentity == .ready ? .green : .orange)
                VStack(alignment: .leading, spacing: 5) {
                    Text(site.publicationIdentity.title)
                        .font(.headline)
                    Text("This authority belongs only to this publication. It is not a user account, persona, linked-device identity, recovery authority, or global inbox.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 130, alignment: .leading)
    }

    private func selectableValue(_ value: String) -> some View {
        Text(value)
            .font(.system(.callout, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(2)
            .truncationMode(.middle)
    }
}
