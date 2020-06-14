//
//  ThumbServer.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200611.
//

import Foundation
import CoreGraphics

import Waterpipe
import CocoaLumberjackSwift

/**
 * Provides the interface used by XPC clients to generate and request thumbnail images.
 */
class ThumbServer: ThumbXPCProtocol {
    /// Background work queue
    private var queue = OperationQueue()

    // MARK: - Initialization
    /**
     * Sets up the thumb server.
     */
    init() {
        self.queue.name = "ThumbServer Work Queue"
        self.queue.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount
    }

    // MARK: - Thumb Retrieval
    /**
     * Attempts to retrieve a thumbnail for the provided image.
     *
     * Right now, this is just a pretty shitty wrapper around ImageIO.
     */
    func retrieve(_ request: ThumbRequest, _ callback: (Result<CGImage, Error>) -> Void) {
        // get the original image
        let url = request.imageUrl

        // create an image source
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return callback(.failure(RetrievalError.readError))
        }

        // get a thumbnail
        var opt: [CFString: Any] = [
            // let ImageIO cache the thumbnail
            kCGImageSourceShouldCache: true,
            // create the thumbnail always
            kCGImageSourceCreateThumbnailFromImageAlways: true,
        ]

        if let size = request.size, size != .zero {
            opt[kCGImageSourceThumbnailMaxPixelSize] = max(size.width, size.height)
        }

        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opt as CFDictionary) else {
            return callback(.failure(RetrievalError.generationFailed))
        }

        // run callback
        callback(.success(img))
    }

    /**
     * Errors raised during image retrieval
     */
    enum RetrievalError: Error {
        /// The request was invalid.
        case invalidRequest
        /// Failed to open the original image.
        case readError
        /// Something went wrong while creating the thumbnail.
        case generationFailed
    }

    // MARK: - XPC Calls
    /**
     * Loads the thumbnail directory, if not done already.
     */
    func wakeUp(withReply reply: @escaping (Error?) -> Void) {
        // nothing to be done
        reply(nil)
    }

    /**
     * Gets the thumbnail for the provided image.
     */
    func get(_ request: ThumbRequest, withReply reply: @escaping (ThumbRequest, IOSurface?, Error?) -> Void) {
        // perform actual work on the background queue
        self.queue.addOperation {
            self.retrieve(request) { res in
                switch res {
                    // pass the image forward to the reply
                    case .success(let image):
                        // create a surface from the image
                        let surface = IOSurface.fromImage(image)
                        reply(request, surface, nil)
                        surface?.decrementUseCount()

                    // some sort of error took place, pass that
                    case .failure(let error):
                        reply(request, nil, error)
                }
            }
        }
    }
}
