import Foundation
import XCTest

@testable import NoctwebLab

final class DesignSystemTests: XCTestCase {
    func testGeneratedAndLegacySiteCSSFollowsSystemAppearance() throws {
        var site = try XCTUnwrap(Workspace.starter().sites.first)
        WebsiteProjectBuilder.ensureProject(&site)

        let css = try XCTUnwrap(
            site.resolvedFiles.first(where: { $0.path == "styles.css" })
        )
        let source = try XCTUnwrap(String(data: css.bytes, encoding: .utf8))

        XCTAssertTrue(source.contains("color-scheme: light dark"))
        XCTAssertTrue(source.contains("@media (prefers-color-scheme: dark)"))
        XCTAssertTrue(source.contains("--violet: #674dd9"))
        XCTAssertTrue(source.contains("--blue: #397ccf"))
        XCTAssertTrue(source.contains("--teal: #168f83"))

        let legacySource = WebsiteProjectBuilder.legacyCSS(
            accentHex: "#4F8F77"
        )
        XCTAssertTrue(legacySource.contains("color-scheme: light dark"))
        XCTAssertTrue(legacySource.contains("@media (prefers-color-scheme: dark)"))
        XCTAssertTrue(legacySource.contains("var(--canvas)"))
    }
}
