//
//  Retriever.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200626.
//

import Foundation
import CoreData
import ImageIO

import Paper
import CocoaLumberjackSwift

/**
 * Provides an interface to read existing thumbnails from the directory and reading images out of chunks.
 */
internal class Retriever {
    /// Data store containing thumbnail metadata
    private var directory: ThumbDirectory!
    
    /// Work queue for thumbnail generation
    private var queue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Retriever"
        queue.qualityOfService = .userInitiated
        return queue
    }()
    
    // MARK: - Initialization
    /**
     * Creates a new retriever using the provided directory as a data source.
     */
    init(_ directory: ThumbDirectory) {
        self.directory = directory
    }
    
    /**
     * Ensures all operations are terminated on deallocation.
     */
    deinit {
        self.queue.cancelAllOperations()
    }
    
    // MARK: - Public API
    /**
     * Attempts to fullfill the given thumbnail request.
     *
     * Requests run asynchronously on a background queue.
     */
    internal func retrieve(_ request: ThumbRequest, _ completion: @escaping (Result<CGImage, Error>) -> Void) {
        self.queue.addOperation {
            do {
                // validate the request
                var size = CGSize.zero
                
                if let reqSize = request.size {
                    size = reqSize
                }
                // get thumbnail from the store
                guard let thumb = try self.directory.getThumb(request: request) else {
                    throw RetrieverErrors.noSuchThumb
                }
                
                // read the best image
                let image = try self.getBestThumb(thumb, size)
                return completion(.success(image))
            }
            // propagate any errors to the caller
            catch {
                return completion(.failure(error))
            }
        }
    }
    
    // MARK: - Retrieval
    /**
     * Reads the thumbnail that most closely matches the requested size.
     */
    private func getBestThumb(_ thumb: Thumbnail, _ size: CGSize) throws -> CGImage {
        // get the chunk and chunk identifier for this thumb
        guard let chunk = thumb.chunk, let chunkId = chunk.identifier,
              let chunkEntryId = thumb.chunkEntryIdentifier else {
            throw RetrieverErrors.invalidChunk
        }
        
        let entry = try self.directory.chonker.getEntry(fromChunk: chunkId,
                                                        entryId: chunkEntryId)
        
        // create an image source for chunk data
        let opt = [
            // provide a guess of the image type as what the generator writes
            kCGImageSourceTypeIdentifierHint: Generator.utiString
        ]
        
        guard let src = CGImageSourceCreateWithData(entry.data as CFData,
                                                    opt as CFDictionary) else {
            throw RetrieverErrors.sourceCreateFailed
        }
        guard CGImageSourceGetCount(src) > 0 else {
            throw RetrieverErrors.noImagesInSource
        }
        
        // try to find the most suitable image
        if size == .zero {
            // get the first image
            guard let image = CGImageSourceCreateImageAtIndex(src, 0,
                                  Self.createImageOptions as CFDictionary) else {
                throw RetrieverErrors.imageCreateFailed(0)
            }
            
            return image
        } else {
            // otherwise, find the closest sized thumb
            let edge = max(size.width, size.height)
            return try self.closestImage(src, Int(edge))
        }
    }
    
    /**
     * Given an image source and desired edge with, finds the image that has the smallest difference in the
     * large edge and the given value.
     *
     * This means you may get an image that is _smaller_ than requested, even if there is a larger image
     * available.
     */
    private func closestImage(_ source: CGImageSource, _ edge: Int) throws -> CGImage {
        // find which image has the smallest difference to the requested edge
        var difference: Int = Int.max
        var index: Int? = nil
        
        for i in 0..<CGImageSourceGetCount(source) {
            // copy the properties
            guard let dict = CGImageSourceCopyPropertiesAtIndex(source, i, nil),
                  let props = dict as? [CFString: Any] else {
                throw RetrieverErrors.copyPropertiesFailed(i)
            }
            // get width/height
            guard let width = props[kCGImagePropertyPixelWidth] as? Int,
                  let height = props[kCGImagePropertyPixelHeight] as? Int else {
                throw RetrieverErrors.sizingFailed(i)
            }
            
            // is the difference smaller than the previous one?
            if abs(max(width, height) - edge) < difference {
                difference = abs(max(width, height) - edge)
                index = i
            }
        }
        
        // read the most suitable image
        guard let i = index else {
            throw RetrieverErrors.noSuitableImage
        }
        
        guard let image = CGImageSourceCreateImageAtIndex(source, i,
                              Self.createImageOptions as CFDictionary) else {
            throw RetrieverErrors.imageCreateFailed(i)
        }
        
        return image
    }
    
    /**
     * Options to use when reading images out of thumbnails.
     *
     * This disallows caching of decoded images.
     */
    private static let createImageOptions: [CFString: Any] = [
        kCGImageSourceShouldCache: false
    ]
    
    // MARK: - Errors
    enum RetrieverErrors: Error {
        /// The request is invalid
        case invalidRequest
        /// No thumbnail exists for the given request
        case noSuchThumb
        /// The thumbnail doesn't have an associated chunk
        case invalidChunk
        
        /// `CGImageSourceCreateWithData` failed; the data is probably corrupt
        case sourceCreateFailed
        /// No images were found in the chunk data
        case noImagesInSource
        /// Couldn't get image properties for one of the thumbnails
        case copyPropertiesFailed(_ index: Int)
        /// Size of the image at the given index could not be determined
        case sizingFailed(_ index: Int)
        /// No image was suitable to satisfy the request (shouldn't happen)
        case noSuitableImage
        /// Failed to create an image with the given index
        case imageCreateFailed(_ index: Int)
    }
}
