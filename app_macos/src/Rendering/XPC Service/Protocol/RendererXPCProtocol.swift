//
//  RendererXPCProtocol.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200712.
//

import Foundation

/**
 * Type of renderer
 */
@objc enum RendererType: UInt {
    /**
     * Renderer optimized for display. The caller defines the size of a viewport, which in turn results in a texture that can be drawn at its
     * original size. It can then adjust the offset and scale of the viewport, with the renderer filling in appropriately.
     */
    case display
    
    /**
     * Draws the output into a bitmap, which is passed to the caller by means of a shared memory buffer and bitmap descriptor. This can
     * be used to quickly draw thumbnails or other small images for display, or when more extensive processing on the raw bitmap
     * data (which must be in memory the entire time) is needed.
     */
    case bitmap
    
    /**
     * Renders the image and writes the output to a file on disk. The type of file, compression, and location are provided by the caller,
     * in addition to normal renderer options.
     */
    case file
}

/**
 * Interface of the object exported by the renderer XPC service
 */
@objc protocol RendererXPCProtocol {
    /**
     * Gets a renderer object of the given type with the given handler.
     */
    func dispense(_ type: RendererType, handler: RendererHandlerXPCProtocol, withReply reply: @escaping (Error?, RendererInstanceXPCProtocol?) -> Void)
}

/**
 * A renderer object dispensed by the renderer service. It may have several different types of renderers (for display, thumbnails, writing to
 * disk, etc.) that process data differently and present their results in different ways, but they all implement the same interface.
 */
@objc protocol RendererInstanceXPCProtocol {
    /**
     * Kicks off a render job with the given description. The reply block is called with any errors that took place during the
     * setup phase of the render, or an identifier by which the job can be tracked. All requests made to the handler object
     * contain this identifier.
     *
     * This method supports progress reporting (via `Progress`)
     */
    func render(_ jobDescriptor: [AnyHashable: Any], withReply reply: @escaping (Error?, UUID?) -> Void)
}

/**
 * App-side handler interface that each dispensed renderer calls into with progress and completion of requests.
 */
@objc protocol RendererHandlerXPCProtocol {
    /**
     * A render job failed.
     */
    func jobFailed(_ jobId: UUID, _ error: Error)

    /**
     * Render job completed successfully. The renderer's output information (result) is provided as a dictionary.
     */
    func jobCompleted(_ jobId: UUID, _ result: [AnyHashable: Any])
}
