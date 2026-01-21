//
//  ADIFParserTests.swift
//  FullDuplexTests
//
//  Created by Jay Vana on 1/20/26.
//

import XCTest
@testable import FullDuplex

final class ADIFParserTests: XCTestCase {

    func testParseSimpleRecord() throws {
        let adif = "<call:4>W1AW <band:3>20m <mode:2>CW <qso_date:8>20240115 <time_on:4>1430 <eor>"

        let parser = ADIFParser()
        let records = try parser.parse(adif)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].callsign, "W1AW")
        XCTAssertEqual(records[0].band, "20m")
        XCTAssertEqual(records[0].mode, "CW")
    }
}
