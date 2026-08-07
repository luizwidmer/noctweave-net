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
    public static let warmIvory = Color(
        red: 250.0 / 255.0,
        green: 243.0 / 255.0,
        blue: 234.0 / 255.0
    )
    public static let paleSand = Color(
        red: 235.0 / 255.0,
        green: 199.0 / 255.0,
        blue: 175.0 / 255.0
    )
    public static let mutedCoral = Color(
        red: 201.0 / 255.0,
        green: 106.0 / 255.0,
        blue: 97.0 / 255.0
    )
    public static let deepWine = Color(
        red: 146.0 / 255.0,
        green: 45.0 / 255.0,
        blue: 53.0 / 255.0
    )
    public static let plumBlack = Color(
        red: 27.0 / 255.0,
        green: 18.0 / 255.0,
        blue: 23.0 / 255.0
    )
    public static let success = Color(
        red: 121.0 / 255.0,
        green: 198.0 / 255.0,
        blue: 163.0 / 255.0
    )
    public static let primaryText = Color(
        red: 250.0 / 255.0,
        green: 243.0 / 255.0,
        blue: 234.0 / 255.0
    )
    public static let secondaryText = Color(
        red: 189.0 / 255.0,
        green: 169.0 / 255.0,
        blue: 170.0 / 255.0
    )
    public static let accent = mutedCoral
    public static let accentStrong = deepWine

    public static let canvas = adaptive(
        light: NSColor(
            srgbRed: 250.0 / 255.0,
            green: 246.0 / 255.0,
            blue: 242.0 / 255.0,
            alpha: 1
        ),
        dark: NSColor(
            srgbRed: 18.0 / 255.0,
            green: 11.0 / 255.0,
            blue: 15.0 / 255.0,
            alpha: 1
        )
    )
    public static let surface = adaptive(
        light: NSColor(
            srgbRed: 250.0 / 255.0,
            green: 243.0 / 255.0,
            blue: 234.0 / 255.0,
            alpha: 0.96
        ),
        dark: NSColor(
            srgbRed: 27.0 / 255.0,
            green: 18.0 / 255.0,
            blue: 23.0 / 255.0,
            alpha: 0.96
        )
    )
    public static let card = adaptive(
        light: NSColor(
            srgbRed: 1,
            green: 253.0 / 255.0,
            blue: 251.0 / 255.0,
            alpha: 0.98
        ),
        dark: NSColor(
            srgbRed: 42.0 / 255.0,
            green: 27.0 / 255.0,
            blue: 33.0 / 255.0,
            alpha: 0.96
        )
    )
    public static let input = adaptive(
        light: NSColor(
            srgbRed: 247.0 / 255.0,
            green: 238.0 / 255.0,
            blue: 233.0 / 255.0,
            alpha: 0.9
        ),
        dark: NSColor(
            srgbRed: 23.0 / 255.0,
            green: 15.0 / 255.0,
            blue: 19.0 / 255.0,
            alpha: 0.86
        )
    )
    public static let navigation = adaptive(
        light: NSColor(
            srgbRed: 247.0 / 255.0,
            green: 238.0 / 255.0,
            blue: 233.0 / 255.0,
            alpha: 0.97
        ),
        dark: NSColor(
            srgbRed: 23.0 / 255.0,
            green: 15.0 / 255.0,
            blue: 19.0 / 255.0,
            alpha: 0.97
        )
    )
    public static let status = accent.opacity(0.14)
    public static let border = adaptive(
        light: NSColor(
            srgbRed: 217.0 / 255.0,
            green: 198.0 / 255.0,
            blue: 193.0 / 255.0,
            alpha: 0.24
        ),
        dark: NSColor(
            srgbRed: 86.0 / 255.0,
            green: 49.0 / 255.0,
            blue: 58.0 / 255.0,
            alpha: 0.24
        )
    )
    public static let softShadow = adaptive(
        light: NSColor(
            srgbRed: 69.0 / 255.0,
            green: 36.0 / 255.0,
            blue: 46.0 / 255.0,
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
            ZStack {
                upperPlatePath(side: side)
                    .fill(
                        LinearGradient(
                            colors: [NoctwebTheme.warmIvory, NoctwebTheme.paleSand],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                upperCorridorPath(side: side)
                    .fill(.black)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()

            ZStack {
                lowerPlatePath(side: side)
                    .fill(
                        LinearGradient(
                            colors: [NoctwebTheme.mutedCoral, NoctwebTheme.deepWine],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                lowerCorridorPath(side: side)
                    .fill(.black)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }

    private func upperPlatePath(side: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: side * 0.375, y: side * 0.125))
            path.addLine(to: CGPoint(x: side * 0.875, y: side * 0.125))
            path.addLine(to: CGPoint(x: side * 0.875, y: side * 0.6875))
            path.addLine(to: CGPoint(x: side * 0.546875, y: side * 0.5234375))
            path.addLine(to: CGPoint(x: side * 0.546875, y: side * 0.4296875))
            path.addLine(to: CGPoint(x: side * 0.375, y: side * 0.34375))
            path.closeSubpath()
        }
    }

    private func lowerPlatePath(side: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: side * 0.125, y: side * 0.3125))
            path.addLine(to: CGPoint(x: side * 0.453125, y: side * 0.4765625))
            path.addLine(to: CGPoint(x: side * 0.453125, y: side * 0.5703125))
            path.addLine(to: CGPoint(x: side * 0.625, y: side * 0.65625))
            path.addLine(to: CGPoint(x: side * 0.625, y: side * 0.875))
            path.addLine(to: CGPoint(x: side * 0.125, y: side * 0.875))
            path.closeSubpath()
        }
    }

    private func upperCorridorPath(side: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: side * 0.375, y: side * 0.15625))
            path.addLine(to: CGPoint(x: side * 0.609375, y: side * 0.2734375))
            path.addLine(to: CGPoint(x: side * 0.609375, y: side * 0.3359375))
            path.addLine(to: CGPoint(x: side * 0.875, y: side * 0.46875))
            path.addLine(to: CGPoint(x: side * 0.875, y: side * 0.578125))
            path.addLine(to: CGPoint(x: side * 0.515625, y: side * 0.3984375))
            path.addLine(to: CGPoint(x: side * 0.515625, y: side * 0.3359375))
            path.addLine(to: CGPoint(x: side * 0.375, y: side * 0.265625))
            path.closeSubpath()
        }
    }

    private func lowerCorridorPath(side: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: side * 0.125, y: side * 0.4375))
            path.addLine(to: CGPoint(x: side * 0.40625, y: side * 0.578125))
            path.addLine(to: CGPoint(x: side * 0.40625, y: side * 0.640625))
            path.addLine(to: CGPoint(x: side * 0.625, y: side * 0.734375))
            path.addLine(to: CGPoint(x: side * 0.625, y: side * 0.84375))
            path.addLine(to: CGPoint(x: side * 0.34375, y: side * 0.703125))
            path.addLine(to: CGPoint(x: side * 0.34375, y: side * 0.640625))
            path.addLine(to: CGPoint(x: side * 0.125, y: side * 0.546875))
            path.closeSubpath()
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
            .fill(NoctwebTheme.deepWine)

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
            .fill(NoctwebTheme.mutedCoral)
        }
    }

    private var backgroundColors: [Color] {
        switch product {
        case .browser:
            [NoctwebTheme.plumBlack, Color(red: 18.0 / 255.0, green: 11.0 / 255.0, blue: 15.0 / 255.0)]
        case .lab:
            [NoctwebTheme.primaryText, NoctwebTheme.secondaryText]
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
