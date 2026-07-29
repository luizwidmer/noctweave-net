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
    public static let accent = Color(
        red: 116.0 / 255.0,
        green: 99.0 / 255.0,
        blue: 1.0
    )
    public static let aqua = Color(
        red: 61.0 / 255.0,
        green: 210.0 / 255.0,
        blue: 190.0 / 255.0
    )
    public static let coral = accent
    public static let coralStrong = accent
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
    public static let wine = accent

    public static let canvas = Color(nsColor: .windowBackgroundColor)
    public static let surface = Color(nsColor: .controlBackgroundColor)
        .opacity(0.86)
    public static let card = Color(nsColor: .textBackgroundColor)
        .opacity(0.82)
    public static let input = Color(nsColor: .textBackgroundColor)
        .opacity(0.72)
    public static let navigation = Color(nsColor: .underPageBackgroundColor)
        .opacity(0.9)
    public static let status = accent.opacity(0.14)
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
