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
    /// Thumbnail directory
    private var directory: ThumbDirectory! = nil

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
        let url = request.imageUrl!

        // create an image source
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return callback(.failure(RetrievalError.readError))
        }

        // get a thumbnail
        var opt: [CFString: Any] = [
            // let ImageIO cache the thumbnail
            kCGImageSourceShouldCache: false,
            // create the thumbnail always
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
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
        // open thumbnail directory if needed
        if self.directory == nil {
            do {
                self.directory = try ThumbDirectory()
            } catch {
                DDLogError("Failed to open thumb directory: \(error)")
                return reply(error)
            }
            
            // if we get here, directory opened successfully
            reply(nil)
        }
        // otherwise, nothing to be done
        else {
            reply(nil)
        }
    }
    
    /**
     * Opens a library with the given UUID. This will create an entry for it in the library directory if needed.
     */
    func openLibrary(_ libraryId: UUID, withReply reply: @escaping (Error?) -> Void) {
        DDLogVerbose("Opening thumb library: \(libraryId)")
        
        do {
            try self.directory.openLibrary(libraryId)
        } catch {
            DDLogError("Failed to open library: \(error)")
            return reply(error)
        }
        
        // library was opened successfully
        reply(nil)
    }
    
    /**
     * Generates a thumbnail for the image specified in the request. This is dispatched to the background
     * processing thread.
     */
    func generate(_ requests: [ThumbRequest]) {
        DDLogInfo("Generating thumbs for images: \(requests)")
    }
    
    /**
     * Discards thumbnail data for all images specified.
     *
     * Images are identified only by their library id and image id; the URL and orientation are ignored.
     */
    func discard(_ requests: [ThumbRequest]) {
        DDLogInfo("Discarding images: \(requests)")
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
