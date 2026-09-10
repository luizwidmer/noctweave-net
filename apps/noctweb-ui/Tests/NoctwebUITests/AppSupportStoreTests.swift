import XCTest
@testable import NoctwebUI

@MainActor
final class AppSupportStoreTests: XCTestCase {
    func testReviewURLUsesExactAppAndWriteReviewAction() {
        XCTAssertNil(AppSupportStore.reviewURL(appID: 0))
        XCTAssertEqual(AppSupportStore.reviewURL(appID: 6809914725)?.absoluteString,
                       "https://apps.apple.com/app/id6809914725?action=write-review")
    }
}
