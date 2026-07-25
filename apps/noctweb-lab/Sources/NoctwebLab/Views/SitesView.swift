import SwiftUI

private enum SiteWorkspacePane: String, CaseIterable, Identifiable {
    case editor
    case preview

    var id: Self { self }

    var title: String {
        switch self {
        case .editor: "Editor"
        case .preview: "Preview"
        }
    }
}

struct SitesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var compactPane: SiteWorkspacePane = .editor

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= siteLibraryBreakpoint {
                HStack(spacing: 0) {
                    siteList
                        .frame(width: 240)
                    Divider()
                    selectedWorkspace(width: proxy.size.width - 241)
                }
            } else {
                VStack(spacing: 0) {
                    compactSiteSelector
                    Divider()
                    selectedWorkspace(width: proxy.size.width)
                }
            }
        }
    }

    @ViewBuilder
    private func selectedWorkspace(width: CGFloat) -> some View {
        if let site = model.selectedSite {
            siteWorkspace(site, width: width)
        } else {
            ContentUnavailableView(
                "No Site Selected",
                systemImage: "rectangle.stack.badge.plus",
                description: Text("Create a site in this workspace to begin.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var compactSiteSelector: some View {
        HStack(spacing: 12) {
            Picker("Site", selection: siteSelection) {
                if model.selectedSiteID == nil {
                    Text("Select a site")
                        .tag(UUID?.none)
                }
                ForEach(model.activeWorkspace?.sites ?? []) { site in
                    Text(site.title)
                        .tag(Optional(site.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 360, alignment: .leading)

            Spacer(minLength: 8)

            Button {
                model.createSite()
            } label: {
                Label("New Site", systemImage: "plus")
            }
            .help("Create a site")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(.regularMaterial)
    }

    private func siteWorkspace(_ site: SiteProject, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                publicationHeader(site, compact: width < headerBreakpoint)

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
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(width < headerBreakpoint ? 16 : 24)

            Divider()

            if width >= editorPreviewBreakpoint {
                HStack(spacing: 0) {
                    editor(site)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    preview(site)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                compactWorkspace(site)
            }
        }
    }

    @ViewBuilder
    private func publicationHeader(_ site: SiteProject, compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 14) {
                headerCopy(site, compact: true)
                publishControls
            }
        } else {
            HStack(alignment: .top, spacing: 20) {
                headerCopy(site, compact: false)
                Spacer(minLength: 20)
                publishControls
            }
        }
    }

    private func headerCopy(_ site: SiteProject, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(site.title)
                .font(compact ? .title.weight(.semibold) : .largeTitle.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Edit the publication, review its native preview, then publish a verified revision.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var publishControls: some View {
        HStack(spacing: 10) {
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
    }

    private func compactWorkspace(_ site: SiteProject) -> some View {
        VStack(spacing: 0) {
            Picker("Workspace pane", selection: $compactPane) {
                ForEach(SiteWorkspacePane.allCases) { pane in
                    Text(pane.title)
                        .tag(pane)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 320)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            Group {
                switch compactPane {
                case .editor:
                    editor(site)
                case .preview:
                    preview(site)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private let siteLibraryBreakpoint: CGFloat = 1_080
    private let editorPreviewBreakpoint: CGFloat = 840
    private let headerBreakpoint: CGFloat = 760
}
