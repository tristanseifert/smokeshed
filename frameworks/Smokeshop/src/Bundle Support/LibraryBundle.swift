//
//  LibraryBundle.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200606.
//

import Foundation

import CocoaLumberjackSwift

/**
 * Represents a library bundle on disk, and provides easy access to all of its contents.
 */
public class LibraryBundle {
    /// URL on disk of the bundle. May or may not exist
    private var url: URL! = nil
    /// File wrapper around the library bundle
    private var wrapper: FileWrapper! = nil

    /// URL to the data store
    private var storeUrl: URL! = nil

    /// Library metdata
    private var meta: LibraryMeta = LibraryMeta()

    // MARK: - Initialization
    /**
     * Initializes a library bundle with the given URL. If the URL exists, that library is loaded; otherwise, a
     * new library at that path is created.
     *
     * If an error takes place during loading (invalid format, inaccessible) or creating (saving of data) an
     * exception is raised.
     */
    public init(_ url: URL) throws {
        self.url = url
        
        let b = Bundle(for: LibraryBundle.self)

        // create the bare bundle if not existent already
        if !FileManager.default.fileExists(atPath: url.path) {
            try self.createStructure()
        }

        // attempt to read the bundle and ensure it's a directory
        self.wrapper = try FileWrapper(url: url)

        guard wrapper.isDirectory else {
            let msg = NSLocalizedString("Not a directory", tableName: nil,
                        bundle: b, value: "",
                        comment: "library directory check failed")
            throw LibraryBundleError.invalidFormat(message: msg)
        }

        // load metadata and validate store
        try self.loadMetadata()

        self.storeUrl = self.url.appendingPathComponent(self.meta.storePath,
                                                        isDirectory: false)
    }

    /**
     * Creates the basic structure of the library:
     *
     * - Contents: directory holding all data
     *  ↳ Metadata.plist: Basic information about the library
     *  ↳ Store.sqlite: CoreData store
     */
    private func createStructure() throws {
        // create metadata and encode it
        self.createMetadata()

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode(self.meta)

        let metaWrapper = FileWrapper(regularFileWithContents: data)

        // contents directory
        let contents = FileWrapper(directoryWithFileWrappers: [
            "Metadata.plist": metaWrapper
        ])

        // create the main wrapper and write it
        let bundle = FileWrapper(directoryWithFileWrappers: [
            "Contents": contents
        ])

        try bundle.write(to: self.url, originalContentsURL: nil)
    }

    // MARK: - Disk IO
    /**
     * Forces the bundle to be written out to disk.
     */
    public func write() throws {
        try self.wrapper.write(to: self.url, originalContentsURL: nil)
    }

    /**
     * Gets a reference to a file wrapper with the given name inside of the contents directory.
     */
    private func getWrapper(_ name: String) -> FileWrapper! {
        // first, get the contents wrapper
        guard let contents = self.wrapper.fileWrappers?["Contents"] else {
            DDLogError("Failed to get Contents wrapper from \(self.wrapper!)")
            return nil
        }

        // then, query it for the given wrapper
        for entry in contents.fileWrappers! {
            if entry.value.filename == name {
                return entry.value
            }
        }

        // failed to find file
        return nil
    }

    // MARK: - Metadata Handling
    /**
     * Fills the metadata dictionary with initial metadata.
     */
    private func createMetadata() {
        // version and compatibility info
        self.meta.version = 1
        self.meta.storePath = "Store.sqlite"

        // what app version created this
        if let appInfo = Bundle.main.infoDictionary {
            self.meta.creatorAppId = appInfo[kCFBundleIdentifierKey as String] as? String
            self.meta.creatorAppVers = appInfo[kCFBundleVersionKey as String] as? String
        }

        // who and when created this library
        self.meta.createdOn = Date()
        self.meta.creatorName = NSFullUserName()

        // what system version created this
        let sysVers = ProcessInfo.processInfo.operatingSystemVersionString
        self.meta.creatorOSVers = sysVers
    }

    /**
     * Decodes metadata from the library.
     */
    private func loadMetadata() throws {
        let b = Bundle(for: LibraryBundle.self)

        // find the Metadata.plist file and read its contents
        guard let metaWrapper = self.getWrapper("Metadata.plist") else {
            let msg = NSLocalizedString("Failed to get metadata file",
                        tableName: nil, bundle: b, value: "",
                        comment: "library failed to get Metadata.plist wrapper")
            throw LibraryBundleError.invalidFormat(message: msg)
        }

        guard let data = metaWrapper.regularFileContents else {
            let msg = NSLocalizedString("Failed to read metadata file",
                                        tableName: nil, bundle: b, value: "",
                                        comment: "library failed to read Metadata.plist data")
            throw LibraryBundleError.ioError(message: msg)
        }

        // then, decode it
        let plist = PropertyListDecoder()
        let meta = try plist.decode(LibraryMeta.self, from: data)

        self.meta = meta
        DDLogDebug("Loaded metadata for library \(self.url!): \(self.meta)")
    }

    /**
     * Gets metadata for the bundle.
     */
    public func getMetadata() -> LibraryMeta {
        return self.meta
    }
}
