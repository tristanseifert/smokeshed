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
     * Reads in the `birb.cr2` RAW file once and ensures the read data matches what we expect.
     *
     * This image was created on a Canon EOS 6D Mk II.
     */
    func testCr2Birb() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                  withExtension: "cr2")!

        let reader = try CR2Reader(fromUrl: url, decodeRawData: true, decodeThumbs: true)
        let image = try reader.decode()
        
        DDLogInfo("Metadata: \(String(describing: image.meta))")
        DDLogInfo("CR2 image: \(image)")
//        self.saveResults(image)
    }
    
    /**
     * Reads in the `froge.cr2` RAW file once and ensures the read data matches what we expect.
     *
     * This image was created on a Canon T3i.
     */
    func testCr2Froge() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "froge",
                                                  withExtension: "cr2")!

        let reader = try CR2Reader(fromUrl: url, decodeRawData: true, decodeThumbs: true)
        let image = try reader.decode()
        
        DDLogInfo("Metadata: \(String(describing: image.meta))")
        DDLogInfo("CR2 image: \(image)")
        self.saveResults(image)
    }

    /**
     * Reads in the `birb.cr2` RAW file multiple times, gathering timing information.
     */
    func testCr2BirbTiming() throws {
        // decode it
        measure {
            var reader: CR2Reader!

            // create a CR2 decoder
            let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                      withExtension: "cr2")!
            do {
                reader = try CR2Reader(fromUrl: url, decodeRawData: true, decodeThumbs: true)
                let image = try reader.decode()
                self.stopMeasuring()
                DDLogInfo("CR2 image: \(image)")
            } catch {
                XCTAssertNotNil(error, "Failed to decode CR2")
            }
        }
    }
    
    /**
     * Tests reading `birb.cr2` using the LibRaw reader.
     */
    func testCr2BirbLibRaw() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                  withExtension: "cr2")!
        
        let reader = try LibRawReader(fromUrl: url, decodeRawData: true, decodeThumbs: true)
        try reader.decode()
        
        DDLogInfo("Reader: \(reader)")
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

        // save the raw planes as well as unsliced pixel data
        var planeIdx = 0

        for planeData in image.rawPlanes {
            let attach = XCTAttachment(data: planeData)
            attach.name = String(format: "raw_plane\(planeIdx)")
            attach.lifetime = .keepAlways
            self.add(attach)

            planeIdx += 1
        }

        let attach = XCTAttachment(data: image.rawValues)
        attach.name = String(format: "raw_values")
        attach.lifetime = .keepAlways
        self.add(attach)
    }
}
