//
//  RenderPipelineState.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200728.
//

import Foundation
import Metal
import MetalPerformanceShaders

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
    
    /// Processing elements set on the pipeline
    private var elements: [RenderPipelineElement] = []
    
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
    
    // MARK: - Accessors
    /**
     * Adds a new rendering element to the pipeline, in the given group.
     */
    internal func add(_ element: RenderPipelineElement, group: ElementGroup) {
        // TODO: care about group
        self.elements.append(element)
    }
    
    // MARK: - Rendering
    /**
     * Encodes onto the given command buffer all of the processing elements.
     *
     * - Returns: The output image, or `nil` if no image processing took place.
     */
    internal func render(buffer: MTLCommandBuffer) throws -> TiledImage {
        var input: TiledImage? = self.image.tiledImage
        var output: TiledImage? = self.image.tiledImage
        
        // encode each element        
        try self.elements.forEach { element in
            // allocate an output texture
            let tempOut = TiledImage(buffer: buffer, imageSize: input!.imageSize,
                                     tileSize: input!.tileSize, input!.pixelFormat, 1)
            output = tempOut
            
            // encode the element
            precondition(input != nil)
            precondition(output != nil)
            
            try element.encode(buffer, in: input!, out: output!)
            input!.didRead()
            
            // use the output of this element as the input of the next
            input = output
        }
        
        return output!
    }
    
    // MARK: - Errors
    public enum Errors: Error {
        /// Image is not decoded
        case imageNotDecoded
    }
    
    // MARK: - Types
    /// Group to which a processing element belongs
    internal enum ElementGroup {
        /// Elements inserted by the image reader implementation; these always run first.
        case readerImpl
    }
}

/**
 * Interface for processing elements
 */
public protocol RenderPipelineElement {
    typealias Tag = String
    
    /// Tag value for the element
    var tag: Tag? { get }
    /// Metal device on which the element runs
    var device: MTLDevice! { get }
    
    /**
     * Creates a pipeline element that belongs to the given Metal device and has the given tag.
     */
    init(_ device: MTLDevice, tag: Tag?) throws
    
    /**
     * Encodes the element into the given command buffer, with the specified input and output images.
     */
    func encode(_ buffer: MTLCommandBuffer, in: TiledImage, out: TiledImage) throws
}
