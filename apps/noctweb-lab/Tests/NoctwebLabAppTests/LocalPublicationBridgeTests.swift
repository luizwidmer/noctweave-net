import Foundation
import XCTest

@testable import NoctwebLab

final class LocalPublicationBridgeTests: XCTestCase {
    func testResponseFramesTheCompletePublicationBody() throws {
        let body = Data((0..<4_096).map { UInt8($0 % 251) })
        let response = LocalPublicationBridge.responseData(
            status: 200,
            body: body
        )
        let separator = Data("\r\n\r\n".utf8)
        let separatorRange = try XCTUnwrap(response.range(of: separator))
        let header = try XCTUnwrap(
            String(
                data: response[..<separatorRange.lowerBound],
                encoding: .utf8
            )
        )

        XCTAssertTrue(header.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(
            header.contains(
                "Content-Type: application/vnd.noctweave.noctweb-capsule"
            )
        )
        XCTAssertTrue(header.contains("Content-Length: \(body.count)"))
        XCTAssertEqual(response[separatorRange.upperBound...], body)
    }

    func testRequestParserAcceptsOnlyBoundedExactPublicationGets() {
        XCTAssertEqual(
            LocalPublicationBridge.requestedAddress(
                from:
                    "GET /v1/publication?address=noct%3A%2F%2Fsite.lisbon%2F HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            ),
            "noct://site.lisbon/"
        )
        XCTAssertNil(
            LocalPublicationBridge.requestedAddress(
                from:
                    "POST /v1/publication?address=noct%3A%2F%2Fsite.lisbon%2F HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            )
        )
        XCTAssertNil(
            LocalPublicationBridge.requestedAddress(
                from:
                    "GET /v1/publication?address=noct%3A%2F%2Fsite.lisbon%2F%0D%0AInjected HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
            )
        )
    }
}
