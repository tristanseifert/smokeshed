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
    // MARK: - Initialization
    /**
     * Attempts to create a new render pipeline image from the file at the given url.
     *
     * This will automatically determine how to get at the image data (by invoking the correct camera raw reader) and read some
     * preliminary metadata from it.
     *
     * - Note: `Progress` reporting is supported. All processing takes place synchronously.
     */
    public init(url: URL) throws {
        // TODO: determine how to read the image
    }
    
    // MARK: - Decoding
    /**
     * Device on which the image was most recently decoded. This is the device that contains the image tile texture and image
     * data buffer objects.
     */
    private(set) public var device: MTLDevice? = nil
    /// Has the image been decoded yet?
    private(set) internal var isDecoded: Bool = false
    
    /**
     * Decodes the image.
     *
     * If the image has previously been decoded, and the device on which it was decoded was the same as the device for which
     * the current decode is requested, the call is a no-op.
     *
     * - Note: `Progress` reporting is supported. This runs synchronously on the caller thread, and may take a not
     * insignificant amount of time.
     */
    internal func decode(device: MTLDevice) throws {
        // short circuit if decode is valid
        if self.isDecoded, let lastDevice = self.device,
           lastDevice.registryID == device.registryID {
            return
        }
        
        // TODO: actually decode
    }
}
