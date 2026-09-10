import NoctwebLabCore
import NoctwebUI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var appearance: NoctwebAppearanceStore

    @State private var showResetConfirmation = false
    @State private var resetConfirmation = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    "Settings",
                    subtitle: "Appearance, local storage, and publication boundaries."
                ) {
                    EmptyView()
                }

                SectionCard("Appearance", systemImage: "circle.lefthalf.filled") {
                    Picker("Theme", selection: $appearance.selection) {
                        ForEach(NoctwebAppearance.allCases) { option in
                            Label(option.title, systemImage: option.systemImage)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("System follows macOS. Light and Dark are remembered independently by Noctweb Lab.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                AppSupportCard()

                SectionCard("Reset app", systemImage: "trash") {
                    Text("Remove all local workspaces, site drafts, publisher signing keys, history, and settings. Published copies on relays and exported files remain. Losing a publisher key prevents further updates signed with that key.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Purge and Reset App…", role: .destructive) {
                        resetConfirmation = ""
                        showResetConfirmation = true
                    }
                    .accessibilityIdentifier("app.purgeAndReset")
                    .disabled(model.isResetting)
                    if model.isResetting { ProgressView("Resetting…") }
                    if model.resetIsPending, let error = model.operationError {
                        Text(error).font(.callout).foregroundStyle(.red)
                    }
                }

                SectionCard("Technical details", systemImage: "info.circle") {
                    DisclosureGroup("Storage, security, and routing boundaries") {
                        VStack(alignment: .leading, spacing: 18) {
                            detailSection("Workspace storage", rows: [
                                ("Mode", "Local persistent workspace"),
                                ("Saved workspaces", "\(model.workspaces.count)")
                            ], boundary: "Site drafts and relay endpoints stay on this Mac. Publisher authorization is never saved, and protocol identity is not derived from an application account.")
                            Divider()
                            detailSection("Publication security", rows: [
                                ("Identity scope", "Per publication"),
                                ("Name scope", "Relay namespace"),
                                ("Renderer", "Isolated WebKit"),
                                ("Website scripts", "Same-publication only")
                            ], boundary: "Every site has a publisher-scoped Keychain identity. Only verified bundle bytes run; the website receives no native bridge or unrestricted external network access.")
                            Divider()
                            detailSection("Routing and hosting", rows: [
                                ("Authority order", "Federation → Relay → Publisher → Visitor"),
                                ("Hosted profile", HostedCapsuleEnvelope.profile),
                                ("Bundle limit", "1 MiB"),
                                ("Consensus", "Not claimed")
                            ], boundary: "The Lab verifies publisher signatures, content hashes, and relay hosting receipts. Hosting does not establish global naming or finality.")
                        }
                        .padding(.top, 10)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(NoctwebTheme.canvas)
        .alert("Purge and reset Noctweb Lab?", isPresented: $showResetConfirmation) {
            TextField("Type RESET to confirm", text: $resetConfirmation)
            Button("Cancel", role: .cancel) {}
            Button("Purge and Reset", role: .destructive) {
                Task {
                    await model.purgeAndReset()
                    if !model.resetIsPending { appearance.reset() }
                }
            }.disabled(resetConfirmation != "RESET")
        } message: {
            Text("This permanently removes this app’s local data and publisher keys. It cannot be undone. Type RESET to continue.")
        }
    }

    private func settingsRows(_ rows: [(String, String)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(row.0)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    Text(row.1)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                .font(.callout)
                .padding(.vertical, 9)

                if index < rows.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func boundaryText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detailSection(
        _ title: String,
        rows: [(String, String)],
        boundary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            settingsRows(rows)
            boundaryText(boundary)
        }
    }
}
