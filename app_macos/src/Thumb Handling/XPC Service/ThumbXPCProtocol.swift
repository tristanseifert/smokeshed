//
//  ThumbXPCService.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200610.
//

import Foundation
import CoreGraphics
import Cocoa

import Smokeshop
import CocoaLumberjackSwift

/**
 * Represents a thumbnail request (either to generate or retrieve)
 */
@objc(ThumbRequest_XPC) public class ThumbRequest: NSObject, NSSecureCoding {
    public override var description: String {
        return String(format: "<ThumbRequest: lib %@ img %@ (url %@) size %@>",
                      self.libraryId as CVarArg, self.imageId as CVarArg,
                      String(describing: self.imageUrl),
                      String(describing: self.size))
    }
    
    /// Identifier of the library this image is associated with
    private(set) public var libraryId: UUID
    /// Identifier of the image
    private(set) public var imageId: UUID
    /// URL of the image on disk
    private(set) public var imageUrl: URL!
    /// Image orientation
    private(set) public var orientation: Image.ImageOrientation = .unknown

    /// Url to which the bookmark is relative to
    private var imageUrlBase: URL? = nil
    /// Bookmark data for the image url
    private var imageUrlBookmark: Data?
    /// Bookmark data for the base url
    private var imageUrlBaseBookmark: Data?
    
    /// Size of the thumbnail that's desired
    public var size: CGSize? = nil

    // MARK: Initialization
    /**
     * Creates an unpopulated thumb request.
     */
    public init?(libraryId: UUID, libraryUrl: URL, image: Image, withDetails: Bool) {
        self.libraryId = libraryId

        guard let imageId = image.identifier else {
            return nil
        }
        self.imageId = imageId
        
        self.orientation = image.orientation

        // include url if requested
        if withDetails {
            self.imageUrlBase = libraryUrl
            
            // get the raw url
            guard let url = image.getUrl(relativeTo: self.imageUrlBase) else {
                return nil
            }
            self.imageUrl = url
            
            // create bookmark for library
            var relinquish = libraryUrl.startAccessingSecurityScopedResource()
            
            do {
                let bm = try libraryUrl.bookmarkData(options: [.minimalBookmark],
                                                     includingResourceValuesForKeys: nil,
                                                     relativeTo: nil)
                self.imageUrlBaseBookmark = bm
            } catch {
                DDLogError("Failed to create bookmark for library url \(libraryUrl): \(error)")
            }
            
            if relinquish {
                libraryUrl.stopAccessingSecurityScopedResource()
            }
            
            // create bookmark for the image url
            relinquish = url.startAccessingSecurityScopedResource()
            
            do {
                let bm = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                              includingResourceValuesForKeys: nil,
                                              relativeTo: self.imageUrlBase)
                self.imageUrlBookmark = bm
            } catch {
                DDLogError("Failed to create bookmark for \(url): \(error)")
            }
            
            if relinquish {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }

    // MARK: Encoding
    public static var supportsSecureCoding: Bool {
        return true
    }
    /**
     * Encodes the thumb request.
     */
    public func encode(with coder: NSCoder) {
        coder.encode(self.libraryId, forKey: "libraryId")
        coder.encode(self.imageId, forKey: "imageId")
        coder.encode(Int(self.orientation.rawValue), forKey: "orientation")
        
        if let bookmark = self.imageUrlBookmark {
            coder.encode(bookmark, forKey: "imageUrlBookmark")
            coder.encode(self.imageUrlBase, forKey: "imageUrlBase")
            
            if let data = self.imageUrlBaseBookmark {
                coder.encode(data, forKey: "imageUrlBaseBookmark")
            }
        } else if let url = self.imageUrl {
            coder.encode(url, forKey: "imageUrl")
        }

        if let size = self.size, size != .zero {
            coder.encode(true, forKey: "hasSize")
            coder.encode(size, forKey: "size")
        } else {
            coder.encode(false, forKey: "hasSize")
        }
    }
    /**
     * Decodes a thumb request.
     */
    public required init?(coder: NSCoder) {
        // attempt to decode the url by resolving the bookmark or just taking the raw url value
        if let bookmark = coder.decodeObject(forKey: "imageUrlBookmark") as? Data {
            do {
                // decode base url bookmark or read it
                var base: URL! = coder.decodeObject(forKey: "imageUrlBase") as? URL
                
                if let data = coder.decodeObject(forKey: "imageUrlBaseBookmark") as? Data {
                    // this is just a minimal bookmark
                    do {
                        var isStale: Bool = false
                        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI],
                                          relativeTo: nil, bookmarkDataIsStale: &isStale)
                        base = url
                    } catch {
                        DDLogError("Failed to decode base url bookmark data (\(data)): \(error)")
                        return nil
                    }
                }
                
                var isStale: Bool = false
                let url = try URL(resolvingBookmarkData: bookmark,
                                  options: [.withoutUI, .withSecurityScope],
                                  relativeTo: base, bookmarkDataIsStale: &isStale)
                self.imageUrl = url
            } catch {
                DDLogError("Failed to decode url bookmark data (\(bookmark)): \(error)")
                return nil
            }
        } else if let url = coder.decodeObject(forKey: "imageUrl") as? URL {
            self.imageUrl = url
        }
        
        // decode library id and image id
        guard let libraryId = coder.decodeObject(forKey: "libraryId") as? UUID else {
            return nil
        }
        self.libraryId = libraryId

        guard let imageId = coder.decodeObject(forKey: "imageId") as? UUID else {
            return nil
        }
        self.imageId = imageId

        // get image orientation
        let rawOrientation = Int16(coder.decodeInteger(forKey: "orientation"))
        guard let orientation = Image.ImageOrientation(rawValue: rawOrientation) else {
            return nil
        }
        self.orientation = orientation

        // lastly, size
        if coder.decodeBool(forKey: "hasSize") {
            self.size = coder.decodeSize(forKey: "size")
        }
    }
}

/**
 * Defines the interface implemented by the thumbnail XPC service.
 */
@objc protocol ThumbXPCProtocol {
    /**
     * Initializes the XPC service and load the thumbnail directory.
     */
    func wakeUp(handler: ThumbXPCHandler, withReply reply: @escaping (Error?) -> Void)
    
    /**
     * Opens a library.
     */
    func openLibrary(_ libraryId: UUID, withReply reply: @escaping (Error?) -> Void)
    
    /**
     * Saves any uncommitted thumbnail data to the thumb handler's persistent storage.
     */
    func save(withReply reply: @escaping (Error?) -> Void)
    
    /**
     * Requests the thumbnail handler generates a thumbnail for the given images.
     *
     * This is processed in the background in the thumb handler; the caller doesn't get any indication if the
     * request failed or succeeded.
     */
    func generate(_ requests: [ThumbRequest])
    
    /**
     * Discards thumbnail data for the images specified in these thumb requests.
     *
     * As with thumbnail generation, this request runs asynchronously in the background in the service.
     */
    func discard(_ requests: [ThumbRequest])
    
    /**
     * Prefetch data for the images identified by these requests.
     */
    func prefetch(_ requests: [ThumbRequest])
    
    /**
     * Retrieves a thumbnail for an image. The image is identified by its library id and some other properties
     * provided by the caller. It's then provided as an IOSurface object.
     */
    func get(_ request: ThumbRequest, withReply reply: @escaping (ThumbRequest, IOSurface?, Error?) -> Void)
    
    
    
    /**
     * Gets a reference to the maintenance endpoint.
     */
    func getMaintenanceEndpoint(withReply reply: @escaping (NSXPCListenerEndpoint) -> Void)
}

/**
 * Defines the interface exposed by the maintenance endpoint.
 */
@objc protocol ThumbXPCMaintenanceEndpoint {
    /**
     * Calculates the total disk space used to store thumbnail data.
     */
    func getSpaceUsed(withReply reply: @escaping (UInt, Error?) -> Void)
    
    /**
     * Retrieve the currently used path for thumbnail storage.
     */
    func getStorageDir(withReply reply: @escaping (URL) -> Void)
    
    /**
     * Moves thumbnail storage.
     */
    func moveThumbStorage(to: URL, copyExisting: Bool, deleteExisting: Bool, withReply reply: @escaping(Error?) -> Void)
    
    /**
     * Gets the current xpc service configuration.
     */
    func getConfig(withReply reply: @escaping([String: Any]) -> Void)
    
    /**
     * Sets the current xpc service configuration.
     */
    func setConfig(_ config: [String: Any])
}

/**
 * Interface of the app-side event handler for the thumb server.
 */
@objc protocol ThumbXPCHandler {
    /**
     * Thumbnail data for the given (libraryId, imageId) tuple was changed.
     */
    func thumbChanged(inLibrary library: UUID, _ imageId: UUID)
}

/**
 * String dictionary keys for the XPC service configuration
 */
public enum ThumbXPCConfigKey: String {
    /// Is the thumbnail processing queue dynamically sized?
    case workQueueSizeAuto = "thumbWorkQueueSizeAuto"
    /// If the thumb work queue is statically sized, number of threads to allocate
    case workQueueSize = "thumbWorkQueueSize"
    /// Should the chunk cache be sized automatically?
    case chunkCacheSizeAuto = "thumbChunkCacheSizeAuto"
    /// How big the in memory chunk cache is, in bytes
    case chunkCacheSize = "thumbChunkCacheSize"
    /// Where is thumbnail data stored?
    case storageUrl = "thumbStorageUrl"
}

/**
 * Some helper functions for working with the XPC protocol
 */
internal class ThumbXPCProtocolHelpers {
    /**
     * Creates a reference to the thumb XPC protocol, with all functions configured as needed.
     */
    class func make() -> NSXPCInterface {
        let int = NSXPCInterface(with: ThumbXPCProtocol.self)

        // set up the get() request
        let thumbReqClass = NSSet(array: [
            ThumbRequest.self, NSDictionary.self, NSArray.self, NSUUID.self, NSURL.self,
            NSString.self, NSNumber.self, NSData.self,
        ]) as! Set<AnyHashable>
        let imageClass = NSSet(array: [
            NSImage.self, IOSurface.self
        ]) as! Set<AnyHashable>

        int.setClasses(thumbReqClass,
                       for: #selector(ThumbXPCProtocol.get(_:withReply:)),
                       argumentIndex: 0, ofReply: false)

        int.setClasses(thumbReqClass,
                       for: #selector(ThumbXPCProtocol.get(_:withReply:)),
                       argumentIndex: 0, ofReply: true)
        int.setClasses(imageClass,
                       for: #selector(ThumbXPCProtocol.get(_:withReply:)),
                       argumentIndex: 1, ofReply: true)
        
        // generate, discard, prefetch
        int.setClasses(thumbReqClass,
                       for: #selector(ThumbXPCProtocol.generate(_:)),
                       argumentIndex: 0, ofReply: false)
        int.setClasses(thumbReqClass,
                       for: #selector(ThumbXPCProtocol.discard(_:)),
                       argumentIndex: 0, ofReply: false)
        int.setClasses(thumbReqClass,
                       for: #selector(ThumbXPCProtocol.prefetch(_:)),
                       argumentIndex: 0, ofReply: false)

        // handler interface
        int.setInterface(Self.makeHandler(),
                         for: #selector(ThumbXPCProtocol.wakeUp(handler:withReply:)),
                         argumentIndex: 0, ofReply: false)
        
        return int
    }
    
    /**
     * Creates an interface describing the maintenance endpoint protocol.
     */
    class func makeMaintenanceEndpoint() -> NSXPCInterface {
        let int = NSXPCInterface(with: ThumbXPCMaintenanceEndpoint.self)
        
        return int
    }
    
    /**
     * Creates an interface describing the maintenance endpoint protocol.
     */
    public class func makeHandler() -> NSXPCInterface {
        let int = NSXPCInterface(with: ThumbXPCHandler.self)
        
        return int
    }

    /// Don't allow initialization of the class, it's just a bunch of static methods
    private init() {}
}
