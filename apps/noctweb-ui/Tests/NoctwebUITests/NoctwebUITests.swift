import XCTest
@testable import NoctwebUI

@MainActor
final class NoctwebUITests: XCTestCase {
    func testAppearancePersistsAndDefaultsToSystem() {
        let suite = "NoctwebUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = NoctwebAppearanceStore(defaults: defaults)
        XCTAssertEqual(store.selection, .system)

        store.selection = .dark
        XCTAssertEqual(
            defaults.string(forKey: "net.noctweave.noctweb.appearance"),
            "dark"
        )
        XCTAssertEqual(
            NoctwebAppearanceStore(defaults: defaults).selection,
            .dark
        )
    }

    func testThemeDefinesCanonicalVioletBlueTealPalette() {
        XCTAssertNotNil(NoctwebTheme.quantumViolet)
        XCTAssertNotNil(NoctwebTheme.transitBlue)
        XCTAssertNotNil(NoctwebTheme.signalTeal)
    }
}
