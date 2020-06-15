//
//  TIFFReaderTests.swift
//  PaperTests
//
//  Created by Tristan Seifert on 20200614.
//

import XCTest

import Combine

import Bowl
import Paper
import CocoaLumberjackSwift

class TIFFReaderTests: XCTestCase {
    /**
     * Set up logging before tests run.
     */
    override func setUp() {
        Bowl.Logger.setup()
    }

    // MARK: - Basic reading
    /**
     * Reads the "f14.tif" file. This file has a single IFD containing 18 tags.
     *
     * This test asserts that a single IFD, with 18 tags, is loaded. It does not verify the contents of those tags
     * yet.
     */
    func testReadFile() throws {
        let expect = XCTestExpectation(description: "TIFF decoding")

        // create a TIFF reader
        let url = Bundle(for: type(of: self)).url(forResource: "f14",
                                                  withExtension: "tif")!
        let reader = try TIFFReader(fromUrl: url)

        // add a meeper
        let cancelable = reader.publisher.sink(receiveCompletion: { completion in
            switch completion {
                case .finished:
                    expect.fulfill()

                case .failure(let error):
                    XCTFail("Decoding failed: \(error)")
            }

            expect.fulfill()
        }, receiveValue: { ifd in
            XCTAssertEqual(ifd.tags.count, 18, "Unexpected number of tags for \(ifd)")
        })

        // decode it in the background
        DispatchQueue.global().async {
            reader.decode()
        }

        // wait for decoding to complete
        wait(for: [expect], timeout: 2)
    }

}
