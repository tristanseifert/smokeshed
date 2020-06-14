//
//  ImportHandler.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200608.
//

import Foundation

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
                self.context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                self.context.parent = lib.store.mainContext
                self.context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
            }
        }
    }

    /// Background import queue
    private var queue: OperationQueue = OperationQueue()
    /// Object context for background operations
    private var context: NSManagedObjectContext! = nil

    /// Date formatter for converting EXIF date strings to date
    private var dateFormatter = DateFormatter()

    // MARK: - Initialization
    /**
     * Initializes a new import handler. All images will be associated with the given library, optionally being
     * copied into it.
     */
    public init() {
        // set up the queue. we allow some concurrency
        self.queue.name = "ImportHandler"
        self.queue.qualityOfService = .default
        self.queue.maxConcurrentOperationCount = 8

        // set up the EXIF date parser
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter.dateFormat = "yyyy':'MM':'dd HH':'mm':'ss"
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
            do {
                let flattened = try self.flattenUrls(urls)

                // if no URLs returned, complete job
                if flattened.isEmpty {
                    // TODO: implement
                    return
                }

                // prepare an import job for each URL
                flattened.forEach({ (url) in
                    self.queue.addOperation({
                        do {
                            _ = url.startAccessingSecurityScopedResource()
                            try self.importSingle(url, importDate: importDate)
                            url.stopAccessingSecurityScopedResource()
                        } catch {
                            // TODO: signal this error somehow
                            DDLogError("Failed to import '\(url)': \(error)")
                        }
                    })
                })
            } catch {
                // TODO: signal this error somehow
                DDLogError("Failed to flatten URLs: \(error)")
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
        let ids = images.map({$0.objectID})
        let urls = images.compactMap({$0.url})

        // create the "remove files" operation
        let removeFiles = BlockOperation(block: {
            let m = FileManager.default

            urls.forEach {
                _ = $0.startAccessingSecurityScopedResource()

                do {
                    try m.trashItem(at: $0, resultingItemURL: nil)
                } catch {
                    DDLogError("Failed to delete image '\($0)' from disk: \(error)")
                }

                $0.stopAccessingSecurityScopedResource()
            }

            if let handler = completion {
                return handler(.success(Void()))
            }
        })
        removeFiles.name = "RemoveFromDisk"

        // create the "remove from library" operation
        let removeFromLib = BlockOperation(block: {
            // set up batch delete request
            let delete = NSBatchDeleteRequest(objectIDs: ids)
            delete.resultType = .resultTypeObjectIDs

            self.context.performAndWait {
                do {
                    let result = try self.context.execute(delete) as! NSBatchDeleteResult
                    let idArray = result.result! as! [NSManagedObjectID]
                    let changes = [NSDeletedObjectsKey: idArray]

                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [self.context, self.context.parent!])

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
        var meta: [String: AnyObject]! = nil
        var insertRes: Result<Image, Error>? = nil

        // get some info about the file and ensure it's actually an image
        let resVals = try url.resourceValues(forKeys: [.typeIdentifierKey, .nameKey])

        guard let uti = resVals.typeIdentifier else {
            throw ImportError.unknownError(url)
        }

        guard UTTypeConformsTo(uti as CFString, kUTTypeImage) else {
            throw ImportError.notAnImage(url, uti)
        }

        // extract some metadata from the image
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: AnyObject] {
            meta = props
        } else {
            DDLogWarn("Failed to get metadata from '\(url)'")
            throw ImportError.failedToGetImageProperties(url)
        }

        let size = try self.sizeForMeta(meta)
        let orientation = try self.orientationForMeta(meta)
        let lens = try self.lensForMeta(meta)
        let captureDate = try self.captureDateForMeta(meta)

        // hop on the queue to create the object
        self.context.performAndWait {
            do {
                // ensure no image with this URL exists
                let req = NSFetchRequest<NSFetchRequestResult>(entityName: "Image")
                req.predicate = NSPredicate(format: "%K = %@", argumentArray: ["originalUrl", url])

                if try self.context.count(for: req) > 0 {
                    throw ImportError.duplicate(url)
                }

                // create the new image
                let image = Image(context: self.context)

                image.dateImported = importDate
                image.name = resVals.name
                image.originalMetadata = meta as NSDictionary?

                // save image url and a bookmark to it
                image.originalUrl = url
                try image.setUrlBookmark(url)

                // store other precomputed properties
                image.dateCaptured = captureDate
                image.imageSize = size
                image.rawOrientation = orientation.rawValue
                image.lens = lens

                // save the context
                try self.context.save()
                insertRes = .success(image)
            } catch {
                insertRes = .failure(error)
            }
        }

        // rethrow errors if we got any
        _ = try insertRes!.get()
    }

    /**
     * Gets the image size (in pixels) from the given metadata.
     */
    private func sizeForMeta(_ meta: [String: AnyObject]) throws -> CGSize {
        guard let width = meta[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let height = meta[kCGImagePropertyPixelHeight as String] as? NSNumber else {
            throw ImportError.failedToSizeImage
        }

        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    /**
     * Extracts the capture date of the iamge from the exif data.
     */
    private func captureDateForMeta(_ meta: [String: AnyObject]) throws -> Date? {
        if let exif = meta[kCGImagePropertyExifDictionary as String],
           let dateStr = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
           let date = self.dateFormatter.date(from: dateStr) {
            return date
        }

        // failed to get date :(
        return nil
    }

    /**
     * Extracts the orientation from the given image metadata.
     */
    private func orientationForMeta(_ meta: [String: AnyObject]) throws -> Image.ImageOrientation {
        if let orientation = meta[kCGImagePropertyOrientation as String] as? NSNumber {
            let val = CGImagePropertyOrientation(rawValue: orientation.uint32Value)

            switch val {
                case .down, .downMirrored:
                    return Image.ImageOrientation.cw180

                case .right, .rightMirrored:
                    return Image.ImageOrientation.cw90

                case .left, .leftMirrored:
                    return Image.ImageOrientation.ccw90

                case .up, .upMirrored:
                    return Image.ImageOrientation.normal

                // TODO: should this be a special value?
                case .none:
                    return Image.ImageOrientation.normal

                default:
                    DDLogError("Unknown image orientation: \(String(describing: val))")
                    return Image.ImageOrientation.unknown
            }
        }

        // failed to get orientation
        return Image.ImageOrientation.unknown
    }

    /**
     * Tries to find a lens that best matches what is laid out in the given metadata. If we could identify the
     * lens but none exists in the library, it's created.
     */
    private func lensForMeta(_ meta: [String: AnyObject]) throws -> Lens? {
        var fetchRes: Result<[Lens], Error>? = nil

        // read the model string and lens id
        guard let exif = meta[kCGImagePropertyExifDictionary as String],
            let model = exif[kCGImagePropertyExifLensModel] as? String else {
            DDLogWarn("Failed to get lens model from metadata: \(meta)")
            return nil
        }

        var lensId: Int? = nil
        if let aux = meta[kCGImagePropertyExifAuxDictionary as String],
            let id = aux[kCGImagePropertyExifAuxLensID] as? NSNumber {
            lensId = id.intValue
        }

        // try to find an existing lens matching BOTH criteria
        let req = NSFetchRequest<Lens>(entityName: "Lens")

        var predicates = [
            NSPredicate(format: "exifLensModel == %@", model)
        ]
        if let id = lensId {
            predicates.append(NSPredicate(format: "exifLensId == %i", id))
        }

        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

        self.context.performAndWait {
            do {
                let res = try self.context.fetch(req)
                fetchRes = .success(res)
            } catch {
                fetchRes = .failure(error)
            }
        }

        let results = try fetchRes!.get()
        if !results.isEmpty {
            return results.first
        }

        // we need to create a lens
        return try self.createLens(meta, model, lensId)
    }
    /**
     * Creates a lens object for the given metadata.
     * The context is not saved after creation; the assumption is that pretty much immediately after this call,
     * an image is imported, where we'll save the context anyhow.
     */
    private func createLens(_ meta: [String: AnyObject], _ model: String, _ id: Int?) throws -> Lens? {
        var res: Result<Lens, Error>? = nil

        // run a block to create it
        self.context.performAndWait {
            let lens = Lens(context: self.context)

            lens.exifLensModel = model
            lens.name = model

            lens.exifLensId = Int32(id ?? -1)

            res = .success(lens)
        }

        // return the lens or throw error
        return try res!.get()
    }

    // MARK: - Errors
    /**
     * Represents import errors.
     */
    enum ImportError: Error {
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
}
