import NoctwebLabCore
import NoctwebUI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var appearance: NoctwebAppearanceStore

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $appearance.selection) {
                    ForEach(NoctwebAppearance.allCases) { option in
                        Label(option.title, systemImage: option.systemImage)
                            .tag(option)
                    }
                }
                .pickerStyle(.segmented)
                Text("System follows macOS. An explicit Light or Dark choice is remembered by this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Workspace Storage") {
                LabeledContent("Mode", value: "Local persistent workspace")
                LabeledContent("Saved workspaces", value: "\(model.workspaces.count)")
                Text("Site drafts and relay endpoints are stored on this Mac. Publisher authorization is never saved, and protocol identity is not derived from an application account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Publication Security") {
                LabeledContent("Identity scope", value: "Per publication")
                LabeledContent("Name scope", value: "Relay namespace")
                LabeledContent("Renderer", value: "Isolated WebKit")
                LabeledContent("Website scripts", value: "Same-publication only")
                Text("Every site has a publisher-scoped Keychain identity. Only verified bundle bytes run, with no native bridge and website access to external network resources blocked by runtime policy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Routing Policy") {
                LabeledContent(
                    "Authority order",
                    value: "Federation → Relay operator → Publisher → Visitor"
                )
                LabeledContent("Open fallback", value: "Direct host retrieval")
                Text("The first non-open directive governs retrieval. Solo mode keeps federation authority open; passthrough is required only when the effective directive selects one hop.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hosted Profile") {
                LabeledContent("Capsule", value: HostedCapsuleEnvelope.profile)
                LabeledContent("Bundle limit", value: "1 MiB per hosted object")
                LabeledContent("Relay module", value: "nw.net-host@1")
                LabeledContent("Consensus", value: "Not claimed")
                Text("The Lab verifies publisher signatures, content hashes, and relay hosting receipts. A successful host operation does not establish global naming or finality.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .padding(.top, 8)
    }
}
