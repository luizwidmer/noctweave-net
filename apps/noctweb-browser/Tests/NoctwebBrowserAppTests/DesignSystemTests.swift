import Foundation
import XCTest

@testable import NoctwebBrowserCore

final class DesignSystemTests: XCTestCase {
    func testDeterministicBrowserFixtureCSSIsAdaptive() async throws {
        let environment = try DeterministicNoctwebResolver.developmentEnvironment()
        let site = try await environment.resolver.resolve(
            environment.welcomeURL,
            profile: environment.profile,
            visitorDirective: .open
        )
        let css = try XCTUnwrap(
            site.bundle.files.first(where: { $0.path == "styles.css" })
        )
        let source = try XCTUnwrap(String(data: css.bytes, encoding: .utf8))

        XCTAssertTrue(source.contains("color-scheme: light dark"))
        XCTAssertTrue(source.contains("@media (prefers-color-scheme: dark)"))
        XCTAssertFalse(source.contains("color-scheme: dark;"))
    }
}
