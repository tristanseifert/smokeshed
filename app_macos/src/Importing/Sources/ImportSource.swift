//
//  ImportSource.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200828.
//

import Cocoa
import UniformTypeIdentifiers

/**
 * Defines the interface of a source of images to import.
 */
internal protocol ImportSource {
    /// What kind of storage is the import source backed by?
    var type: ImportSourceType { get }
    /// Display name
    var displayName: String { get }
    
    /**
     * Gets all images present on the import source, in no particular order.
     */
    func getImages() throws -> [ImportSourceItem]
    
    // TODO: add stuff :)
}

/**
 * A single item returned by an import source
 */
internal protocol ImportSourceItem {
    /// Item type
    var type: UTType? { get }
    /// Display name of the item
    var displayName: String { get }
    
    /// Item creation date
    var creationDate: Date? { get }
    /// Item modification date
    var modificationDate: Date? { get }
    
    /**
     * Requests a thumbnail image for the item
     */
    func getThumbnail(_ callback: @escaping (Result<NSImage, Error>) -> Void)
}

enum ImportSourceType {
    /// Connected camera (or SD card)
    case camera
    /// Directory/file containing images
    case file
}
