//
//  RenderPipeline.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200728.
//

import Foundation

import Metal

/**
 * Main interface to the Metal-based image processing pipeline. Each instance of this class is bound to a particular Metal device,
 * and can create pipeline state tied to that device and a particular image. In turn, each pipeline state can be adjusted with
 * different pipeline steps and settings before rendering, and re-used multiple times.
 */
public class RenderPipeline {
    /// Render device to use for the pipeline
    private(set) public var device: MTLDevice! = nil
    /// Command queue used for pipeline tasks (such as decoding images)
    private var commandQueue: MTLCommandQueue! = nil
    
    // MARK: - Initialization
    /**
     * Creates a new render pipeline for the given device.
     */
    public init(device: MTLDevice) {
        self.device = device
        
        self.commandQueue = device.makeCommandQueue()!
        self.commandQueue.label = "RenderPipeline"
    }
    
    // MARK: - State creation
    /**
     * All pipeline states ever created, but with weak references so they can be deallocated as needed.
     */
    private var states = NSHashTable<RenderPipelineState>.weakObjects()
    
    /**
     * Creates a pipeline state object for the image at the given url.
     *
     * - Note: `Progress` reporting is supported. All processing takes place synchronously.
     */
    public func createState(image: RenderPipelineImage) throws -> Any? {
        // decode the image
        guard let buffer = self.commandQueue.makeCommandBuffer() else {
            throw Errors.makeCommandBufferFailed
        }
        
        try image.decode(device: self.device, commandBuffer: buffer)
        
        buffer.commit()
        buffer.waitUntilCompleted()
        
        // try to create the pipeline state
        let state = try RenderPipelineState(device: self.device, image: image)
        self.states.add(state)
        
        // TODO: more stuff
        return state
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Failed to create a command buffer to decode an image on
        case makeCommandBufferFailed
    }
}
