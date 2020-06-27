//
//  Generator.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200626.
//

import Foundation
import CoreData
import UniformTypeIdentifiers

import Paper
import CocoaLumberjackSwift

/**
 * This class handles generating thumbnail images, writing them to chunks and updating the thumbnail
 * directory. It also contains logic to delete existing thumbnails.
 */
internal class Generator {
    /// Data store containing thumbnail metadata
    private var directory: ThumbDirectory!
    
    /// Work queue for thumbnail generation
    private var queue: OperationQueue = {
        var queue = OperationQueue()
        queue.name = "Thumb Generator"
        queue.qualityOfService = .utility
        return queue
    }()
    
    // MARK: - Initialization
    /**
     * Creates a new thumb generator using the provided directory as a data source.
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
     * Requests thumbs to be generated for the provided images.
     *
     * Images that already exist will have their thumbnails regenerated.
     */
    internal func generate(_ requests: [ThumbRequest]) {
        do {
            var new = requests
            
            // find all already existing images (these are to be updated)
            let existing = try requests.compactMap()
            { req -> (Thumbnail, ThumbRequest)? in
                if let thumb = try self.directory.getThumb(request: req) {
                    return (thumb, req)
                }
                return nil
            }
            
            // get the requests that don't correspond to existing images
            if existing.count == new.count {
                new.removeAll()
            } else {
                // remove requests for which we've got thumb objects
                for thumb in existing {
                    new.removeAll(where: {
                        $0.libraryId == thumb.0.library!.identifier &&
                        $0.imageId == thumb.0.imageIdentifier
                    })
                }
            }
            
            // create operations for each new image
            for request in new {
                let flight = InFlightInfo(request)
                self.inFlight.append(flight)
                
                self.queue.addOperation {
                    do {
                        try self.generateNew(request)
                    } catch {
                        DDLogError("Creating new thumb for \(request) failed: \(error)")
                    }
                    
                    // remove the in-flight info
                    self.inFlight.removeAll(where: {
                        $0.libraryId == request.libraryId &&
                        $0.imageId == request.imageId
                    })
                }
            }
            
            // update the existing thumbs
            for thumb in existing {
                self.queue.addOperation {
                    do {
                        try self.updateExisting(thumb.0, thumb.1)
                    } catch {
                        DDLogError("Updating thumb for \(thumb) failed: \(error)")
                    }
                }
            }
            
            // save after all of these have completed
            self.queue.addBarrierBlock {
                do {
                    try self.directory.save()
                } catch {
                    DDLogError("Failed to save directory: \(error)")
                }
            }
        } catch {
            DDLogError("generate(_:) failed: \(error) (requests: \(requests))")
        }
    }
    
    /**
     * Discards thumbs for the given images.
     */
    internal func discard(_ requests: [ThumbRequest]) {
        do {
            // attempt to get thumb instances for each
            let thumbs = try requests.compactMap() {
                try self.directory.getThumb(request: $0)
            }
            
            if thumbs.count != requests.count {
                DDLogWarn("discard(_:) count mistmatch: requests \(requests) thumbs \(thumbs)")
            }
            
            // discard them and their chunk data asynchronously
            for thumb in thumbs {
                self.queue.addOperation {
                    do {
                        try self.discardThumb(thumb)
                    } catch {
                        DDLogError("Failed to remove thumb \(thumb): \(error)")
                    }
                }
            }
            
            // save after all removals have completed
            self.queue.addBarrierBlock {
                do {
                    try self.directory.save()
                } catch {
                    DDLogError("Failed to save directory: \(error)")
                }
            }
        } catch {
            DDLogError("generate(_:) failed: \(error) (requests: \(requests))")
        }
    }
    
    /**
     * Determines if there is a generation request in-flight for the image identified in the thumb request.
     */
    internal func isInFlight(_ request: ThumbRequest) -> Bool {
        return self.inFlight.contains(where: {
            $0.libraryId == request.libraryId &&
            $0.imageId == request.imageId
        })
    }
    
    // MARK: - Generation
    /// Information about an in-flight generation request
    private struct InFlightInfo {
        /// Library id
        var libraryId: UUID
        /// Image id
        var imageId: UUID
        
        init(_ request: ThumbRequest) {
            self.libraryId = request.libraryId
            self.imageId = request.imageId
        }
    }
    
    /// All in flight requests
    private var inFlight: [InFlightInfo] = []
    
    /**
     * Creates a new thumbnail for the given request.
     */
    private func generateNew(_ request: ThumbRequest) throws {
        // attempt to create thumb reader and create thumb data
        guard let reader = ThumbReader(request.imageUrl) else {
            throw GeneratorErrors.thumbReaderFailed(request.imageUrl)
        }
        
        let data = try self.makeThumbData(reader)
        
        // create the thumbnail in the directory
        let thumb = try self.directory.makeThumb(request: request)
        
        // write thumb data to a chunk
        let entry = ChunkRef.Entry(directoryId: thumb.chunkEntryIdentifier!,
                                   data: data)
        let chunkId = try self.directory.chonker.writeEntry(entry)
        
        // get reference to chunk or create and add the thumb
        let chunk = try self.directory.makeOrGetChunk(for: chunkId)
        
        self.directory.mainCtx.performAndWait {
            thumb.chunk = chunk
            chunk.addToThumbs(thumb)
        }
    }
    
    /**
     * Updates an existing thumbnail.
     */
    private func updateExisting(_ thumb: Thumbnail, _ request: ThumbRequest) throws {
        // TODO: implement
    }
    
    // MARK: Thumb drawing
    /**
     * Given a thumbnail reader, creates a data object containing all of the thumbnail sizes we want.
     */
    private func makeThumbData(_ reader: ThumbReader) throws -> Data {
        // get all thumb sizes that aren't larger than the actual image
        var sizes = Self.thumbMap
        
        sizes.removeAll(where: {
            return ($0.size.rawValue > Int(reader.originalSize.width)) ||
                   ($0.size.rawValue > Int(reader.originalSize.height))
        })
        
        // create an image destination
        let mut = NSMutableData()
        
        guard let dest = CGImageDestinationCreateWithData(mut as CFMutableData,
                                                          Self.utiString as CFString,
                                                          sizes.count,
                                                          nil) else {
            throw GeneratorErrors.destinationCreateFailed
        }
        
        // generate each thumb
        for info in sizes {
            let edge = info.size.rawValue
            
            // get a matching thumb from the generator
            guard let thumb = reader.getThumb(CGFloat(edge)) else {
                throw GeneratorErrors.thumbReaderGetFailed
            }
            
            // if one of the edges is the requested size, take it as-is
            guard thumb.width != edge, thumb.height != edge else {
                CGImageDestinationAddImage(dest, thumb, info.imageOptions)
                continue
            }
            // if both edges are smaller than the requested size, finish
//            guard thumb.width >= edge || thumb.height >= edge else {
//                break
//            }
            // scale thumbnail proportionally to the required size
            guard let scaled = self.scaleProportionally(thumb, CGFloat(edge)) else {
                throw GeneratorErrors.imageResizeFailed
            }
            
            CGImageDestinationAddImage(dest, scaled, info.imageOptions)
        }
        
        // finalize image destination
        guard CGImageDestinationFinalize(dest) else {
            throw GeneratorErrors.destinationFinalizeFailed
        }
        
        return (mut as Data)
    }
    
    /**
     * Scales the provided image proportionally such that the small edge has the given dimensions.
     *
     * - Note: This does not check whether the edge size will scale the image up or down.
     */
    private func scaleProportionally(_ image: CGImage, _ edge: CGFloat) -> CGImage? {
        // calculate new size
        var size = CGSize(width: image.width, height: image.height)
        
        if size.width > size.height {
            let ratio = size.width / size.height
            
            size.width = edge
            size.height = size.width / ratio
        } else {
            let ratio = size.height / size.width
            
            size.height = edge
            size.width = size.height / ratio
        }
        
        // create context to draw into
        let context = CGContext(data: nil,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: image.bitsPerComponent,
                                bytesPerRow: 0,
                                space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: image.bitmapInfo.rawValue)
        context?.interpolationQuality = .high
        
        // draw the image into the context and return it
        context?.draw(image, in: CGRect(origin: .zero, size: size))

        return context?.makeImage()
    }
    
    /**
     * Thumbnail sizes we generate; the raw value of each case specifies the length of the maximum edge
     * of the image.
     */
    enum ThumbSizes: Int {
        /// Small square image
        case smallSquare = 100
        /// Small thumb
        case small = 150
        /// Medium thumb
        case medium = 350
        /// Large thumb
        case large = 750
        /// Jumbo Size™
        case jumbo = 1250
    }
    
    /**
     * Information structure for a single thumb size to generate
     */
    private struct Info {
        /// Size
        var size: ThumbSizes
        /// Index in file
        var index: Int
        /// Compression quality
        var quality: Double
        
        /// Automagically generated options for `CGImageDestinationAddImage`
        var imageOptions: CFDictionary {
            let opts = [
                // compression quality
                kCGImageDestinationLossyCompressionQuality: self.quality
            ]
            
            return opts as CFDictionary
        }
    }
    
    /**
     * Information on each of the sized thumbnails to generate
     *
     * New entries _must_ be added to the end of the list.
     */
    private static let thumbMap: [Info] = [
        Info(size: .smallSquare, index: 0, quality: 0.69),
        Info(size: .small, index: 1, quality: 0.69),
        Info(size: .medium, index: 2, quality: 0.80),
        Info(size: .large, index: 3, quality: 0.80),
        Info(size: .jumbo, index: 4, quality: 0.70),
    ]
    
    /// UTI string defining the thumbnail iamge type
    internal static let utiString = UTType.heic.identifier
    
    // MARK: - Deletion
    /**
     * Discards all data stored in chunks for the given thumb.
     */
    private func discardThumb(_ thumb: Thumbnail) throws {
        // get the chunk id and entry id
        var chunkIdRaw: UUID?
        var entryIdRaw: UUID?
        
        thumb.managedObjectContext?.performAndWait {
            chunkIdRaw = thumb.chunk?.identifier
            entryIdRaw = thumb.chunkEntryIdentifier
        }
        
        guard let chunkId = chunkIdRaw, let entryId = entryIdRaw else {
            throw GeneratorErrors.invalidIdentifiers
        }
        
        // delete the thumbnail
        thumb.managedObjectContext?.performAndWait {
            thumb.managedObjectContext?.delete(thumb)
        }
        
        // remove chunk data
        DDLogInfo("Removing entry \(entryId) from chunk \(chunkId)")
        try self.directory.chonker.deleteEntry(inChunk: chunkId,
                                               entryId: entryId)
        
        // TODO: remove chunk object from directory if all entries were removed
    }
    
    // MARK: - Errors
    enum GeneratorErrors: Error {
        /// Couldn't create a thumbnail reader for the given url
        case thumbReaderFailed(_ url: URL)
        /// An image destination could not be created
        case destinationCreateFailed
        /// Image destination couldn't be finalized
        case destinationFinalizeFailed
        /// Failed to read a thumbnail from the original image
        case thumbReaderGetFailed
        /// Resizing of an image failed
        case imageResizeFailed
        
        /// The provided thumbnail has an invalid chunk or image id
        case invalidIdentifiers
    }
}
