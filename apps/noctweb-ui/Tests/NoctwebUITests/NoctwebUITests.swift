import XCTest
@testable import NoctwebUI

@MainActor
final class NoctwebUITests: XCTestCase {
    func testAppearanceIsSessionOnlyAndDetectsLegacyPlaintext() {
        let suite = "NoctwebUITests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("dark", forKey: "net.noctweave.noctweb.appearance")

        let store = NoctwebAppearanceStore(defaults: defaults)
        XCTAssertEqual(store.selection, .system)
        XCTAssertTrue(store.legacyStorageDetected)
        XCTAssertEqual(defaults.string(forKey: "net.noctweave.noctweb.appearance"), "dark")

        store.selection = .dark
        XCTAssertEqual(defaults.string(forKey: "net.noctweave.noctweb.appearance"), "dark")
        XCTAssertEqual(
            NoctwebAppearanceStore(defaults: defaults).selection,
            .system
        )
        store.reset()
        XCTAssertFalse(store.legacyStorageDetected)
        XCTAssertNil(defaults.object(forKey: "net.noctweave.noctweb.appearance"))
    }

    func testThemeDefinesCanonicalOffsetVeilPalette() {
        XCTAssertNotNil(NoctwebTheme.warmIvory)
        XCTAssertNotNil(NoctwebTheme.paleSand)
        XCTAssertNotNil(NoctwebTheme.mutedCoral)
        XCTAssertNotNil(NoctwebTheme.deepWine)
        XCTAssertNotNil(NoctwebTheme.plumBlack)
    }
}
