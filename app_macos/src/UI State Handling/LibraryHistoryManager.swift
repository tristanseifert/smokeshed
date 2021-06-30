//
//  LibraryHistoryManager.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200606.
//

import Foundation
import Bowl
import OSLog

/**
 * Provides an interface to the library open history. This is maintained as an ordered set of URLs, where the
 * topmost (first) URL is the most recently opened one.
 */
class LibraryHistoryManager {
    fileprivate static var logger = Logger(subsystem: Bundle(for: LibraryHistoryManager.self).bundleIdentifier!,
                                         category: "LibraryHistoryManager")
    
    /// URL to the history file
    static var historyUrl: URL! {
        return Bowl.ContainerHelper.groupCache.appendingPathComponent("LibraryHistory.plist", isDirectory: false)
    }
    
    /// set containing URLs
    private static var urls: NSMutableOrderedSet = NSMutableOrderedSet()
    
    /**
     * Loads history from disk.
     */
    static func loadHistory() {
        // attempt to read data from disk and unarchive
        do {
            let data = try Data(contentsOf: self.historyUrl)
            let set = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)
            
            if let swiftSet = set as? NSMutableOrderedSet {
                self.urls = swiftSet
            } else {
                // failed to convert history, so overwrite it
                self.writeHistory()
            }
        } catch {
            Self.logger.error("Failed to read history from \(self.historyUrl!): \(error.localizedDescription)")
       }
    }
    
    /**
     * Writes history out to disk.
     */
    static func writeHistory() {
        // convert to NSSet, then archive to disk
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: self.urls,
                                                        requiringSecureCoding: true)
            try data.write(to: self.historyUrl, options: .atomic)
        } catch {
            Self.logger.error("Failed to write history to \(self.historyUrl!): \(error.localizedDescription)")
        }
    }
    
    /**
     * Handles opening of a library. It will be prepended to the set.
     */
    static func openLibrary(_ url: URL) {
        // move existing entry
        if self.urls.contains(url) {
            let indexSet = IndexSet(integer: self.urls.index(of: url))
            self.urls.moveObjects(at: indexSet, to: 0)
        }
        // create new entry
        else {
            self.urls.insert(url, at: 0)
        }
        
        self.writeHistory()
    }
    
    /**
     * If the given URL is in the history, remove it.
     */
    static func removeLibrary(_ url: URL) {
        self.urls.remove(url)
        self.writeHistory()
    }
    
    /**
     * Returns an ordered array of library URLs.
     */
    static func getLibraries() -> [URL] {
        // attempt to load if no urls
        if self.urls.count == 0 {
            self.loadHistory()
        }
        
        return self.urls.array as! [URL]
    }

    /**
     * Returns the most recently opened library URL, or nil if there is none.
     */
    static func getMostRecentlyOpened() -> URL! {
        // attempt to load if no urls
        if self.urls.count == 0 {
            self.loadHistory()
        }

        // if there's STILL no URLs, abort
        if self.urls.count == 0 {
            return nil
        }

        // get the first one's URL
        return self.urls.firstObject as? URL
    }
}
