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
    public func createState(image: RenderPipelineImage) throws -> RenderPipelineState {
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

    /**
     * Renders the given pipeline state synchronously. The output is rendered
     * into the given tiled image.
     */
    public func render(_ state: RenderPipelineState, _ image: TiledImage) throws {
        // validate device
        guard self.device.registryID == state.device.registryID else {
            throw Errors.invalidDevice
        }

        // for now, just copy the texture to output
        guard let commandBuffer = self.commandQueue.makeCommandBuffer() else {
            throw Errors.makeCommandBufferFailed
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw Errors.makeCommandBufferFailed
        }
        
        encoder.copy(from: state.image.tiledImage!.texture!, to: image.texture)
        
        encoder.endEncoding()
        
        // execute and wait
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Render state is not valid on this renderer's device
        case invalidDevice
        /// Failed to create a command buffer to decode an image on
        case makeCommandBufferFailed
    }
}
