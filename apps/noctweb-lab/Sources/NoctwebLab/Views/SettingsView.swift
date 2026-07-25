import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Workspace Storage") {
                LabeledContent("Mode", value: "Local persistent workspace")
                LabeledContent("Saved workspaces", value: "\(model.workspaces.count)")
                Text("Site drafts, topology settings, and test runs are stored on this Mac. Protocol identity is not derived from an application account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Publication Security") {
                LabeledContent("Identity scope", value: "Per publication")
                LabeledContent("Renderer", value: "Native SwiftUI")
                LabeledContent("WebKit and scripts", value: "Unavailable")
                Text("Site content is rendered as bounded native fields. The runtime never evaluates HTML, Markdown, JavaScript, or same-origin capabilities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Test Runs") {
                Toggle("Preserve run history", isOn: $model.preserveRunHistory)
                Text("Saved runs include scenario steps and assertions, but never plaintext private communications or secret key material.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Experimental Profile") {
                LabeledContent("Profile", value: "noctweb-lab-v0")
                LabeledContent("Consensus", value: "Deterministic test adapter")
                Text("This profile is a development surface and is not a stable Noctweave Net wire format.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .padding(.top, 8)
    }
}
