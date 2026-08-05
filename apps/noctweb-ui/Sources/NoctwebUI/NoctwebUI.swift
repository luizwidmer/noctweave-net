import SwiftUI

public enum NoctwebAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var systemImage: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
public final class NoctwebAppearanceStore: ObservableObject {
    public static let standard = NoctwebAppearanceStore()

    @Published public var selection: NoctwebAppearance {
        didSet {
            defaults.set(selection.rawValue, forKey: key)
        }
    }

    private let defaults: UserDefaults
    private let key: String

    public init(
        defaults: UserDefaults = .standard,
        key: String = "net.noctweave.noctweb.appearance"
    ) {
        self.defaults = defaults
        self.key = key
        selection = NoctwebAppearance(
            rawValue: defaults.string(forKey: key) ?? ""
        ) ?? .system
    }
}

public enum NoctwebTheme {
    public static let quantumViolet = Color(
        red: 123.0 / 255.0,
        green: 97.0 / 255.0,
        blue: 255.0 / 255.0
    )
    public static let transitBlue = Color(
        red: 91.0 / 255.0,
        green: 156.0 / 255.0,
        blue: 250.0 / 255.0
    )
    public static let signalTeal = Color(
        red: 61.0 / 255.0,
        green: 213.0 / 255.0,
        blue: 197.0 / 255.0
    )
    public static let night = Color(
        red: 8.0 / 255.0,
        green: 11.0 / 255.0,
        blue: 22.0 / 255.0
    )
    public static let raised = Color(
        red: 18.0 / 255.0,
        green: 22.0 / 255.0,
        blue: 37.0 / 255.0
    )
    public static let soft = Color(
        red: 28.0 / 255.0,
        green: 32.0 / 255.0,
        blue: 48.0 / 255.0
    )
    public static let primaryText = Color(
        red: 243.0 / 255.0,
        green: 245.0 / 255.0,
        blue: 250.0 / 255.0
    )
    public static let secondaryText = Color(
        red: 168.0 / 255.0,
        green: 173.0 / 255.0,
        blue: 189.0 / 255.0
    )
    public static let accent = quantumViolet
    public static let accentStrong = transitBlue

    public static let canvas = adaptive(
        light: NSColor(
            srgbRed: 245.0 / 255.0,
            green: 247.0 / 255.0,
            blue: 252.0 / 255.0,
            alpha: 1
        ),
        dark: NSColor(
            srgbRed: 8.0 / 255.0,
            green: 11.0 / 255.0,
            blue: 22.0 / 255.0,
            alpha: 1
        )
    )
    public static let surface = adaptive(
        light: NSColor(
            srgbRed: 243.0 / 255.0,
            green: 245.0 / 255.0,
            blue: 250.0 / 255.0,
            alpha: 0.96
        ),
        dark: NSColor(
            srgbRed: 18.0 / 255.0,
            green: 22.0 / 255.0,
            blue: 37.0 / 255.0,
            alpha: 0.96
        )
    )
    public static let card = adaptive(
        light: NSColor(
            srgbRed: 1,
            green: 1,
            blue: 1,
            alpha: 0.98
        ),
        dark: NSColor(
            srgbRed: 28.0 / 255.0,
            green: 32.0 / 255.0,
            blue: 48.0 / 255.0,
            alpha: 0.96
        )
    )
    public static let input = adaptive(
        light: NSColor(
            srgbRed: 1,
            green: 1,
            blue: 1,
            alpha: 0.9
        ),
        dark: NSColor(
            srgbRed: 13.0 / 255.0,
            green: 17.0 / 255.0,
            blue: 32.0 / 255.0,
            alpha: 0.86
        )
    )
    public static let navigation = adaptive(
        light: NSColor(
            srgbRed: 238.0 / 255.0,
            green: 241.0 / 255.0,
            blue: 248.0 / 255.0,
            alpha: 0.97
        ),
        dark: NSColor(
            srgbRed: 13.0 / 255.0,
            green: 17.0 / 255.0,
            blue: 32.0 / 255.0,
            alpha: 0.97
        )
    )
    public static let status = accent.opacity(0.14)
    public static let border = adaptive(
        light: NSColor(
            srgbRed: 103.0 / 255.0,
            green: 77.0 / 255.0,
            blue: 217.0 / 255.0,
            alpha: 0.24
        ),
        dark: NSColor(
            srgbRed: 91.0 / 255.0,
            green: 156.0 / 255.0,
            blue: 250.0 / 255.0,
            alpha: 0.24
        )
    )
    public static let softShadow = adaptive(
        light: NSColor(
            srgbRed: 24.0 / 255.0,
            green: 35.0 / 255.0,
            blue: 74.0 / 255.0,
            alpha: 0.16
        ),
        dark: NSColor(
            srgbRed: 0,
            green: 0,
            blue: 0,
            alpha: 0.34
        )
    )

    private static func adaptive(
        light: NSColor,
        dark: NSColor
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(
                    from: [.darkAqua, .aqua]
                ) == .darkAqua ? dark : light
            }
        )
    }
}

public enum NoctwebProduct: Sendable {
    case browser
    case lab
}

public struct NoctwebProductIcon: View {
    private let product: NoctwebProduct

    public init(_ product: NoctwebProduct) {
        self.product = product
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            ZStack {
                RoundedRectangle(
                    cornerRadius: side * 0.245,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: backgroundColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: side * 0.245,
                        style: .continuous
                    )
                    .strokeBorder(
                        borderColor,
                        lineWidth: max(0.75, side * 0.012)
                    )
                }

                switch product {
                case .browser:
                    browserGlyph(side: side)
                case .lab:
                    offsetVeilGlyph(side: side)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func browserGlyph(side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: side * 0.115,
                style: .continuous
            )
            .fill(NoctwebTheme.night.opacity(0.36))
            .overlay {
                RoundedRectangle(
                    cornerRadius: side * 0.115,
                    style: .continuous
                )
                .strokeBorder(
                    NoctwebTheme.transitBlue,
                    lineWidth: max(1, side * 0.047)
                )
            }
            .padding(side * 0.16)

            Path { path in
                path.move(
                    to: CGPoint(x: side * 0.16, y: side * 0.33)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.84, y: side * 0.33)
                )
            }
            .stroke(
                NoctwebTheme.transitBlue,
                style: StrokeStyle(lineWidth: max(1, side * 0.047))
            )

            ForEach([-0.12, 0, 0.12], id: \.self) { offset in
                corridorPath(
                    side: side,
                    verticalOffset: side * offset
                )
                .stroke(
                    NoctwebTheme.primaryText,
                    style: StrokeStyle(
                        lineWidth: max(1, side * 0.043),
                        lineJoin: .miter
                    )
                )

                corridorPath(
                    side: side,
                    verticalOffset: side * (offset - 0.006)
                )
                .stroke(
                    NoctwebTheme.signalTeal,
                    style: StrokeStyle(
                        lineWidth: max(1, side * 0.01),
                        lineJoin: .miter
                    )
                )
            }
        }
    }

    private func corridorPath(
        side: CGFloat,
        verticalOffset: CGFloat = 0
    ) -> Path {
        Path { path in
            path.move(
                to: CGPoint(
                    x: side * 0.24,
                    y: side * 0.59 + verticalOffset
                )
            )
            path.addLine(
                to: CGPoint(
                    x: side * 0.455,
                    y: side * 0.59 + verticalOffset
                )
            )
            path.addLine(
                to: CGPoint(
                    x: side * 0.56,
                    y: side * 0.645 + verticalOffset
                )
            )
            path.addLine(
                to: CGPoint(
                    x: side * 0.76,
                    y: side * 0.645 + verticalOffset
                )
            )
        }
    }

    private func offsetVeilGlyph(side: CGFloat) -> some View {
        ZStack {
            Path { path in
                path.move(
                    to: CGPoint(x: side * 0.375, y: side * 0.125)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.875, y: side * 0.125)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.875, y: side * 0.6875)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.546875, y: side * 0.5234375)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.546875, y: side * 0.4296875)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.375, y: side * 0.34375)
                )
                path.closeSubpath()
            }
            .fill(NoctwebTheme.quantumViolet)

            Path { path in
                path.move(
                    to: CGPoint(x: side * 0.125, y: side * 0.3125)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.453125, y: side * 0.4765625)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.453125, y: side * 0.5703125)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.625, y: side * 0.65625)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.625, y: side * 0.875)
                )
                path.addLine(
                    to: CGPoint(x: side * 0.125, y: side * 0.875)
                )
                path.closeSubpath()
            }
            .fill(NoctwebTheme.signalTeal)
        }
    }

    private var backgroundColors: [Color] {
        switch product {
        case .browser:
            [NoctwebTheme.raised, NoctwebTheme.night]
        case .lab:
            [NoctwebTheme.primaryText, NoctwebTheme.secondaryText]
        }
    }

    private var borderColor: Color {
        switch product {
        case .browser:
            NoctwebTheme.transitBlue.opacity(0.16)
        case .lab:
            NoctwebTheme.quantumViolet.opacity(0.16)
        }
    }
}

public struct NoctwebChromeModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .tint(NoctwebTheme.accent)
            .accentColor(NoctwebTheme.accent)
    }
}

public extension View {
    func noctwebChrome() -> some View {
        modifier(NoctwebChromeModifier())
    }

    func noctwebAppearance(_ appearance: NoctwebAppearance) -> some View {
        preferredColorScheme(appearance.colorScheme)
            .noctwebChrome()
    }
}
