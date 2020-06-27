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
    /// Size of the thumbnail chunk cache, in bytes.
    @objc dynamic var thumbChunkCacheSize: Int {
        get {
            return self.integer(forKey: "thumbChunkCacheSize")
        }
        set {
            set(newValue, forKey: "thumbChunkCacheSize")
        }
    }
}
