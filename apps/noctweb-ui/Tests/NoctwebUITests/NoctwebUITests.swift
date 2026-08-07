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

    func testThemeDefinesCanonicalOffsetVeilPalette() {
        XCTAssertNotNil(NoctwebTheme.warmIvory)
        XCTAssertNotNil(NoctwebTheme.paleSand)
        XCTAssertNotNil(NoctwebTheme.mutedCoral)
        XCTAssertNotNil(NoctwebTheme.deepWine)
        XCTAssertNotNil(NoctwebTheme.plumBlack)
    }
}
