//
//  HistogramTests.swift
//  WaterpipeTests
//
//  Created by Tristan Seifert on 20200809.
//

import XCTest
import Metal
import Waterpipe
import Bowl
import CocoaLumberjackSwift

class HistogramTests: XCTestCase {
    /// Metal device
    private var device: MTLDevice! = nil
    
    /**
     * Set up logging before tests run, and a GPU capturer.
     */
    override func setUpWithError() throws {
        Bowl.Logger.setup()
        
        // get the system default device
        self.device = MTLCreateSystemDefaultDevice()
        XCTAssertNotNil(self.device)
    }
    
    /**
     * Tries to create a rendering pipeline with the "birb.cr2" image and calculate the histogram over it.
     */
    func testBirbCr2() throws {
        // create pipeline
        let pipeline = RenderPipeline(device: self.device)
        DDLogInfo("Pipeline: \(pipeline)")
        
        // histogram calculator
        let histo = try HistogramCalculator(device: self.device)
        DDLogInfo("Histogram: \(histo)")
        
        // load image
        let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                  withExtension: "cr2")!
        let image = try RenderPipelineImage(url: url)
        DDLogInfo("Render image: \(image)")
        
        // create pipeline state
        let state = try pipeline.createState(image: image)
        DDLogInfo("Pipeline state: \(String(describing: state))")
        
        // output image
        let outImage = TiledImage(device: self.device, forImageSized: image.size, tileSize: 512,
                                  .rgba32Float)
        XCTAssertNotNil(outImage)
        
        // render it
        try pipeline.render(state, outImage!)
    
        // compute histogram
        let res = try histo.calculateHistogram(outImage!, buckets: 256)
        DDLogVerbose("Result: \(res)")
    }
}
