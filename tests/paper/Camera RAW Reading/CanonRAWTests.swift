//
//  CanonRAWTests.swift
//  PaperTests
//
//  Created by Tristan Seifert on 20200614.
//

import XCTest

import Combine

import Bowl
import Paper
import CocoaLumberjackSwift

class CanonRAWTests: XCTestCase {
    private var cancelable: AnyCancellable? = nil

    /**
     * Set up logging before tests run.
     */
    override func setUp() {
        Bowl.Logger.setup()
    }

    /**
     * After each run, ensure the cancelable is cleared out. Setting it to nil is enough to cancel it if not
     * already done since the destructor does this.
     */
    override func tearDownWithError() throws {
        self.cancelable = nil
    }

    // MARK: - Reading tests
    /**
     * Reads in the `birb.cr2` RAW file.
     */
    func testCr2Birb() throws {
        let expect = XCTestExpectation(description: "birb.cr2 decoding")

        // create a CR2 decoder
        let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                  withExtension: "cr2")!
        let reader = try CR2Reader(fromUrl: url)

        self.cancelable = reader.publisher.sink(receiveCompletion: { completion in
            switch completion {
                case .finished:
                    expect.fulfill()

                case .failure(let error):
                    XCTFail("Decoding failed: \(error)")
            }

            expect.fulfill()
        }, receiveValue: { image in
            DDLogInfo("CR2 image: \(image)")
            self.saveResults(image)
        })

        // decode it in the background and wait
        DispatchQueue.global().async {
            self.measure {
                reader.decode()
            }
        }

        wait(for: [expect], timeout: 5)
    }

    // MARK: - Test Artifacts
    /**
     * Saves information from a decoded RAW image as attachments.
     */
    private func saveResults(_ image: CR2Image) {
        // save each thumbnail
        for thumb in image.thumbs {
            let nsimg = NSImage(cgImage: thumb, size: .zero)

            let attach = XCTAttachment(image: nsimg)
            attach.lifetime = .keepAlways
            self.add(attach)
        }
    }
}
