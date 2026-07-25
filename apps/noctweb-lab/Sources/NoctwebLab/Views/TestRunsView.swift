import SwiftUI

struct TestRunsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedRunID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                "Test Runs",
                subtitle: "Execute deterministic failure scenarios and retain reviewable assertions."
            ) {
                Button {
                    model.runSelectedScenario()
                    selectedRunID = model.activeWorkspace?.runs.first?.id
                } label: {
                    Label("Run Scenario", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedScenario == nil)
            }
            .padding(24)

            Divider()

            HSplitView {
                scenarioLibrary
                    .frame(minWidth: 290, idealWidth: 340, maxWidth: 390)
                runWorkspace
                    .frame(minWidth: 650)
            }
        }
    }

    private var scenarioLibrary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Scenario Library")
                .font(.headline)
                .padding(16)
            Divider()

            List(selection: $model.selectedScenarioID) {
                ForEach(model.scenarios) { scenario in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(scenario.name)
                            .font(.subheadline.weight(.medium))
                        Text(scenario.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 6)
                    .tag(Optional(scenario.id))
                }
            }
            .listStyle(.inset)
        }
        .background(.regularMaterial)
    }

    private var runWorkspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let scenario = model.selectedScenario {
                    SectionCard("Expected behavior", systemImage: "target") {
                        Text(scenario.summary)
                            .font(.body)
                        Label(scenario.expectedResult, systemImage: "checkmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Run History")
                        .font(.title2.weight(.semibold))
                    Spacer()
                    if !(model.activeWorkspace?.runs.isEmpty ?? true) {
                        Button("Clear History", role: .destructive) {
                            model.clearRunHistory()
                            selectedRunID = nil
                        }
                    }
                }

                if let runs = model.activeWorkspace?.runs, !runs.isEmpty {
                    ForEach(runs) { run in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { selectedRunID == run.id },
                                set: { selectedRunID = $0 ? run.id : nil }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(Array(run.events.enumerated()), id: \.offset) { index, event in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(index + 1)")
                                            .font(.system(.caption, design: .rounded, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 24, height: 24)
                                            .background(Color.accentColor.opacity(0.1), in: Circle())
                                        Text(event)
                                            .font(.callout)
                                    }
                                }
                                Divider()
                                Label(run.assertion, systemImage: "checkmark.seal")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(.green)
                            }
                            .padding(.top, 14)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: run.result == .passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(run.result == .passed ? .green : .red)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(run.scenarioName)
                                        .font(.headline)
                                    Text(run.startedAt.formatted(date: .abbreviated, time: .standard))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(run.durationMilliseconds) ms")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.5))
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Test Runs",
                        systemImage: "checklist",
                        description: Text("Choose a scenario and run it to create a deterministic evidence trail.")
                    )
                    .frame(height: 260)
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
    }
}
