//
//  PipelineCache.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200822.
//

import Foundation

/**
 * Provides a mechanism to cache arbitrary objects in main memory. The cache is aware of the system's memory needs and will decide
 * what data is actually kept around based on some heuristics.
 */
internal class PipelineCache {
    /// Flags that affect cache behavior
    private var hints: CacheHints
    
    // MARK: - Initialization
    /**
     * Creates a new cache instance with the given behavior hints.
     */
    init(_ hints: CacheHints = []) {
        self.hints = hints
    }
    
    // MARK: - Types
    /// Hints to the cache implementation
    struct CacheHints: OptionSet {
        /// Treat all cache requests as a no-op
        static let passthrough = CacheHints(rawValue: 1 << 0)
        
        let rawValue: UInt32
    }
}
