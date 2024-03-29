//
//  RenderPipelineImage.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200728.
//

import Foundation

import Metal

/**
 * Represents a single image to ingest into the render pipeline.
 */
public class RenderPipelineImage {
    private var image: ImageReaderImpl
    
    /// If the image is transient, we expect to use it once and then never again. This is the case for batch exports, for example.
    private(set) public var isTransient: Bool
    
    /// URL from which the image was read originally
    private(set) public var url: URL
    /// Size of the image
    public var size: CGSize {
        return self.image.size
    }
    
    /**
     * Cache for intermediate representations of the image that may be used later. This is used to cache the raw RGB data immediately
     * after decoding the image, before any transformations are applied.
     */
    private var cache: PipelineCache!

    // MARK: - Initialization
    /**
     * Attempts to create a new render pipeline image from the file at the given url.
     *
     * This will automatically determine how to get at the image data (by invoking the correct camera raw reader) and read some
     * preliminary metadata from it.
     *
     * - Note: `Progress` reporting is supported. All processing takes place synchronously.
     */
    public init(url: URL, transient: Bool = false) throws {
        // try to read image
        guard let image = try ImageReader.shared.read(url: url) else {
            throw Errors.readImageFailed(url)
        }
        
        self.isTransient = transient
        self.url = url
        self.image = image
        
        if transient {
            self.cache = PipelineCache([.passthrough])
        } else {
            self.cache = PipelineCache()
        }
    }
    
    // MARK: - Decoding
    /**
     * Device on which the image was most recently decoded. This is the device that contains the image tile texture and image
     * data buffer objects.
     */
    private(set) public var device: MTLDevice? = nil
    /// Has the image been decoded yet?
    private(set) internal var isDecoded: Bool = false
    
    /// Tiled image containing pixel data
    private(set) internal var tiledImage: TiledImage? = nil
    
    /// Buffer on the GPU containing the image data
    private var pixelBuffer: MTLBuffer? = nil
    
    /**
     * Decodes the image.
     *
     * If the image has previously been decoded, and the device on which it was decoded was the same as the device for which
     * the current decode is requested, the call is a no-op. Otherwise, the contents of the image will not be valid until the
     * commands encoded into the command buffer have been executed.
     *
     * - Note: `Progress` reporting is supported. This runs synchronously on the caller thread, and may take a not
     * insignificant amount of time.
     */
    internal func decode(device: MTLDevice, commandBuffer: MTLCommandBuffer) throws {
        // short circuit if decode is valid
        if self.isDecoded, let lastDevice = self.device,
           lastDevice.registryID == device.registryID {
            return
        }
        
        // set up for progress reporting
        let progress = Progress(totalUnitCount: 2)
        
        // decode the image to an RGBA data buffer and copy to GPU
        // TODO: support 16 bit formats
        // TODO: use .shared storage mode on iOS
        progress.becomeCurrent(withPendingUnitCount: 1)
        
        let decoded = try self.image.decode(.float32)
        try decoded.data.withUnsafeBytes {
            guard let buf = device.makeBuffer(bytes: $0.baseAddress!,
                                              length: decoded.data.count,
                                              options: .storageModeManaged) else {
                throw Errors.makeBufferFailed
            }
            self.pixelBuffer = buf
        }
        
        progress.resignCurrent()
        
        // allocate a tiled image and copy the buffer into it
        progress.becomeCurrent(withPendingUnitCount: 1)
        guard let tiled = TiledImage(device: device, forImageSized: self.image.size,
                                     tileSize: 512) else {
            throw Errors.makeTiledImageFailed
        }
        try TiledImage.copyBufferToImage(commandBuffer, self.pixelBuffer!, image.size,
                                         decoded.bytesPerRow, .rgba32Float, tiled)
        
        self.tiledImage = tiled        
        progress.resignCurrent()
        
        // ensure we won't decode on the same device again later
        self.device = device
        self.isDecoded = true
    }
    
    /**
     * Adds the processing elements needed for the image display to the pipeline state.
     */
    internal func addElements(_ state: RenderPipelineState) throws {
        try self.image.insertProcessingElements(state)
    }
    
    // MARK: - Errors
    public enum Errors: Error {
        /// Failed to read image at the given url
        case readImageFailed(_ url: URL)
        /// Couldn't create a buffer for the image data
        case makeBufferFailed
        /// Couldn't create a tiled image to hold the decoded image
        case makeTiledImageFailed
    }
}
