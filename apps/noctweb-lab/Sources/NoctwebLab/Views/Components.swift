import NoctwebUI
import SwiftUI

struct PageHeader<Actions: View>: View {
    let title: String
    let subtitle: String
    let actions: Actions

    init(
        _ title: String,
        subtitle: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                heading
                Spacer(minLength: 20)
                actions
            }

            VStack(alignment: .leading, spacing: 14) {
                heading
                actions
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SectionCard<Content: View>: View {
    let title: String
    let systemImage: String?
    let content: Content

    init(
        _ title: String,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Color.accentColor)
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoctwebTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                Spacer()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(.title, design: .rounded, weight: .semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
    }
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(NoctwebTheme.status, in: Capsule())
    }
}

struct RelayRoleBadge: View {
    let role: LabRelayRole

    var body: some View {
        Label(role.shortTitle, systemImage: role.systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(role.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(NoctwebTheme.status, in: Capsule())
    }
}

struct PublicationPipeline: View {
    let activeStage: PublicationStage
    let outcome: PublicationOutcome

    var body: some View {
        ViewThatFits(in: .horizontal) {
            stageRow
                .fixedSize(horizontal: true, vertical: false)
            compactProgress
        }
    }

    private var stageRow: some View {
        HStack(spacing: 0) {
            ForEach(PublicationStage.allCases) { stage in
                HStack(spacing: 0) {
                    VStack(spacing: 7) {
                        Image(systemName: stage.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .foregroundStyle(foreground(for: stage))
                            .background(background(for: stage), in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(border(for: stage), lineWidth: 1)
                            }
                        Text(stage.title)
                            .font(.caption)
                            .foregroundStyle(stage.rawValue <= activeStage.rawValue ? .primary : .secondary)
                    }
                    .frame(minWidth: 58)

                    if stage != PublicationStage.allCases.last {
                        Rectangle()
                            .fill(stage.rawValue < activeStage.rawValue ? NoctwebTheme.coral : Color.secondary.opacity(0.25))
                            .frame(width: 34, height: 1)
                            .padding(.bottom, 21)
                }
            }
        }
    }
    }

    private var compactProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(activeStage.title, systemImage: activeStage.systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(outcome == .failed ? .red : NoctwebTheme.coral)
                Spacer(minLength: 8)
                Text("\(activeStage.rawValue + 1) of \(PublicationStage.allCases.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(
                value: Double(activeStage.rawValue + 1),
                total: Double(PublicationStage.allCases.count)
            )
            .tint(outcome == .failed ? .red : NoctwebTheme.coral)
        }
        .frame(maxWidth: .infinity)
    }

    private func foreground(for stage: PublicationStage) -> Color {
        if outcome == .failed && stage == activeStage { return .red }
        if stage.rawValue <= activeStage.rawValue { return NoctwebTheme.coral }
        return .secondary
    }

    private func background(for stage: PublicationStage) -> Color {
        if outcome == .failed && stage == activeStage { return .red.opacity(0.12) }
        if stage.rawValue <= activeStage.rawValue { return NoctwebTheme.status }
        return .secondary.opacity(0.08)
    }

    private func border(for stage: PublicationStage) -> Color {
        if outcome == .failed && stage == activeStage { return .red.opacity(0.45) }
        if stage.rawValue <= activeStage.rawValue { return NoctwebTheme.coral.opacity(0.45) }
        return .secondary.opacity(0.2)
    }
}

struct EvidenceRow: View {
    let evidence: TrustEvidence
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: evidence.kind.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(evidence.state.color)
                .frame(width: 30, height: 30)
                .background(evidence.state.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        evidenceHeading
                        Spacer()
                        evidenceState
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        evidenceHeading
                        evidenceState
                    }
                }
                Text(evidence.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !compact {
                    Text(evidence.detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var evidenceHeading: some View {
        Text(evidence.kind.title)
            .font(.subheadline.weight(.semibold))
    }

    private var evidenceState: some View {
        Text(evidence.state.title)
            .font(.caption.weight(.medium))
            .foregroundStyle(evidence.state.color)
    }
}

struct RelayPathView: View {
    let relays: [LabRelayNode]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Label("Runtime", systemImage: "laptopcomputer")
                    .font(.caption.weight(.medium))
                ForEach(Array(relays.enumerated()), id: \.element.id) { _, relay in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Label(relay.role.shortTitle, systemImage: relay.role.systemImage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(relay.role.tint)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.secondary.opacity(0.09), in: Capsule())
    }
}

struct RenderedSiteView: View {
    let title: String
    let subtitle: String
    let content: String
    let accentHex: String
    let revision: Int
    let isVerified: Bool

    init(site: SiteProject) {
        self.title = site.title
        self.subtitle = site.subtitle
        self.content = site.body
        self.accentHex = site.accentHex
        self.revision = site.revision
        self.isVerified = false
    }

    init(snapshot: ResolvedSiteSnapshot) {
        self.title = snapshot.title
        self.subtitle = snapshot.subtitle
        self.content = snapshot.body
        self.accentHex = snapshot.accentHex
        self.revision = Int(snapshot.revision)
        self.isVerified = true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 9) {
                    Rectangle()
                        .fill(Color(hex: accentHex))
                        .frame(width: 32, height: 2)
                    Text(
                        isVerified
                            ? "Verified Noctweb publication"
                            : "Native draft preview"
                    )
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 28)

                Text(title)
                    .font(.system(size: 42, weight: .medium, design: .serif))
                    .tracking(-1.2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()
                    .padding(.vertical, 36)

                Text(content)
                    .font(.body)
                    .lineSpacing(7)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack {
                        Label("Static native profile", systemImage: "swift")
                        Spacer()
                        Text("Revision \(revision)")
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Static native profile", systemImage: "swift")
                        Text("Revision \(revision)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 42)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(hex: accentHex).opacity(0.08),
                    Color(nsColor: .textBackgroundColor)
                ],
                startPoint: .topTrailing,
                endPoint: .center
            )
        )
    }
}

extension LabRelayRole {
    var tint: Color {
        switch self {
        case .standard: .blue
        case .passthrough: .purple
        case .host: .green
        }
    }
}

extension EvidenceState {
    var color: Color {
        switch self {
        case .pending: .secondary
        case .accepted: .green
        case .warning: .orange
        case .rejected: .red
        }
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let number = UInt64(value, radix: 16) ?? 0x4F8F77
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
