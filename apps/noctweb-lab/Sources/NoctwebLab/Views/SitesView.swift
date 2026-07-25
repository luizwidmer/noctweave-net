import SwiftUI

struct SitesView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HSplitView {
            siteList
                .frame(minWidth: 220, idealWidth: 250, maxWidth: 300)

            if let site = model.selectedSite {
                siteWorkspace(site)
                    .frame(minWidth: 720)
            } else {
                ContentUnavailableView(
                    "No Site Selected",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Create a site in this workspace to begin.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var siteList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sites")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    model.createSite()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Create a site")
            }
            .padding(16)

            Divider()

            List(selection: siteSelection) {
                ForEach(model.activeWorkspace?.sites ?? []) { site in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(site.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(site.address)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(site.lastPublishedAt == nil ? "Draft" : "Revision \(site.revision)")
                            .font(.caption2)
                            .foregroundStyle(site.lastPublishedAt == nil ? .orange : .green)
                    }
                    .padding(.vertical, 5)
                    .tag(Optional(site.id))
                }
            }
            .listStyle(.sidebar)
        }
        .background(.regularMaterial)
    }

    private func siteWorkspace(_ site: SiteProject) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    site.title,
                    subtitle: "Edit the publication, review its native preview, then publish a verified revision."
                ) {
                    if model.publicationOutcome == .running {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        model.publishSelectedSite()
                    } label: {
                        Label(
                            model.publicationOutcome == .running ? "Publishing…" : "Publish Revision",
                            systemImage: "paperplane.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.publicationOutcome == .running)
                }

                PublicationPipeline(
                    activeStage: model.publicationStage,
                    outcome: model.publicationOutcome
                )
                .frame(maxWidth: 700)

                HStack(spacing: 8) {
                    Image(systemName: outcomeImage)
                        .foregroundStyle(outcomeColor)
                    Text(model.publicationMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)

            Divider()

            HSplitView {
                editor(site)
                    .frame(minWidth: 330, idealWidth: 410)
                preview(site)
                    .frame(minWidth: 420)
            }
        }
    }

    private func editor(_ site: SiteProject) -> some View {
        ScrollView {
            Form {
                Section("Publication") {
                    TextField("Noctweb address", text: binding(\.address))
                        .font(.system(.body, design: .monospaced))
                    LabeledContent("Identity") {
                        StatusPill(
                            title: site.publicationIdentity.title,
                            systemImage: site.publicationIdentity.systemImage,
                            color: site.publicationIdentity == .ready ? .green : .orange
                        )
                    }
                    LabeledContent("Current revision") {
                        Text(site.revision == 0 ? "Unpublished" : "\(site.revision)")
                    }
                }

                Section("Content") {
                    TextField("Title", text: binding(\.title))
                    TextField("Subtitle", text: binding(\.subtitle), axis: .vertical)
                        .lineLimit(2...4)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Body")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: binding(\.body))
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 220)
                            .padding(7)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    }
                }

                Section("Appearance") {
                    LabeledContent("Accent") {
                        HStack(spacing: 8) {
                            ForEach(accentChoices, id: \.self) { hex in
                                Button {
                                    model.updateSelectedSite { $0.accentHex = hex }
                                } label: {
                                    Circle()
                                        .fill(Color(hex: hex))
                                        .frame(width: 22, height: 22)
                                        .overlay {
                                            if site.accentHex == hex {
                                                Circle()
                                                    .stroke(.white, lineWidth: 2)
                                                    .padding(3)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Use accent \(hex)")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)
            .padding(.bottom, 18)
        }
    }

    private func preview(_ site: SiteProject) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("Native Preview", systemImage: "macwindow")
                    .font(.headline)
                Spacer()
                Text("SwiftUI · No WebKit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(.bar)
            Divider()
            RenderedSiteView(site: site)
        }
    }

    private var siteSelection: Binding<UUID?> {
        Binding(
            get: { model.selectedSiteID },
            set: { model.selectSite($0) }
        )
    }

    private func binding(_ keyPath: WritableKeyPath<SiteProject, String>) -> Binding<String> {
        Binding(
            get: { model.selectedSite?[keyPath: keyPath] ?? "" },
            set: { value in
                model.updateSelectedSite { $0[keyPath: keyPath] = value }
            }
        )
    }

    private var outcomeImage: String {
        switch model.publicationOutcome {
        case .ready: "circle.dotted"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var outcomeColor: Color {
        switch model.publicationOutcome {
        case .ready: .secondary
        case .running: .blue
        case .succeeded: .green
        case .failed: .red
        }
    }

    private let accentChoices = [
        "#4F8F77",
        "#4B78A8",
        "#7866A6",
        "#AD7748",
        "#A65D69"
    ]
}
