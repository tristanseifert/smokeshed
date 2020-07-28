//
//  RenderPipelineState.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200728.
//

import Foundation

import Metal

/**
 * A render pipeline state object contains a fully decoded image (decoded from camera raw formats or other sources) as well as
 * its metadata. It serves as the endpoint for processing a single image.
 *
 * Pipeline states aren't tied to a particular thread, but they may only be used by a single thread at a time.
 */
public class RenderPipelineState {
    /// Image rendered by this pipeline state object
    private(set) public var image: RenderPipelineImage! = nil
    
    /// Device to which the state object, and all of its resources, belong
    private(set) public var device: MTLDevice! = nil
    
    // MARK: - Initialization
    /**
     * Creates a new render pipeline for the given device.
     */
    internal init(device: MTLDevice, image: RenderPipelineImage) throws {
        guard image.isDecoded else {
            throw Errors.imageNotDecoded
        }
        
        self.device = device
        self.image = image
    }
    
    // MARK: - Errors
    public enum Errors: Error {
        /// Image is not decoded
        case imageNotDecoded
    }
}
