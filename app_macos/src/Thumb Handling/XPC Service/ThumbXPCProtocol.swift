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

/**
 * Represents a thumbnail request (either to generate or retrieve)
 */
@objc(ThumbRequest_XPC) public class ThumbRequest: NSObject, NSSecureCoding {
    /// Identifier of the library this image is associated with
    public var libraryId: UUID
    /// Identifier of the image
    public var imageId: UUID
    /// URL of the image on disk
    public var imageUrl: URL
    /// Image orientation
    public var orientation: Image.ImageOrientation

    /// Size of the thumbnail that's desired
    public var size: CGSize? = nil

    // MARK: Initialization
    /**
     * Creates an unpopulated thumb request.
     */
    public init?(libraryId: UUID, image: Image) {
        self.libraryId = libraryId

        guard let imageId = image.identifier else {
            return nil
        }
        self.imageId = imageId

        guard let url = image.url else {
            return nil
        }
        self.imageUrl = url

        self.orientation = image.orientation
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
        coder.encode(self.imageUrl, forKey: "imageUrl")
        coder.encode(Int(self.orientation.rawValue), forKey: "orientation")

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
        guard let libraryId = coder.decodeObject(forKey: "libraryId") as? UUID else {
            return nil
        }
        self.libraryId = libraryId

        guard let imageId = coder.decodeObject(forKey: "imageId") as? UUID else {
            return nil
        }
        self.imageId = imageId

        guard let url = coder.decodeObject(forKey: "imageUrl") as? URL else {
            return nil
        }
        self.imageUrl = url

        let rawOrientation = Int16(coder.decodeInteger(forKey: "orientation"))
        guard let orientation = Image.ImageOrientation(rawValue: rawOrientation) else {
            return nil
        }
        self.orientation = orientation

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
     * provided by the caller. It's then provided as an IOSurface object.
     */
    func get(_ request: ThumbRequest, withReply reply: @escaping (ThumbRequest, IOSurface?, Error?) -> Void)
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
            ThumbRequest.self, NSDictionary.self, NSArray.self,
            NSUUID.self, NSURL.self, NSString.self, NSNumber.self,
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

        return int
    }

    /// Don't allow initialization of the class, it's just a bunch of static methods
    private init() {}
}
