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
                        self.importSingle(url)
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
     * Enumerates the contents of a directory, returning all files therein.
     */
    private func enumerateDirectory(_ directoryUrl: URL) throws -> [URL] {
        var outUrls = [URL]()

        // list the contents of the given directory
        guard let e = FileManager.default.enumerator(at: directoryUrl, includingPropertiesForKeys: nil) else {
                throw ImportError.failedToEnumerateDirectory(directoryUrl)
        }

        for case let fileURL as URL in e {
            outUrls.append(fileURL)
        }

        return outUrls
    }

    // MARK: - Importing
    /**
     * Adds the image file at the given URL to the library, by reference.
     *
     * If the exact image (matching by path) already exists in the library, this step aborts.
     */
    private func importSingle(_ url: URL) {
        DDLogVerbose("Importing image: \(url)")
    }

    // MARK: - Errors
    /**
     * Represents import errors.
     */
    enum ImportError: Error {
        /// Failed to get a directory enumerator.
        case failedToEnumerateDirectory(_ directoryUrl: URL)
    }
}
