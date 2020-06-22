//
//  ChunkManager.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200621.
//

import Foundation
import CoreData

import Bowl
import CocoaLumberjackSwift

/**
 * Provides an interface for reading chunks of thumbnail data from disk.
 */
internal class ChunkManager: NSObject, NSCacheDelegate {
    /// Managed object context specifically for the chunk manager
    private var ctx: NSManagedObjectContext!
    /// Base URL to the chunk directory
    private var chunkDir: URL
    
    // MARK: - Initialization
    /**
     * Initializes a chunk manager with the given directory as its data source.
     */
    internal init(withDirectory directory: ThumbDirectory) throws {
        // create a context from it
        let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        
        ctx.automaticallyMergesChangesFromParent = true
        ctx.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        
        ctx.parent = directory.mainCtx
        
        self.ctx = ctx
        
        // get chunk directory
        let url = ContainerHelper.groupCache.appendingPathComponent("Thumbs",
                                                                    isDirectory: true)
        
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        }
        
        self.chunkDir = url
        
        // allocate super
        super.init()
        
        // configure cache
        self.chunkCache.totalCostLimit = Self.maxChunkCacheSize
        self.chunkCache.evictsObjectsWithDiscardedContent = true
        self.chunkCache.delegate = self
    }
    
    // MARK: - Cache support
    /// Cache containing chunk refs that have been decoded from disk
    private var chunkCache = NSCache<NSUUID, ChunkRef>()
    
    // MARK: Cache access
    /**
     * Retrieves a chunk with the given identifier from the cache. If it is not present in memory, we try to
     * load it from disk.
     *
     * This assumes that the chunk does exist in the directory.
     */
    internal func getChunk(withId id: UUID) throws -> ChunkRef {
        // can we get it out of the cache?
        if let ref = self.chunkCache.object(forKey: id as NSUUID) {
            return ref
        }
        
        // it's not in the cache, so load it then add it
        let chunk = try self.readChunk(withId: id)
        self.chunkCache.setObject(chunk, forKey: id as NSUUID,
                                  cost: chunk.payloadBytes)
        
        return chunk
    }
    
    /**
     * Inserts a chunk into the cache. This ensures the chunk is persisted to disk.
     */
    internal func addChunk(_ chunk: ChunkRef) throws {
        // ensure chunk is written out to disk before adding to cache
        try self.saveChunk(chunk)
        
        self.chunkCache.setObject(chunk, forKey: chunk.identifier as NSUUID,
                                  cost: chunk.payloadBytes)
    }
    
    // MARK: Cache delegate
    /**
     * Writes changed cache items to disk as they are evicted.
     */
    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // get chunk ref
        guard let chunk = obj as? ChunkRef else {
            fatalError("Failed to convert cache object: \(obj)")
        }
        
        DDLogVerbose("Evicting \(obj)")
        
        // save it out to disk if it's changed
        if chunk.isDirty {
            do {
                try self.saveChunk(chunk)
            } catch {
                DDLogError("Failed to save chunk \(String(describing: chunk)): \(error)")
            }
        }
    }
    
    // MARK: - Disk IO
    /**
     * Saves a chunk to disk.
     */
    internal func saveChunk(_ chunk: ChunkRef) throws {
        // produce data to encode
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        
        let data = try encoder.encode(chunk)
        
        // write it out to file
        let url = try self.urlForChunk(withId: chunk.identifier)
        try data.write(to: url, options: .atomic)
        
        // clear the dirty flag
        chunk.isDirty = false
    }
    
    /**
     * Reads a chunk with the given identifier from disk.
     */
    internal func readChunk(withId id: UUID) throws -> ChunkRef {
        // read data
        let url = try self.urlForChunk(withId: id)
        let data = try Data(contentsOf: url)
        
        // decode it
        let decoder = PropertyListDecoder()
        let obj = try decoder.decode(ChunkRef.self, from: data)
        
        // ensure its version matches
        guard obj.version == ChunkRef.currentVersion else {
            throw IOErrors.unsupportedChunkVersion(obj.version)
        }
        
        // done
        return obj
    }
    
    /**
     * Gets the url at which the thumbnail chunk with the given identifier is located.
     *
     * Chunk urls are made up of a first-level directory (the first byte of the uuid, converted to an uppercase
     * hex string) followed by the full UUID as the filename.
     */
    private func urlForChunk(withId id: UUID) throws -> URL {
        let fm = FileManager.default
        
        // get the first byte of the uuid
        let first = String(id.uuid.0, radix: 16, uppercase: true)
        let name = String(format: "%@.chonker", id.uuidString)
        
        // get container directory url (and create dir if needed)
        let dir = self.chunkDir.appendingPathComponent(first, isDirectory: true)
        
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                   attributes: nil)
        }
        
        // return the url to the chunk
        return dir.appendingPathComponent(name, isDirectory: false)
    }
    
    // MARK: - Constants
    /// Maximum chunk cache size, bytes
    private static let maxChunkCacheSize: Int = (1024 * 1024 * 128)
    
    // MARK: - Errors
    /// Chunk IO errors
    enum IOErrors: Error {
        /// Decoded a chunk with an unsupported version
        case unsupportedChunkVersion(_ actual: UInt)
    }
}
