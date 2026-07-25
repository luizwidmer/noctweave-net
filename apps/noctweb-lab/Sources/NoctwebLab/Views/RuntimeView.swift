import SwiftUI

struct RuntimeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    "Noctweb Runtime",
                    subtitle: "Resolve publication addresses and render accepted content directly with SwiftUI."
                ) {
                    Picker("Route", selection: $model.routeMode) {
                        ForEach(RouteMode.allCases) { route in
                            Text(route.title)
                                .tag(route)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                    .onChange(of: model.routeMode) {
                        model.reloadRuntime()
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        model.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!model.canGoBack)
                    .help("Back")

                    Button {
                        model.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!model.canGoForward)
                    .help("Forward")

                    Button {
                        model.reloadRuntime()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Resolve again")

                    TextField("noct://publication/", text: $model.runtimeAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            model.navigateRuntime()
                        }

                    Button("Resolve") {
                        model.navigateRuntime()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)

            Divider()

            HSplitView {
                runtimeCanvas
                    .frame(minWidth: 620)
                evidenceSidebar
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
            }
        }
        .task {
            if case .idle = model.runtimeResult {
                model.navigateRuntime()
            }
        }
    }

    @ViewBuilder
    private var runtimeCanvas: some View {
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
                    HStack {
                        StatusPill(
                            title: "Object accepted",
                            systemImage: "checkmark.shield.fill",
                            color: .green
                        )
                        Spacer()
                        RelayPathView(
                            relays: relayPath.compactMap { id in
                                workspace.relays.first(where: { $0.id == id })
                            }
                        )
                    }
                    .padding(12)
                    .background(.bar)
                    Divider()
                    RenderedSiteView(snapshot: snapshot)
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

    private var evidenceSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Trust Evidence")
                    .font(.title3.weight(.semibold))

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
            .padding(20)
        }
        .background(.regularMaterial)
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
}
