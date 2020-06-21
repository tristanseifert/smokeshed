//
//  DebayerTests.swift
//  PaperTests
//
//  Created by Tristan Seifert on 20200621.
//

import XCTest

import Paper
import Bowl

import CocoaLumberjackSwift

class DebayerTests: XCTestCase {
    /**
     * Set up logging before tests run.
     */
    override func setUp() {
        Bowl.Logger.setup()
    }

    // MARK: - Reading tests
    /**
     * Reads in the `birb.cr2` RAW file once, then attempts to debayer it.
     */
    func testCr2BirbDebayer() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                  withExtension: "cr2")!

        let reader = try CR2Reader(fromUrl: url, decodeRawData: true, decodeThumbs: true)
        let image = try reader.decode()
        
        // get white balance values
        let wb = image.rawWbMultiplier.map(NSNumber.init)

        DDLogVerbose("Black levels: \(image.rawBlackLevel)")
        DDLogVerbose("WB multipliers: \(wb)")
        
        // attempt debayering
        let bytes = image.rawValuesSize.width * image.rawValuesSize.height * 4 * 2
        let outData = NSMutableData(length: Int(bytes))!
        
        PAPDebayerer.debayer(image.rawValues!, withOutput: outData,
                             imageSize: image.rawValuesSize, andAlgorithm: 1,
                             vShift: UInt(image.rawValuesVshift), wbShift: wb,
                             blackLevel: image.rawBlackLevel as [NSNumber])
        
        // save that shit
        let attach = XCTAttachment(data: image.rawValues)
        attach.name = String(format: "raw")
        attach.lifetime = .keepAlways
        self.add(attach)

        let attach2 = XCTAttachment(data: outData as Data)
        attach2.name = String(format: "debayered")
        attach2.lifetime = .keepAlways
        self.add(attach2)
    }

}
