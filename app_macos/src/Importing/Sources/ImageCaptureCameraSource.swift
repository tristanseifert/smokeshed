//
//  ImageCaptureCameraSource.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200828.
//

import Foundation
import ImageCaptureCore
import UniformTypeIdentifiers
import OSLog

/**
 * Implements an image capture source that works with ImageCapture framework.
 */
internal class ImageCaptureCameraSource: ImportSource {
    fileprivate static var logger = Logger(subsystem: Bundle(for: ImageCaptureCameraSource.self).bundleIdentifier!,
                                         category: "ImageCaptureCameraSource")
    
    /// Source type
    var type: ImportSourceType = .camera
    /// Display name of the device
    var displayName: String
    
    /// Device which we read images from
    private(set) internal var device: ICCameraDevice!
    
    /// Secret file-based import source for memory cards
    private var secretSource: DirectoryImportSource? = nil
    
    // MARK: - Initialization
    /**
     * Creates a new import source from the given source.
     */
    init(_ device: ICCameraDevice) throws {
        self.device = device
        self.displayName = device.name ?? ""
    
        /*
         * For devices that use the mass storage transport (e.g. memory cards,) we create a file
         * import source that's actually used under the hood to enumerate the contents of its
         * mount point.
         */
        if let mountPoint = device.mountPoint {
            let url = URL(fileURLWithPath: mountPoint, isDirectory: true)
            self.secretSource = try DirectoryImportSource(url)
        }
    }
    
    // MARK: - Source items
    /**
     * Gets all images on the device.
     */
    func getImages() throws -> [ImportSourceItem] {
        // if using a file-based import source, prefer this
        if let source = self.secretSource {
            return try source.getImages()
        }
        
        // otherwise, enumerate the device's contents
        guard let items = self.device.mediaFiles else {
            Self.logger.warning("No items on device: \(String(describing: self.device))")
            return []
        }
        
        return items.compactMap {
            return Item($0)
        }
    }
    
    // MARK: - Item class
    private class Item: ImportSourceItem {
        var type: UTType?
        var displayName: String
        var creationDate: Date?
        var modificationDate: Date?
        
        /// Camera item handle for this image
        private var item: ICCameraItem!
        
        /**
         * Creates a new item from a camera item.
         */
        init?(_ item: ICCameraItem) {
            self.item = item
            
            // it must be an image item
            guard item.uti == kUTTypeImage as String else {
                return nil
            }
            
            // try to get the image type and other properties
            if let utiString = item.uti,
               let type = UTType(utiString) {
                self.type = type
            }
            
            self.creationDate = item.creationDate
            self.modificationDate = item.modificationDate
            self.displayName = item.name ?? ""
        }
        
        /**
         * Requests a thumbnail for the given image.
         */
        func getThumbnail(_ callback: @escaping (Result<NSImage, Error>) -> Void) {
            // TODO: implement
        }
    }
}
