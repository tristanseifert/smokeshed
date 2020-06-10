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
    private var library: LibraryBundle

    /// Background import queue
    private var queue: OperationQueue = OperationQueue()
    /// Object context for background operations
    private var context: NSManagedObjectContext! = nil

    /// Date formatter for converting EXIF date strings to date
    private var dateFormatter: DateFormatter

    // MARK: - Initialization
    /**
     * Initializes a new import handler. All images will be associated with the given library, optionally being
     * copied into it.
     */
    public init(_ library: LibraryBundle) {
        self.library = library

        // set up the queue. we allow some concurrency
        self.queue.name = "ImportHandler"
        self.queue.qualityOfService = .default
        self.queue.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount

        // create the background queue
        self.context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        self.context.parent = self.library.store.mainContext

        // set up the EXIF date parser
        self.dateFormatter = DateFormatter()
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter.dateFormat = "yyyy':'MM':'dd HH':'mm':'ss"
    }

    /**
     * Cancel all outstanding operations when deallocating.
     */
    deinit {
        self.queue.cancelAllOperations()
    }

    // MARK: - Public interface
    /**
     * Imports all suitable image files at the provided URLs. These URLs may be of directories, in which case
     * we enumerate their contents for image files (and further subdirectories,) but also point directly to an
     * image.
     */
    public func importFrom(_ urls: [URL]) {
        DDLogDebug("Importing from: \(urls)")

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
                            try self.importSingle(url)
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
    private func importSingle(_ url: URL) throws {
        var meta: [String: AnyObject]! = nil

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

        guard let width = meta[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let height = meta[kCGImagePropertyPixelWidth
                as String] as? NSNumber else {
            throw ImportError.failedToSizeImage(url)
        }
        let size = CGSize(width: width.doubleValue, height: height.doubleValue)

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

                image.dateImported = Date()
                image.name = resVals.name
                image.originalMetadata = meta as NSDictionary?
                image.originalUrl = url
                image.imageSize = NSValue(size: size)

                // get capture date from exif if avaialble (TODO: parse subseconds)
                if let m = meta,
                   let exif = m[kCGImagePropertyExifDictionary as String],
                   let dateStr = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
                   let date = self.dateFormatter.date(from: dateStr) {
                    image.dateCaptured = date
                }

                // save the context
                try self.context.save()
            } catch {
                DDLogError("Failed to create image: \(error)")
            }
        }
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
        case failedToSizeImage(_ imageUrl: URL)
    }
}
