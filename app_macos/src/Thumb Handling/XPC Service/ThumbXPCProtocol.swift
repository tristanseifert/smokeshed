//
//  ThumbXPCService.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200610.
//

import Foundation
import Cocoa

/**
 * Represents a thumbnail request (either to generate or retrieve)
 */
@objc(ThumbRequest_XPC) public class ThumbRequest: NSObject, NSSecureCoding {
    /// Identifier of the library this image is associated with
    public var libraryId: UUID
    /**
     * Information about the image for which the thumbnail is to be generated. This dictionary should have
     * at least the `identifier` and `originalUrl` keys.
     */
    public var imageInfo = [String: Any]()

    /// Size of the thumbnail that's desired
    public var size: CGSize? = nil

    // MARK: Initialization
    /**
     * Creates an unpopulated thumb request.
     */
    public init(libraryId: UUID) {
        self.libraryId = libraryId
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
        coder.encode(self.imageInfo, forKey: "info")

        if let size = self.size {
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
        guard let id = coder.decodeObject(forKey: "libraryId") as? UUID else {
            return nil
        }
        self.libraryId = id

        guard let info = coder.decodeObject(forKey: "info") as? [String: Any] else {
            return nil
        }
        self.imageInfo = info

        if coder.decodeBool(forKey: "hasSize") {
            self.size = coder.decodeSize(forKey: "size")
        }
    }
}

/**
 * Defines the interface implemented by the thumbnail XPC service.
 */
@objc public protocol ThumbXPCProtocol {
    /**
     * Initializes the XPC service and load the thumbnail directory.
     */
    func wakeUp(withReply reply: @escaping (Error?) -> Void)

    /**
     * Retrieves a thumbnail for an image. The image is identified by its library id and some other properties
     * provided by the caller.
     */
    func get(_ request: ThumbRequest, withReply reply: @escaping (ThumbRequest, NSImage?, Error?) -> Void)
}

/**
 * Some helper functions for working with the XPC protocol
 */
class ThumbXPCProtocolHelpers {
    /**
     * Creates a reference to the thumb XPC protocol, with all functions configured as needed.
     */
    public class func make() -> NSXPCInterface {
        let int = NSXPCInterface(with: ThumbXPCProtocol.self)

        // set up the get() request
        let thumbReqClass = NSSet(array: [
            ThumbRequest.self, NSUUID.self, NSDictionary.self, CGSize.self,
            NSURL.self, NSString.self, NSNumber.self, NSValue.self, NSArray.self
        ]) as! Set<AnyHashable>
        let imageClass = NSSet(object: NSImage.self) as! Set<AnyHashable>

        int.setClasses(thumbReqClass,
                       for: #selector(ThumbXPCProtocol.get(_:withReply:)),
                       argumentIndex: 0, ofReply: false)

        int.setClasses(thumbReqClass,
                       for: #selector(ThumbXPCProtocol.get(_:withReply:)),
                       argumentIndex: 0, ofReply: true)
        int.setClasses(imageClass,
                       for: #selector(ThumbXPCProtocol.get(_:withReply:)),
                       argumentIndex: 1, ofReply: true)

        return int
    }

    /// Don't allow initialization of the class, it's just a bunch of static methods
    private init() {}
}
