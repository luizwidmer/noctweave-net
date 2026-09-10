import StoreKit
import StoreKitTest
import XCTest
import NoctwebUI

@MainActor
final class AppSupportStoreTests: XCTestCase {
    private let ids = ["net.noctweave.noctwebbrowser.tip.small", "net.noctweave.noctwebbrowser.tip.medium", "net.noctweave.noctwebbrowser.tip.large"]

    private func session() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "SupportTips", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    func testReviewURLUsesExactAppAndWriteReviewAction() {
        XCTAssertNil(AppSupportStore.reviewURL(appID: 0))
        XCTAssertEqual(AppSupportStore.reviewURL(appID: 6809914725)?.absoluteString,
                       "https://apps.apple.com/app/id6809914725?action=write-review")
    }

    func testTipsLoadLocalizedPricesAndCanBePurchasedAgain() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = AppSupportStore(productIDs: ids)
        await store.loadProducts()
        XCTAssertEqual(store.products.map(\.id), ids)
        XCTAssertEqual(store.products.map(\.price), [Decimal(string: "1.99")!, Decimal(string: "4.99")!, Decimal(string: "9.99")!])
        let small = try XCTUnwrap(store.products.first)
        XCTAssertFalse(small.displayPrice.isEmpty)
        await store.purchase(small)
        XCTAssertEqual(store.message, "Thank you for supporting continued development.")
        XCTAssertNil(store.purchasingProductID)
        await store.purchase(small)
        XCTAssertEqual(session.allTransactions().count, 2)
        var unfinished = 0
        for await result in StoreKit.Transaction.unfinished {
            if case .verified(let transaction) = result, ids.contains(transaction.productID) { unfinished += 1 }
        }
        XCTAssertEqual(unfinished, 0)
    }

    func testUnconfiguredProductCannotBePurchased() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let products = try await Product.products(for: [ids[0]])
        let product = try XCTUnwrap(products.first)
        let store = AppSupportStore(productIDs: [ids[1]], observeTransactions: false)
        await store.purchase(product)
        XCTAssertTrue(session.allTransactions().isEmpty)
    }
    func testPendingTipIsFinishedWhenApprovalArrives() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        session.askToBuyEnabled = true
        let store = AppSupportStore(productIDs: ids)
        await store.loadProducts()
        let product = try XCTUnwrap(store.products.first)
        await store.purchase(product)
        XCTAssertEqual(store.message, "Your tip is awaiting approval. You can keep using the app.")
        XCTAssertNil(store.purchasingProductID)
        let pending = try XCTUnwrap(session.allTransactions().first)
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        let deadline = Date().addingTimeInterval(5)
        while store.message != "Thank you for supporting continued development.", Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(store.message, "Thank you for supporting continued development.")
        var unfinished = 0
        for await result in StoreKit.Transaction.unfinished {
            if case .verified(let transaction) = result, ids.contains(transaction.productID) { unfinished += 1 }
        }
        XCTAssertEqual(unfinished, 0)
    }

}
