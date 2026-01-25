import XCTest
@testable import CarrierWave

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

    func testParseStatusResponse() throws {
        let response = "RESULT=OK&CALLSIGN=W1ABC&COUNT=1234&CONFIRMED=567"

        let result = QRZClient.parseResponse(response)

        XCTAssertEqual(result["RESULT"], "OK")
        XCTAssertEqual(result["CALLSIGN"], "W1ABC")
        XCTAssertEqual(result["COUNT"], "1234")
    }
}
