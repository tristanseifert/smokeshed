//
//  ThumbHandler.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200610.
//

import Foundation

import Smokeshop
import CocoaLumberjackSwift

/**
 * Provides a shared endpoint to the thumbnail generation service.
 *
 * Thumbnails are uniquely identified by a pair of library id, image id. The thumb generator keeps its own
 * database of generated thumbnails, and stores thumbnails in a standard cache location.
 *
 * A stack of sorts is provided for the library id. This is shared across all callers (and threads!) into the shared
 * instance, so it's of limited use inside most code. It's more intended to allow the library handling code to
 * automatically set the id of the library so the shorter generation methods that do not require a library id to be
 * specified can be used.
 *
 * You can choose to generate thumbnails ahead of time (for example, for prefetching) but they will also be
 * created if they do not exist at retrieval time.
 */
class ThumbHandler {
    /// Shared thumb handler instance
    public static var shared = ThumbHandler()

    /**
     * Thumbnail retrieval callback type. The first argument is the image's identifier, followed by the
     * generated thumbnail image or an error.
     */
    typealias GetCallback = (UUID, Result<NSImage, Error>) -> Void

    /// XPC connection to the thumbnail helper
    private var xpc: NSXPCConnection! = nil
    /// Remote thumbnail service
    private var service: ThumbXPCProtocol! = nil

    // MARK: - Initialization
    /**
     * Creates a new thumb handler instance. This establishes a connection to the thumb generator XPC
     * service and tells it about our state.
     */
    private init() {
        self.establishXpcConnection()
    }

    /**
     * Establishes an XPC connection to the thumb handler.
     */
    private func establishXpcConnection() {
        // create the XPC connection
        self.xpc = NSXPCConnection(serviceName: "me.tseifert.smokeshed.xpc.hand")

        self.xpc.remoteObjectInterface = ThumbXPCProtocolHelpers.make()
        self.xpc.resume()

        DDLogVerbose("Thumb handler XPC connection: \(String(describing: self.xpc))")

        // then, get the service object
        self.service = self.xpc.remoteObjectProxyWithErrorHandler { error in
            DDLogError("Failed to get remote object proxy: \(error)")

            if let xpc = self.xpc {
                xpc.invalidate()
                self.xpc = nil
            }
        } as? ThumbXPCProtocol

        DDLogVerbose("Thumb service: \(String(describing: self.service))")

        // once connection is initialized, the XPC service itself must init
        self.wakeXpcService()
    }

    /**
     * Tells the XPC service to initialize itself.
     */
    private func wakeXpcService() {
        self.service!.wakeUp(withReply: { error in
            // handle errors… not much we can do but invalidate connection
            guard error == nil else {
                DDLogError("Failed to wake thumb service: \(error!)")

                self.service = nil

                self.xpc.invalidate()
                self.xpc = nil
                return
            }

            // cool, we're ready for service™
            DDLogVerbose("Thumb handler has woken up")
        })
    }

    // MARK: - Library stack
    /// Stack of library ids used by default
    private var libraryIdStack: [UUID] = []

    /**
     * Pushes a library id onto the stack.
     */
    public func pushLibraryId(_ id: UUID) {
        self.libraryIdStack.append(id)
    }

    /**
     * Pops a library id from the stack. If no id is set, an error is thrown.
     */
    @discardableResult public func popLibraryId() -> UUID {
        if self.libraryIdStack.isEmpty {
            fatalError("Attempted to pop from empty library id stack")
        }

        return self.libraryIdStack.removeLast()
    }

    // MARK: Helpers
    /**
     * Converts a managed object Image structure to a dictionary.
     */
    private func imageToDict(_ image: Image) -> [String: Any] {
        return [
            "mocId": image.objectID.uriRepresentation(),
            "identifier": image.identifier!,
            "originalUrl": image.originalUrl!
        ]
    }

    // MARK: - External API
    // MARK: Generation
    /**
     * Generates a thumbnail for the given image instance.
     */
    public func generate(_ image: Image) {
        self.generate([image])
    }
    /**
     * Generates a thumbnail for the given image instance, tagged with the provided library id.
     */
    public func generate(_ images: [Image]) {
        if self.libraryIdStack.isEmpty {
            fatalError("No library id has been set; use the long form of generate() or call pushLibraryId()")
        }

        self.generate(self.libraryIdStack.last!, images.map(self.imageToDict))
    }

    /**
     * Generates thumbnails for each of the dictionaries of image properties. At a minimum, the
     * `identifier` and `originalUrl` fields must exist. The thumbnails are tagged with the
     * provided library id.
     */
    public func generate(_ libraryId: UUID, _ props: [[String: Any]]) {
//        DDLogDebug("Thumb req: libId=\(libraryId), info=\(props)")
    }

    // MARK: Retrieval
    /**
     * Gets the "best fit" thumbnail image for the specified size.
     */
    public func get(_ image: Image, _ size: CGSize, _ handler: @escaping GetCallback) {
        if self.libraryIdStack.isEmpty {
            fatalError("No library id has been set; use the long form of generate() or call pushLibraryId()")
        }

        self.get(self.libraryIdStack.last!, self.imageToDict(image), size, handler)
    }

    /**
     * Gets the "best fit" thumbnail image for the specified size. The image is identified by a parameter
     * dictionary and library id.
     */
    public func get(_ libraryId: UUID, _ props: [String: Any], _ size: CGSize, _ handler: @escaping GetCallback) {
        // prepare a request
        let req = ThumbRequest(libraryId: libraryId)

        req.imageInfo = props
        req.size = size

        self.service!.get(req, withReply: { req, inImg, inErr in
            // handle the error case first
            if let error = inErr {
                handler(props["identifier"] as! UUID, .failure(error))
            }
            // otherwise, handle success case
            else if let image = inImg {
                handler(props["identifier"] as! UUID, .success(image))
            }
            // something got seriously fucked
            else {
                handler(props["identifier"] as! UUID, .failure(ThumbError.unknownError))
            }
        })
    }

    // MARK: Cancelation
    /**
     * Cancels all thumbnail operations for the given image.
     */
    public func cancel(_ image: Image) {
        self.cancel([image])
    }

    /**
     * Cancels thumbnail operations for all of the provided images.
     */
    public func cancel(_ images: [Image]) {
        if self.libraryIdStack.isEmpty {
            fatalError("No library id has been set; use the long form of generate() or call pushLibraryId()")
        }

        self.cancel(self.libraryIdStack.last!, images.map({ (image) in
            return image.identifier!
        }))
    }

    /**
     * Cancels all thumbnail operations for a particular image id.
     */
    public func cancel(_ libraryId: UUID, _ imageIds: [UUID]) {
        DDLogDebug("Canceling thumb req: libId=\(libraryId), images=\(imageIds)")
    }

    // MARK: - Errors
    /**
     * Errors that clients may receive during the thumbnail generation.
     */
    enum ThumbError: Error {
        /// An unknown error occurred.
        case unknownError
        /// The specified functionality is not implemented.
        case notImplemented
    }
}
