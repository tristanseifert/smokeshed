//
//  PaperTests.swift
//  PaperTests
//
//  Created by Tristan Seifert on 20200614.
//

import XCTest

import Bowl

class PaperTests: XCTestCase {

    override func setUpWithError() throws {
        // Set up logging
        Bowl.Logger.setup()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }

}
