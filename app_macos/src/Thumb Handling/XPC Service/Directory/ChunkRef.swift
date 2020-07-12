//
//  ChunkRef.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200621.
//

import Foundation

/**
 * Class representing a single chunk of thumbnail data on disk.
 */
internal class ChunkRef: Codable {
    /// Lock restricting writes to the chunk
    private(set) internal var writeLock = NSLock()
    
    /// Chunk version
    private(set) internal var version: UInt = ChunkRef.currentVersion
    /// Identifier of the chunk
    internal var identifier: UUID!
    
    /// File entries
    internal var entries: [Entry] = []
    
    /// Has the chunk been modified? Determines whether it is written to disk when released
    internal var isDirty: Bool = false
    
    /// Total bytes required for storing payload of the chunk
    internal var payloadBytes: Int {
        return self.entries.reduce(0) { $0 + $1.data.count }
    }
    
    /**
     * Thumbnail chunk entry for a single file; this contains all thumbnail images associated with that file.
     */
    internal struct Entry: Codable {
        /// Database identifier of the thumbnail
        internal var directoryId: UUID
        /// Associated thumbnail data
        internal var data: Data
    }
    
    /// Properties to encode/decode
    enum CodingKeys: String, CodingKey {
        case version
        case identifier
        case entries
    }
    
    // MARK: - Constants
    /// Current chunk version
    internal static let currentVersion: UInt = 0x00000100
    
    /// Approximate maximum payload size
    internal static let maxPayload: Int = (1024 * 1024 * 5)
}
