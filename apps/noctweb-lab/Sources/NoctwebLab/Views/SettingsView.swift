import NoctwebLabCore
import NoctwebUI
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var appearance: NoctwebAppearanceStore

    private let columns = [
        GridItem(.adaptive(minimum: 340), spacing: 18, alignment: .top)
    ]

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

                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    SectionCard("Workspace storage", systemImage: "externaldrive") {
                        settingsRows([
                            ("Mode", "Local persistent workspace"),
                            ("Saved workspaces", "\(model.workspaces.count)")
                        ])
                        boundaryText(
                            "Site drafts and relay endpoints stay on this Mac. Publisher authorization is never saved, and protocol identity is not derived from an application account."
                        )
                    }

                    SectionCard("Publication security", systemImage: "signature") {
                        settingsRows([
                            ("Identity scope", "Per publication"),
                            ("Name scope", "Relay namespace"),
                            ("Renderer", "Isolated WebKit"),
                            ("Website scripts", "Same-publication only")
                        ])
                        boundaryText(
                            "Every site has a publisher-scoped Keychain identity. Only verified bundle bytes run; the website receives no native bridge or unrestricted external network access."
                        )
                    }

                    SectionCard("Routing policy", systemImage: "point.3.connected.trianglepath.dotted") {
                        settingsRows([
                            ("Authority order", "Federation → Relay → Publisher → Visitor"),
                            ("Open fallback", "Direct host retrieval")
                        ])
                        boundaryText(
                            "The first non-open directive governs retrieval. Solo mode leaves federation authority open; passthrough is required only when effective policy selects one hop."
                        )
                    }

                    SectionCard("Hosted profile", systemImage: "shippingbox.and.arrow.backward") {
                        settingsRows([
                            ("Capsule", HostedCapsuleEnvelope.profile),
                            ("Bundle limit", "1 MiB per hosted object"),
                            ("Relay module", "nw.net-host@1"),
                            ("Consensus", "Not claimed")
                        ])
                        boundaryText(
                            "The Lab verifies publisher signatures, content hashes, and relay hosting receipts. A successful host operation does not establish global naming or finality."
                        )
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(NoctwebTheme.canvas)
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
}
