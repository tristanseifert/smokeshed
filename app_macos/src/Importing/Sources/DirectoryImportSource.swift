//
//  DirectoryImportSource.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200828.
//

import AppKit
import Foundation
import UniformTypeIdentifiers
import OSLog

/**
 * An import source that (possibly recursively) enumerates the contents of a directory for image files.
 */
internal class DirectoryImportSource: ImportSource {
    fileprivate static var logger = Logger(subsystem: Bundle(for: DirectoryImportSource.self).bundleIdentifier!,
                                         category: "DirectoryImportSource")
    
    /// Source type
    var type: ImportSourceType = .file
    /// Display name of the device
    var displayName: String
    
    /// URL to search for images
    private(set) internal var url: URL
    /// Whether the directory is recursively searched
    private(set) internal var recursive: Bool
    
    // MARK: - Initialization
    init(_ url: URL, recursive: Bool = true) throws {
        self.displayName = url.lastPathComponent
        
        self.url = url
        self.recursive = recursive
        
        // validate the URL is a directory
        let urlInfo = try url.resourceValues(forKeys: [.isDirectoryKey])
        if !(urlInfo.isDirectory ?? false) {
            throw Errors.notADirectory
        }
        
        let _ = try FileManager.default.contentsOfDirectory(at: url,
                                                            includingPropertiesForKeys: nil,
                                                            options: [.skipsSubdirectoryDescendants])
    }
    
    // MARK: - Enumeration
    /**
     * Enumerates the contents of the directory to find all images.
     */
    func getImages() throws -> [ImportSourceItem] {
        let fm = FileManager.default
        
        // set up the enumerator (TODO: respect recursive flag)
        guard let e = fm.enumerator(at: self.url,
                                    includingPropertiesForKeys: [.isDirectoryKey, .typeIdentifierKey],
                                    options: [.skipsHiddenFiles]) else {
            throw Errors.failedToEnumerateDirectory
        }
        
        // iterate over each of the files to create an item
        var items: [ImportSourceItem] = []
        
        for case let fileURL as URL in e {
            Self.logger.trace("url: \(fileURL)")
            
            // create the item
            if let item = try Item(fileURL) {
                items.append(item)
            }
        }
        
        return items
    }
    
    // MARK: - Item class
    private class Item: ImportSourceItem {
        var type: UTType?
        var displayName: String
        var creationDate: Date?
        var modificationDate: Date?
        
        /// URL at which this item resides
        var url: URL
        
        /**
         * Creates a new item from a camera item.
         */
        init?(_ url: URL) throws {
            self.url = url
            
            let resVals = try url.resourceValues(forKeys: [.isDirectoryKey, .typeIdentifierKey])
            
            // ignore directories
            if resVals.isDirectory! {
                return nil
            }
            // ignore non-image files
            guard let typeString = resVals.typeIdentifier, let type = UTType(typeString),
                  type.conforms(to: UTType.image) else {
                return nil
            }
            self.type = type
            
            // get the remaining properties
            let info = try url.resourceValues(forKeys: [.localizedNameKey,
                                                        .contentModificationDateKey, .creationDateKey])
            
            self.displayName = info.localizedName!
            
            self.creationDate = info.creationDate
            self.modificationDate = info.contentModificationDate
        }
        
        /**
         * Requests a thumbnail for the given image.
         */
        func getThumbnail(_ callback: @escaping (Result<NSImage, Error>) -> Void) {
            // TODO: implement
        }
    }
    
    enum Errors: Error {
        /// The input URL is not a directory
        case notADirectory
        /// Could not enumerate the directory
        case failedToEnumerateDirectory
    }
}
