//
//  BitstreamTests.swift
//  PaperTests
//
//  Created by Tristan Seifert on 20200616.
//

import XCTest

class BitstreamTests: XCTestCase {
    /**
     * Test data
     */
    static let test = Data([
        0xF0, 0x80, 0x55
    ])

    /**
     * Tests reading full 8 bit quantities.
     */
    func testFullRead() {
        let stream = Bitstream(withData: Self.test)

        // read a full 8 bits
        XCTAssertEqual(stream.readString(8), UInt64(0xF0), "readString(8) failed")
        XCTAssertEqual(stream.readString(8), UInt64(0x80), "readString(8) failed")
        XCTAssertEqual(stream.readString(8), UInt64(0x55), "readString(8) failed")
    }

    /**
     * Reads quantities between 2 and 8 bits.
     */
    func testMultibitRead() {
        let stream = Bitstream(withData: Self.test)

        // read a 2 bit string
        XCTAssertEqual(stream.readString(2), UInt64(0x03), "readString(2) failed")
        // read a 3 bit string
        XCTAssertEqual(stream.readString(3), UInt64(0x06), "readString(3) failed")
        // read a 4 bit string
        XCTAssertEqual(stream.readString(4), UInt64(0x01), "readString(4) failed")
        // read a 7 bit string
        XCTAssertEqual(stream.readString(7), UInt64(0x00), "readString(7) failed")
        // read a 5 bit string
        XCTAssertEqual(stream.readString(5), UInt64(0x0A), "readString(4) failed")
    }

    /**
     * Reads the 0x55 value; we expect an equal number of 1's and 0's.
     */
    func testSingleBitsRead() {
        let stream = Bitstream(withData: Self.test)

        var zeroes = 0
        var ones = 0

        // discard the first two bytes
        _ = stream.readString(16)

        for _ in 1...8 {
            let read = stream.readNext()
            XCTAssertNotNil(read)
            XCTAssertLessThanOrEqual(read!, 1)

            if read! == 0 {
                zeroes += 1
            } else if read! == 1 {
                ones += 1
            }
        }

        // they should be equal
        XCTAssertEqual(zeroes, ones, "Mismatch in zeroes to ones")
    }
}
