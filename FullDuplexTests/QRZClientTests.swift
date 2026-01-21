import XCTest
@testable import FullDuplex

final class QRZClientTests: XCTestCase {

    func testParseLoginResponse() throws {
        let response = "RESULT=OK&KEY=abc123&COUNT=1"

        let result = QRZClient.parseResponse(response)

        XCTAssertEqual(result["RESULT"], "OK")
        XCTAssertEqual(result["KEY"], "abc123")
    }

    func testParseErrorResponse() throws {
        let response = "RESULT=FAIL&REASON=Invalid credentials"

        let result = QRZClient.parseResponse(response)

        XCTAssertEqual(result["RESULT"], "FAIL")
        XCTAssertEqual(result["REASON"], "Invalid credentials")
    }
}
