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
 *
 * Callers can retrieve and remove entries from an existing chunk, as well as remove the entire chunk. To add
 * new data, provide an entry and it will be added to the most suitable chunk.
 */
internal class ChunkManager: NSObject, NSCacheDelegate {
    /// Managed object context specifically for the chunk manager
    private var ctx: NSManagedObjectContext!
    /// Base URL to the chunk directory
    private(set) internal var chunkDir: URL
    
    // MARK: - Initialization
    /// Observers on user defaults keys related to chunks
    private var kvos: [NSKeyValueObservation] = []
    
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
        let cache = ContainerHelper.groupAppCache(component: .thumbHandler)
        let url = cache.appendingPathComponent("Chonkery", isDirectory: true)
        
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
        
        // observe cache size changes
        let sizeObs = UserDefaults.thumbShared.observe(\.thumbChunkCacheSize,
                                                       options: [])
        { _, _ in
            self.refreshSettings()
        }
        self.kvos.append(sizeObs)
        
        // register for reload config notification
        self.reloadConfigObs = NotificationCenter.default.addObserver(forName: .reloadConfigNotification,
                                                                      object: nil,
                                                                      queue: nil)
        { [weak self] _ in
            self?.refreshSettings()
        }
        
        self.refreshSettings()
    }
    
    /**
     * Remove notification observers.
     */
    deinit {
        NotificationCenter.default.removeObserver(self.reloadConfigObs!)
    }
    
    // MARK: Configuration
    /// Notification handler for config reloading
    private var reloadConfigObs: NSObjectProtocol!
    
    /**
     * Updates the size of the thumbnail cache based on configuration.
     */
    private func refreshSettings() {
        // get the new cache size
        let new = UserDefaults.thumbShared.thumbChunkCacheSize
        
        if new > (1024 * 1024 * 16) {
            DDLogVerbose("New thumb cache size: \(new)")
            self.chunkCache.totalCostLimit = new
        } else {
            DDLogWarn("Ignoring too small cache size: \(new)")
        }
    }
    
    // MARK: - Public interface
    /**
     * Gets an entry from a chunk.
     */
    internal func getEntry(fromChunk chunkId: UUID, entryId: UUID) throws -> ChunkRef.Entry {
        // read chunk and extract entry
        let chunk = try self.getChunk(withId: chunkId, true)
    
        guard let entry = chunk.entries.first(where: { $0.directoryId == entryId }) else {
            throw ChunkErrors.noSuchEntry(chunkId: chunkId, entryId)
        }
        
        // return the chunk we've found
        return entry
    }
    
    /**
     * Writes an entry to the most optimal chunk; its identifier is returned.
     */
    internal func writeEntry(_ entry: ChunkRef.Entry) throws -> UUID {
        precondition(entry.data.count < ChunkRef.maxPayload, "Chunk entry may not be larger than maximum chunk payload size")
        
        // create a write chunk if there is not one
        if self.writeChunk == nil {
            try self.newWriteChunk()
        }
        
        // create new write chunk if it doesn't have sufficient space
        if (self.writeChunk!.payloadBytes + entry.data.count) > ChunkRef.maxPayload {
            try self.newWriteChunk()
        }
        
        guard let write = self.writeChunk else {
            throw ChunkErrors.noWriteChunk
        }
        
        // get write lock
        write.writeLock.lock()
        
        // append the entry to the chunk
        write.entries.append(entry)
        write.isDirty = true
        
        write.writeLock.unlock()
        
        // write it back to disk
        try self.saveChunk(write)
        
        return write.identifier!
    }
    
    /**
     * Replaces an entry in an existing chunk.
     */
    internal func replaceEntry(inChunk chunkId: UUID, entry: ChunkRef.Entry) throws {
        // remove the existing entry
        let entryId = entry.directoryId
        let chunk = try self.getChunk(withId: chunkId, false)
        
        // take write lock before removing old entries
        chunk.writeLock.lock()
        
        let beforeCount = chunk.entries.count
        chunk.entries.removeAll(where: { $0.directoryId == entryId })
        
        guard chunk.entries.count < beforeCount else {
            chunk.writeLock.unlock()
            throw ChunkErrors.noSuchEntry(chunkId: chunkId, entryId)
        }
        
        // insert new entry
        chunk.entries.append(entry)
        
        chunk.isDirty = true
        chunk.writeLock.unlock()
        
        // write it back to disk
        try self.saveChunk(chunk)
        
        // TODO: we really should validate this won't make us over the max size
    }
    
    /**
     * Removes an entry from a chunk, both identified by their respective ids.
     */
    internal func deleteEntry(inChunk chunkId: UUID, entryId: UUID) throws {
        // get the chunk and acquire write lock
        let chunk = try self.getChunk(withId: chunkId, false)
        chunk.writeLock.lock()
        
        // remove that entry from the chunk
        let beforeCount = chunk.entries.count
        chunk.entries.removeAll(where: { $0.directoryId == entryId })
        
        guard chunk.entries.count < beforeCount else {
            chunk.writeLock.unlock()
            throw ChunkErrors.noSuchEntry(chunkId: chunkId, entryId)
        }
        
        chunk.isDirty = true
        
        // release the lock
        chunk.writeLock.unlock()

        // if the chunk has no entries, delete it
        if chunk.entries.isEmpty {
            try self.deleteChunk(withId: chunkId)
        }
        // otherwise, write it back to disk
        else {
            try self.saveChunk(chunk)
        }
    }
    
    /**
     * Deletes chunk data for a chunk with the provided identifier.
     */
    internal func deleteChunk(withId id: UUID) throws {
        // if we cached the chunk: mark as clean and remove from cache
        if let chunk = self.chunkCache.object(forKey: id as NSUUID) {
            chunk.isDirty = false
            self.chunkCache.removeObject(forKey: id as NSUUID)
        }
        
        // delete this chunk from the filesystem
        let url = try self.urlForChunk(withId: id)
        
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    /**
     * Ensures all dirty chunks in the cache are written out to disk.
     */
    internal func flushDirtyChunks() throws {
        // TODO: implement
    }
    
    // MARK: - Cache support
    /// Cache containing chunk refs that have been decoded from disk
    private var chunkCache = NSCache<NSUUID, ChunkRef>()
    
    /// Most optimal chunk for writing; if nil, a new chunk should be created
    private var writeChunk: ChunkRef? = nil
    
    // MARK: Cache access
    /**
     * Retrieves a chunk with the given identifier from the cache. If it is not present in memory, we try to
     * load it from disk.
     *
     * This assumes that the chunk does exist in the directory.
     */
    private func getChunk(withId id: UUID, _ shouldCache: Bool) throws -> ChunkRef {
        // can we get it out of the cache?
        if let ref = self.chunkCache.object(forKey: id as NSUUID) {
            return ref
        }
        
        // it's not in the cache, so load it then add it
        let chunk = try self.readChunk(withId: id)
        
        if shouldCache {
            self.chunkCache.setObject(chunk, forKey: id as NSUUID,
                                      cost: chunk.payloadBytes)
        }
        
        return chunk
    }
    
    /**
     * Inserts a chunk into the cache. This ensures the chunk is persisted to disk.
     */
    private func addChunk(_ chunk: ChunkRef) throws {
        // ensure chunk is written out to disk before adding to cache
        if chunk.isDirty {
            try self.saveChunk(chunk)
        }
        
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
        
        // save it out to disk if it's changed
        if chunk.isDirty {
            do {
                try self.saveChunk(chunk)
            } catch {
                DDLogError("Failed to save chunk \(String(describing: chunk)): \(error)")
            }
        }
    }
    
    // MARK: Write chunk cache
    /**
     * Creates a new write chunk; if there exists an old one, it is written to disk.
     */
    private func newWriteChunk() throws {
        // write old chunk out to disk, if needed
        if let old = self.writeChunk {
            if old.isDirty {
                try self.saveChunk(old)
            }
        }
        
        // create a new chunk (not dirty; explicitly saved by callers tho)
        let new = ChunkRef()
        new.identifier = UUID()
        new.isDirty = false
        
        self.writeChunk = new
        
        // it should be in the cache
        try self.addChunk(new)
    }
    
    // MARK: - Disk IO
    /**
     * Saves a chunk to disk.
     */
    private func saveChunk(_ chunk: ChunkRef) throws {
        // before encoding and writing to disk, take a lock on the chunk
        chunk.writeLock.lock()
        
        do {
            // produce data to encode
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            
            let data = try encoder.encode(chunk)
            
            // write it out to file
            let url = try self.urlForChunk(withId: chunk.identifier)
            try data.write(to: url, options: .atomic)
        } catch {
            // ensure chunk lock is released
            chunk.writeLock.unlock()
            throw error
        }
        
        // release the chunk lock
        chunk.writeLock.unlock()
        
        // clear the dirty flag
        chunk.isDirty = false
    }
    
    /**
     * Reads a chunk with the given identifier from disk.
     */
    private func readChunk(withId id: UUID) throws -> ChunkRef {
        // read data
        let url = try self.urlForChunk(withId: id)
        let data = try Data(contentsOf: url)
        
        // decode it
        let decoder = PropertyListDecoder()
        let chunk = try decoder.decode(ChunkRef.self, from: data)
        
        // ensure its version matches
        guard chunk.version == ChunkRef.currentVersion else {
            throw IOErrors.unsupportedChunkVersion(chunk.version)
        }
        
        // done
        return chunk
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
        let first = String(format: "%02X", id.uuid.0)
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
    private static let maxChunkCacheSize: Int = (1024 * 1024 * 250)
    
    // MARK: - Errors
    /// Public interface errors
    internal enum ChunkErrors: Error {
        /// A write chunk could not be created
        case noWriteChunk
        /// Failed to find an entry with the given id in the specified chunk.
        case noSuchEntry(chunkId: UUID, _ entryId: UUID)
    }
    
    /// Chunk IO errors
    enum IOErrors: Error {
        /// Decoded a chunk with an unsupported version
        case unsupportedChunkVersion(_ actual: UInt)
    }
}
