//
//  ImportHandler.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200608.
//

import Foundation
import UniformTypeIdentifiers

import CocoaLumberjackSwift

/**
 * Handles importing images to the library.
 *
 * Importing happens on a dedicated background queue maintained by this handler. Once a list of URLs has
 * been provided, we enumerate the contents of the directory, and attempt to import each file found.
 */
public class ImportHandler {
    /// Library into which images are to be imported
    public var library: LibraryBundle? {
        didSet {
            // destroy old context
            if self.context != nil {
                self.context = nil
            }

            if let lib = self.library {
                // create the background queue
                let ctx = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                ctx.parent = lib.store.mainContext
                
                // effectively ignore conflicts
                ctx.mergePolicy = NSMergePolicy.rollback
                ctx.automaticallyMergesChangesFromParent = true
                
                self.context = ctx
            }
        }
    }

    /// Background import queue
    private var queue: OperationQueue = OperationQueue()
    /// Object context for background operations
    private var context: NSManagedObjectContext! = nil {
        didSet {
            self.lensFinder.context = self.context
            self.cameraFinder.context = self.context
        }
    }
    
    /// Number of images after which to save the context
    private var importBlockSize: UInt = 12

    /// General metadata helpers
    private var metaHelper = MetaHelper()
    /// Lens matching
    private var lensFinder = LensFinder()
    /// Camera matching
    private var cameraFinder = CameraFinder()

    // MARK: - Initialization
    /**
     * Initializes a new import handler. All images will be associated with the given library, optionally being
     * copied into it.
     */
    public init() {
        // set up the queue. we allow some concurrency
        self.queue.name = "ImportHandler"
        self.queue.qualityOfService = .utility
        self.queue.maxConcurrentOperationCount = 8
    }

    /**
     * Cancel all outstanding operations when deallocating.
     */
    deinit {
        self.queue.cancelAllOperations()
    }

    /**
     * Maximum amount of concurrent operations. This shouldn't need to be accessed, really.
     */
    public var concurrency: Int {
        get {
            return self.queue.maxConcurrentOperationCount
        }
        set(newValue) {
            self.queue.maxConcurrentOperationCount = newValue
        }
    }

    // MARK: - Public Interface
    /**
     * Imports all suitable image files at the provided URLs. These URLs may be of directories, in which case
     * we enumerate their contents for image files (and further subdirectories,) but also point directly to an
     * image.
     */
    public func importFrom(_ urls: [URL]) {
        let importDate = Date()

        // perform flattening on background queue
        let op = BlockOperation(block: {
            urls.forEach({
                _ = $0.startAccessingSecurityScopedResource()
            })
            DDLogDebug("Import input urls: \(urls)")
            
            do {
                let flattened = try self.flattenUrls(urls)
                DDLogDebug("Flattened to \(flattened.count) URLs")
                
                // if no URLs returned, complete job
                if flattened.isEmpty {
                    // TODO: implement
                    return
                }

                // prepare an import job for each URL
                for (i, url) in flattened.enumerated() {
                    self.queue.addOperation({
                        let relinquish = url.startAccessingSecurityScopedResource()
                        
                        do {
                            try self.importSingle(url, importDate: importDate)
                        } catch {
                            // TODO: signal this error somehow
                            DDLogError("Failed to import '\(url)': \(error)")
                        }
                        
                        if relinquish {
                            url.stopAccessingSecurityScopedResource()
                        }
                    })
                    
                    // every N images, add a barrier block to save the context
                    if UInt(i) % self.importBlockSize == 0 {
                        self.queue.addBarrierBlock {
                            do {
                                try self.context.save()
                            } catch {
                                DDLogError("Failed to save context after import: \(error)")
                            }
                        }
                    }
                }
            } catch {
                // TODO: signal this error somehow
                DDLogError("Failed to flatten URLs: \(error)")
            }
            
            // after all imports complete, save context
            self.queue.addBarrierBlock {
                do {
                    try self.context.save()
                } catch {
                    DDLogError("Failed to save context after import: \(error)")
                }
                
                // relinquish access to the URLs
                urls.forEach({
                    $0.stopAccessingSecurityScopedResource()
                })
            }
        })
        op.name = "FlattenURLs"

        self.queue.addOperation(op)
    }

    /**
     * Deletes the given images from the library. The files on disk can be deleted as well.
     */
    public func deleteImages(_ images: [Image], shouldDelete: Bool = false, _ completion: ((Result<Void, Error>) -> Void)? = nil) {
        // get IDs and URLs on calling thread
        let imageIdentifiers = images.compactMap({$0.identifier})
        let objectIds = images.map({$0.objectID})
        let urls = images.compactMap({$0.getUrl(relativeTo: self.library?.url)})

        // create the "remove files" operation
        let removeFiles = BlockOperation(block: {
            let m = FileManager.default

            urls.forEach {
                let relinquish = $0.startAccessingSecurityScopedResource()

                do {
                    try m.trashItem(at: $0, resultingItemURL: nil)
                } catch {
                    DDLogError("Failed to delete image '\($0)' from disk: \(error)")
                }

                if relinquish {
                    $0.stopAccessingSecurityScopedResource()
                }
            }

            if let handler = completion {
                return handler(.success(Void()))
            }
        })
        removeFiles.name = "RemoveFromDisk"

        // create the "remove from library" operation
        let removeFromLib = BlockOperation(block: {
            // set up batch delete request
            let delete = NSBatchDeleteRequest(objectIDs: objectIds)
            delete.resultType = .resultTypeObjectIDs

            self.context.performAndWait {
                do {
                    let result = try self.context.execute(delete) as! NSBatchDeleteResult
                    let idArray = result.result! as! [NSManagedObjectID]
                    let changes = [NSDeletedObjectsKey: idArray]

                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes,
                                                        into: [self.context.parent!, self.context])

                    // send notification
                    let center = NotificationCenter.default
                    center.post(name: Self.imagesDeletedNotification,
                                object: self.library, userInfo: [
                        "identifiers": imageIdentifiers,
                        "objectIds": objectIds,
                    ])
                    
                    // if this succeeded, run the file deletion
                    if shouldDelete {
                        self.queue.addOperation(removeFiles)
                    }
                    // if no deletion requested, run callback
                    else {
                        if let handler = completion {
                            return handler(.success(Void()))
                        }
                    }
                } catch {
                    DDLogError("Failed to remove images from library: \(error)")
                    removeFiles.cancel()

                    if let handler = completion {
                        return handler(.failure(error))
                    }
                }
            }
        })
        removeFromLib.name = "RemoveFromLibrary"

        removeFiles.addDependency(removeFromLib)

        // start the operation
        self.queue.addOperation(removeFromLib)
    }

    // MARK: - Enumeration
    /**
     * Flattens the provided array of URLs by enumerating the contents of any directories found.
     */
    private func flattenUrls(_ urls: [URL]) throws -> [URL] {
        var outUrls = [URL]()

        try urls.forEach({ (url) in
            // check whether that URL is a directory
            var isDirectory: ObjCBool = ObjCBool(false)

            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                // if directory, expand its contents
                if isDirectory.boolValue {
                    let children = try self.enumerateDirectory(url)
                    outUrls.append(contentsOf: children)
                }
                // otherwise, add it to the array as normal
                else {
                    outUrls.append(url)
                }
            }
            // file didn't exist… shouldn't have been passed in
            else {
                DDLogError("Skipping import of nonexistent URL '\(url)'")
            }
        })

        return outUrls
    }

    /**
     * Enumerates the contents of a directory, returning all files therein. Note that hidden files are ignored by
     * this function.
     */
    private func enumerateDirectory(_ directoryUrl: URL) throws -> [URL] {
        var outUrls = [URL]()

        // list the contents of the given directory
        guard let e = FileManager.default.enumerator(at: directoryUrl, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            throw ImportError.failedToEnumerateDirectory(directoryUrl)
        }

        for case let fileURL as URL in e {
            let resVals = try fileURL.resourceValues(forKeys: [.isDirectoryKey])

            // add only non-directory URLs
            if resVals.isDirectory == false {
                outUrls.append(fileURL)
            }
        }

        return outUrls
    }

    // MARK: - Importing
    /**
     * Adds the image file at the given URL to the library, by reference.
     *
     * If the exact image (matching by path) already exists in the library, this step aborts.
     */
    private func importSingle(_ url: URL, importDate: Date) throws {
        var insertRes: Result<NSManagedObjectID, Error>? = nil

        // get some info about the file and ensure it's actually an image
        let resVals = try url.resourceValues(forKeys: [.typeIdentifierKey, .nameKey])

        guard let uti = resVals.typeIdentifier, let type = UTType(uti) else {
            throw ImportError.unknownError(url)
        }

        guard type.conforms(to: UTType.image) else {
            throw ImportError.notAnImage(url, uti)
        }

        // extract some metadata from the image
        let meta = try self.metaHelper.getMeta(url, type)

        guard let size = meta.size else {
            throw ImportError.failedToSizeImage
        }
        
        let orientation = try self.metaHelper.orientation(meta)
        let lens = try self.lensFinder.find(meta)
        let cam = try self.cameraFinder.find(meta)
        let captureDate = meta.captureDate

        // hop on the queue to create the object
        self.context.performAndWait {
            do {
                // ensure no image with this URL exists
                let req: NSFetchRequest<Image> = Image.fetchRequest()
                req.predicate = NSPredicate(format: "%K = %@", argumentArray: ["originalUrl", url])

                if try self.context.count(for: req) > 0 {
                    throw ImportError.duplicate(url)
                }

                // create the new image
                let image = Image(context: self.context)

                image.dateImported = importDate
                image.name = resVals.name
                image.metadata = meta

                // save image url and a bookmark to it
                try image.setUrlBookmark(url, relativeTo: self.library!.url)
                image.originalUrl = url

                // store other precomputed properties
                image.dateCaptured = captureDate
                image.dayCaptured = captureDate?.withoutTime()
                image.imageSize = size
                image.rawOrientation = orientation.rawValue
                image.lens = lens
                image.camera = cam
                
                // obtain permanent ids for the image
                try self.context.obtainPermanentIDs(for: [image])
//                try self.context.save()
                
                insertRes = .success(image.objectID)
            } catch {
                insertRes = .failure(error)
            }
        }

        // rethrow errors if we got any
        _ = try insertRes!.get()
    }

    // MARK: - Errors
    /**
     * Represents import errors.
     */
    public enum ImportError: Error {
        /// An unknown error took place while processing the given URL.
        case unknownError(_ url: URL)
        /// Failed to get a directory enumerator.
        case failedToEnumerateDirectory(_ directoryUrl: URL)
        /// The specified file is not an image file type.
        case notAnImage(_ fileUrl: URL, _ uti: String!)
        /// This image is a duplicate of an image already in the library.
        case duplicate(_ imageUrl: URL)
        /// Something went wrong getting information about an image.
        case failedToGetImageProperties(_ imageUrl: URL)
        /// Failed to size the image.
        case failedToSizeImage
    }
    
    // MARK: - Notifications
    /**
     * Posted after images have been deleted from the library.
     *
     * The `userInfo` dictionary contains two keys: `identifiers` containing image identifiers
     * (UUIDs) and `objectIds` containing an array of `NSManagedObjectID`s for each deleted
     * image. You should not rely on the order of both arrays being the same.
     *
     * The object of the notification is the library to which the notification pertains.
     */
    public static let imagesDeletedNotification = Notification.Name("me.tseifert.smokeshed.imagesDeletedNotification")
}
