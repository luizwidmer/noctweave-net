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
    public static let ivory = Color(
        red: 250.0 / 255.0,
        green: 243.0 / 255.0,
        blue: 234.0 / 255.0
    )
    public static let sand = Color(
        red: 235.0 / 255.0,
        green: 199.0 / 255.0,
        blue: 175.0 / 255.0
    )
    public static let coral = Color(
        red: 201.0 / 255.0,
        green: 106.0 / 255.0,
        blue: 97.0 / 255.0
    )
    public static let wine = Color(
        red: 146.0 / 255.0,
        green: 45.0 / 255.0,
        blue: 53.0 / 255.0
    )
    public static let ink = Color(
        red: 27.0 / 255.0,
        green: 18.0 / 255.0,
        blue: 23.0 / 255.0
    )
    public static let plum = Color(
        red: 45.0 / 255.0,
        green: 28.0 / 255.0,
        blue: 35.0 / 255.0
    )
    public static let accent = coral
    public static let coralStrong = wine

    public static let canvas = adaptive(
        light: NSColor(
            srgbRed: 250.0 / 255.0,
            green: 243.0 / 255.0,
            blue: 234.0 / 255.0,
            alpha: 1
        ),
        dark: NSColor(
            srgbRed: 27.0 / 255.0,
            green: 18.0 / 255.0,
            blue: 23.0 / 255.0,
            alpha: 1
        )
    )
    public static let surface = adaptive(
        light: NSColor(
            srgbRed: 246.0 / 255.0,
            green: 234.0 / 255.0,
            blue: 223.0 / 255.0,
            alpha: 0.92
        ),
        dark: NSColor(
            srgbRed: 45.0 / 255.0,
            green: 28.0 / 255.0,
            blue: 35.0 / 255.0,
            alpha: 0.92
        )
    )
    public static let card = adaptive(
        light: NSColor(
            srgbRed: 1,
            green: 249.0 / 255.0,
            blue: 242.0 / 255.0,
            alpha: 0.9
        ),
        dark: NSColor(
            srgbRed: 42.0 / 255.0,
            green: 27.0 / 255.0,
            blue: 33.0 / 255.0,
            alpha: 0.9
        )
    )
    public static let input = adaptive(
        light: NSColor(
            srgbRed: 1,
            green: 252.0 / 255.0,
            blue: 248.0 / 255.0,
            alpha: 0.9
        ),
        dark: NSColor(
            srgbRed: 61.0 / 255.0,
            green: 35.0 / 255.0,
            blue: 38.0 / 255.0,
            alpha: 0.86
        )
    )
    public static let navigation = adaptive(
        light: NSColor(
            srgbRed: 240.0 / 255.0,
            green: 224.0 / 255.0,
            blue: 212.0 / 255.0,
            alpha: 0.94
        ),
        dark: NSColor(
            srgbRed: 36.0 / 255.0,
            green: 22.0 / 255.0,
            blue: 29.0 / 255.0,
            alpha: 0.94
        )
    )
    public static let status = accent.opacity(0.14)

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
                .fill(upperPlaneColor)

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
                .fill(NoctwebTheme.coral)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var backgroundColors: [Color] {
        switch product {
        case .browser:
            [NoctwebTheme.plum, NoctwebTheme.ink]
        case .lab:
            [NoctwebTheme.ivory, NoctwebTheme.sand]
        }
    }

    private var upperPlaneColor: Color {
        switch product {
        case .browser:
            NoctwebTheme.ivory
        case .lab:
            NoctwebTheme.wine
        }
    }

    private var borderColor: Color {
        switch product {
        case .browser:
            NoctwebTheme.sand.opacity(0.16)
        case .lab:
            NoctwebTheme.wine.opacity(0.16)
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
