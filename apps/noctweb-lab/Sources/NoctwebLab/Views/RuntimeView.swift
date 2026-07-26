import SwiftUI

struct RuntimeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var evidenceExpanded = false
    @State private var websiteReloadToken = UUID()

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                runtimeHeader(width: proxy.size.width)

                Divider()

                if proxy.size.width >= evidenceSidebarBreakpoint {
                    HStack(spacing: 0) {
                        runtimeCanvas(compact: false)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        evidenceSidebar
                            .frame(width: min(330, max(280, proxy.size.width * 0.32)))
                    }
                } else {
                    VStack(spacing: 0) {
                        runtimeCanvas(compact: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        compactEvidencePanel
                    }
                }
            }
        }
        .task {
            if case .idle = model.runtimeResult {
                model.navigateRuntime()
            }
        }
    }

    private func runtimeHeader(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if width >= headerBreakpoint {
                HStack(alignment: .top, spacing: 20) {
                    runtimeHeaderCopy(compact: false)
                    Spacer(minLength: 20)
                    routePicker
                        .frame(width: 220)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    runtimeHeaderCopy(compact: true)
                    routePicker
                        .frame(maxWidth: 320)
                }
            }

            navigationControls(compact: width < navigationBreakpoint)
        }
        .padding(width < headerBreakpoint ? 16 : 24)
    }

    private func runtimeHeaderCopy(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Noctweb Runtime")
                .font(compact ? .title.weight(.semibold) : .largeTitle.weight(.semibold))
            Text("Resolve, verify, and run signed website bundles in an isolated native web runtime.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var routePicker: some View {
        Picker("Route", selection: $model.routeMode) {
            ForEach(RouteMode.allCases) { route in
                Text(route.title)
                    .tag(route)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: model.routeMode) {
            websiteReloadToken = UUID()
            model.reloadRuntime()
        }
    }

    @ViewBuilder
    private func navigationControls(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 9) {
                navigationButtons
                addressControls
            }
        } else {
            HStack(spacing: 8) {
                navigationButtons
                addressControls
            }
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 6) {
            Button {
                websiteReloadToken = UUID()
                model.goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!model.canGoBack)
            .help("Back")

            Button {
                websiteReloadToken = UUID()
                model.goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!model.canGoForward)
            .help("Forward")

            Button {
                websiteReloadToken = UUID()
                model.reloadRuntime()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Resolve again")
        }
    }

    private var addressControls: some View {
        HStack(spacing: 8) {
            TextField("noct://publication/", text: $model.runtimeAddress)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    websiteReloadToken = UUID()
                    model.navigateRuntime()
                }

            Button("Resolve") {
                websiteReloadToken = UUID()
                model.navigateRuntime()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func runtimeCanvas(compact: Bool) -> some View {
        switch model.runtimeResult {
        case .idle:
            ContentUnavailableView(
                "Ready to Resolve",
                systemImage: "safari",
                description: Text("Enter a Noctweb address to open a publication.")
            )

        case let .resolved(snapshot, relayPath):
            if let workspace = model.activeWorkspace {
                VStack(spacing: 0) {
                    resolutionStatus(
                        relays: relayPath.compactMap { id in
                            workspace.relays.first(where: { $0.id == id })
                        },
                        compact: compact
                    )
                    .padding(12)
                    .background(.bar)
                    Divider()
                    VerifiedWebsiteWebView(
                        bundle: snapshot.bundle,
                        origin: snapshot.publisherID,
                        reloadToken: websiteReloadToken
                    )
                    .id(snapshot.objectID)
                }
            } else {
                unavailableView(
                    title: "Workspace Unavailable",
                    message: "The verified snapshot is retained, but no workspace is selected.",
                    rejected: false
                )
            }

        case let .unavailable(message):
            unavailableView(title: "Site Unavailable", message: message, rejected: false)

        case let .rejected(message):
            unavailableView(title: "Object Rejected", message: message, rejected: true)
        }
    }

    @ViewBuilder
    private func resolutionStatus(relays: [LabRelayNode], compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                StatusPill(
                    title: "Object accepted",
                    systemImage: "checkmark.shield.fill",
                    color: .green
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    RelayPathView(relays: relays)
                }
            }
        } else {
            HStack {
                StatusPill(
                    title: "Object accepted",
                    systemImage: "checkmark.shield.fill",
                    color: .green
                )
                Spacer()
                RelayPathView(relays: relays)
            }
        }
    }

    private var evidenceSidebar: some View {
        ScrollView {
            evidenceContent(showTitle: true)
            .padding(20)
        }
        .background(.regularMaterial)
    }

    private var compactEvidencePanel: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    evidenceExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Label("Trust Evidence", systemImage: "checkmark.shield")
                        .font(.headline)
                    Spacer()
                    Text("\(model.trustEvidence.count) checks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: evidenceExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .frame(height: 46)

            if evidenceExpanded {
                Divider()
                ScrollView {
                    evidenceContent(showTitle: false)
                        .padding(16)
                }
                .frame(maxHeight: 220)
            }
        }
        .background(.regularMaterial)
    }

    private func evidenceContent(showTitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if showTitle {
                Text("Trust Evidence")
                    .font(.title3.weight(.semibold))
            }

            Text("Each claim is evaluated separately. Transport success never substitutes for identity or integrity.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(model.trustEvidence) { evidence in
                EvidenceRow(evidence: evidence)
                if evidence.id != model.trustEvidence.last?.id {
                    Divider()
                }
            }

            Button("Open Inspector") {
                model.selection = .inspector
            }
        }
    }

    private func unavailableView(title: String, message: String, rejected: Bool) -> some View {
        ContentUnavailableView {
            Label(
                title,
                systemImage: rejected ? "xmark.shield.fill" : "antenna.radiowaves.left.and.right.slash"
            )
        } description: {
            Text(message)
        } actions: {
            Button("Resolve Again") {
                model.reloadRuntime()
            }
        }
    }

    private let evidenceSidebarBreakpoint: CGFloat = 920
    private let headerBreakpoint: CGFloat = 760
    private let navigationBreakpoint: CGFloat = 700
}
