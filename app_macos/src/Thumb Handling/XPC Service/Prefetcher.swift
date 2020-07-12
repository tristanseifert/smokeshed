//
//  Prefetcher.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200629.
//

import Foundation
import CoreData

import CocoaLumberjackSwift


/**
 * Handles prefetching thumbnail data from disk to speed up later thumbnail requests.
 */
internal class Prefetcher {
    /// Data store containing thumbnail metadata
    private var directory: ThumbDirectory!
        
    // MARK: - Initialization
    /**
     * Creates a new retriever using the provided directory as a data source.
     */
    init(_ directory: ThumbDirectory) {
        self.directory = directory
    }
    
    // MARK: - Public API
    /**
     * Prefetches data for the given images.
     *
     * In the current implementation, this will:
     *  - Read all chunk information from the directory, faulting it in from disk as needed
     *  - Load the chunk containing information from disk and place it in the chunk cache
     */
    internal func prefetch(_ requests: [ThumbRequest]) {
        do {
            // try to load thumb info from data store
            let existing = try requests.compactMap() { try self.directory.getThumb(request: $0) }
            
            // load each chunk
            var loadedChunks: [UUID] = []
            
            for thumb in existing {
                // ensure the chunk id is valid
                guard let chunkId = thumb.chunk?.identifier else { continue }
                // skip if we've already requested to load the chunk
                guard !loadedChunks.contains(chunkId) else { continue }
                
                // read it from disk
                try self.directory.chonker.preloadChunk(chunkId)
                loadedChunks.append(chunkId)
            }
        } catch {
            DDLogError("prefetch(_:) (requests: \(requests)) failed: \(error)")
        }
    }
}
