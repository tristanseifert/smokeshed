//
//  PipelineCreate.swift
//  WaterpipeTests
//
//  Created by Tristan Seifert on 20200729.
//

import XCTest
import Metal

import Waterpipe

import Bowl
import CocoaLumberjackSwift

class PipelineCreate: XCTestCase {
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

    /*
        // set up for capturing all Metal commands
        let captureManager = MTLCaptureManager.shared()
        let captureDescriptor = MTLCaptureDescriptor()
        captureDescriptor.captureObject = self.device
    
        // capture that shit
        try captureManager.startCapture(with: captureDescriptor)
    */
    }

    /**
     * Ends the GPU capture.
     */
    override func tearDown() {
        /*
        // stop GPU capture
        let captureManager = MTLCaptureManager.shared()
        captureManager.stopCapture()
        */
    }
    
    /**
     * Tries to create a rendering pipeline with the "birb.cr2" image.
     */
    func testLoadBirbCr2() throws {
        // create pipeline
        let device = MTLCreateSystemDefaultDevice()
        XCTAssertNotNil(device)
        
        let pipeline = RenderPipeline(device: device!)
        DDLogInfo("Pipeline: \(pipeline)")
        
        // load image
        let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                  withExtension: "cr2")!
        let image = try RenderPipelineImage(url: url)
        DDLogInfo("Render image: \(image)")
        
        // create pipeline state
        let state = try pipeline.createState(image: image)
        DDLogInfo("Pipeline state: \(String(describing: state))")
    }
}
