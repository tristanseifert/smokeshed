//
//  ThumbReaderTests.swift
//  PaperTests
//
//  Created by Tristan Seifert on 20200625.
//

import XCTest
import CoreGraphics

import Bowl
import Paper
import CocoaLumberjackSwift

class ThumbReaderTests: XCTestCase {
    /**
     * Set up logging before tests run.
     */
    override func setUp() {
        Bowl.Logger.setup()
    }
    
    /**
     * Gets the standard sized thumbs out of the `forest.tif` test image.
     */
    func testForestTif() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "forest",
                                                  withExtension: "tif")!
        
        // create the reader
        guard let reader = ThumbReader(url) else {
            throw TestErrors.readerInitFailed(url)
        }
        
        // create the attachments
        try self.generateAttachments(reader)
    }
    
    /**
     * Gets the standard sized thumbs out of the `yenrail.jpg` test image.
     */
    func testYenrailJpeg() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "yenrail",
                                                  withExtension: "jpg")!
        
        // create the reader
        guard let reader = ThumbReader(url) else {
            throw TestErrors.readerInitFailed(url)
        }
        
        // create the attachments
        try self.generateAttachments(reader)
    }
    
    /**
     * Gets the standard sized thumbs out of the `birb.cr2` test image.
     */
    func testBirbCr2() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                  withExtension: "cr2")!
        
        // create the reader
        guard let reader = ThumbReader(url) else {
            throw TestErrors.readerInitFailed(url)
        }
        
        // create the attachments
        try self.generateAttachments(reader)
    }
    
    // MARK: - Helpers
    /**
     * Gets a standard sized set of images from the thumb reader and saves them as attachments.
     */
    @discardableResult private func generateAttachments(_ reader: ThumbReader) throws -> [CGImage] {
        var images: [CGImage] = []
        
        // generate image for every size
        for size in Self.sizes {
            // ensure one was created
            guard let image = reader.getThumb(size) else {
                throw TestErrors.getThumbFailed(size)
            }
            
            // add it to the array
            images.append(image)
            
            // save attachment
            let attach = XCTAttachment(image: NSImage(cgImage: image,
                                                      size: .zero))
            attach.lifetime = .keepAlways
            attach.name = String(format: "thumb_%.0f", size)
            self.add(attach)
        }
        
        return images
    }
    
    /**
     * Image sizes, in pixels, to generate thumbs for
     */
    private static let sizes: [CGFloat] = [
        50,
        100,
        256,
        512,
        1024,
        1500
    ]
    
    /**
     * Test errors
     */
    enum TestErrors: Error {
        /// Couldn't create a reader for the given url
        case readerInitFailed(_ url: URL)
        /// Failed to generate thumbnail of this size
        case getThumbFailed(_ size: CGFloat)
    }
}
