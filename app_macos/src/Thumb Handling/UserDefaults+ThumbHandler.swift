//
//  UserDefaults+ThumbHandler.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200626.
//

import Foundation

/**
 * Adds keys to the user defaults for the thumbnail service.
 */
extension UserDefaults {
    /// Is the chunk cache automatically sized?
    @objc dynamic var thumbChunkCacheSizeAuto: Bool {
        get {
            return self.bool(forKey: "thumbChunkCacheSizeAuto")
        }
        set {
            set(newValue, forKey: "thumbChunkCacheSizeAuto")
        }
    }
    /// Size of the thumbnail chunk cache, in bytes.
    @objc dynamic var thumbChunkCacheSize: Int {
        get {
            return self.integer(forKey: "thumbChunkCacheSize")
        }
        set {
            set(newValue, forKey: "thumbChunkCacheSize")
        }
    }
    
    /// Should the thumbnail generator queue be sized by the system?
    @objc dynamic var thumbWorkQueueSizeAuto: Bool {
        get {
            return self.bool(forKey: "thumbWorkQueueSizeAuto")
        }
        set {
            set(newValue, forKey: "thumbWorkQueueSizeAuto")
        }
    }
    /// If manually sized, how many threads are to be used for the generator work queue?
    @objc dynamic var thumbWorkQueueSize: Int {
        get {
            return self.integer(forKey: "thumbWorkQueueSize")
        }
        set {
            set(newValue, forKey: "thumbWorkQueueSize")
        }
    }
    
    /// Where is thumbnail data stored?
    @objc dynamic var thumbStorageUrl: URL {
        get {
            return self.url(forKey: "thumbStorageUrl")!
        }
        set {
            set(newValue, forKey: "thumbStorageUrl")
        }
    }
}
