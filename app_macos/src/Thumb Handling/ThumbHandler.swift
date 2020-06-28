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
    typealias GetCallback = (UUID, Result<IOSurface, Error>) -> Void

    /// XPC connection to the thumbnail helper
    private var xpc: NSXPCConnection! = nil
    /// Remote thumbnail service
    private var service: ThumbXPCProtocol! = nil
    
    /// Connection to the maintenance endpoint
    private var maintenance: NSXPCConnection? = nil
    /// Maintenance endpoint object proxy
    private var maintenanceService: ThumbXPCMaintenanceEndpoint? = nil

    // MARK: - Initialization
    /**
     * Creates a new thumb handler instance. This establishes a connection to the thumb generator XPC
     * service and tells it about our state.
     */
    private init() {
        self.observerQueue.name = "ThumbHandler MOC Observers"
        self.observerQueue.qualityOfService = .utility
        self.observerQueue.maxConcurrentOperationCount = 1
        
        self.establishXpcConnection()
    }
    
    /**
     * Remove observers on deallocation
     */
    deinit {
        self.removeImageObservers()
    }

    /**
     * Establishes an XPC connection to the thumb handler.
     */
    private func establishXpcConnection() {
        // create the XPC connection
        self.xpc = NSXPCConnection(serviceName: "me.tseifert.smokeshed.xpc.hand")

        self.xpc.remoteObjectInterface = ThumbXPCProtocolHelpers.make()
        self.xpc.resume()

        // then, get the service object
        self.service = self.xpc.remoteObjectProxyWithErrorHandler { error in
            DDLogError("Failed to get remote object proxy: \(error)")

            if let xpc = self.xpc {
                xpc.invalidate()
                self.xpc = nil
            }
        } as? ThumbXPCProtocol

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
        // open it in the xpc service as well
        if let service = self.service {
            service.openLibrary(id, withReply: { error in
                if let err = error {
                    DDLogError("Failed to open library in thumb handler: \(err)")
                }
            })
        }
        
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
    
    // MARK: - Context observer
    /// Queue for background notifications
    private var observerQueue = OperationQueue()
    /// Observers we've registered for background changes
    private var observers: [NSObjectProtocol] = []
    
    /**
     * Specifies the currently opened library; the context of this library is observed for changes (such as
     * insertions, edits or deletions) of images, so that thumbnails can be updated accordingly.
     */
    internal var library: LibraryBundle? {
        didSet(oldLibrary) {
            let c = NotificationCenter.default
            
            // unsubscribe old notifications
            self.removeImageObservers()
            
            guard let new = self.library else {
                return
            }
            
            // subscribe for object queue changes on the new context
            let o = c.addObserver(forName: .NSManagedObjectContextObjectsDidChange,
                                  object: new.store.mainContext,
                                  queue: self.observerQueue)
            { [weak self] notification in
                guard let changes = notification.userInfo else {
                    fatalError("Received NSManagedObjectContext.didChangeObjectsNotification without user info")
                }
                
                self?.processContextChanges(changes)
            }
            self.observers.append(o)
            
            // save thumb data whenever main context saves
            let o2 = c.addObserver(forName: .NSManagedObjectContextDidSave,
                                   object: new.store.mainContext,
                                   queue: self.observerQueue)
            { [weak self] notification in
                self?.service.save() { error in
                    if let error = error {
                        DDLogError("Failed to save thumb data: \(error)")
                    }
                }
            }
            self.observers.append(o2)
        }
    }
    
    /**
     * Removes all existing observers for image changes.
     */
    private func removeImageObservers() {
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
        self.observers.removeAll()
    }
    
    /**
     * Processes a CoreData change notification.
     */
    private func processContextChanges(_ changes: [AnyHashable: Any]) {
        guard let ctx = self.library?.store.mainContext,
              let libraryId = self.library?.identifier else {
            return
        }
        
        // for deleted objects, simply discard them
        if let objects = changes[NSDeletedObjectsKey] as? Set<NSManagedObject> {
            let deleted = objects.compactMap({ $0 as? Image })
            if !deleted.isEmpty {
                // create thumb requests on the context queue
                ctx.perform {
                    let req = deleted.compactMap({
                        return ThumbRequest(libraryId: libraryId, image: $0,
                                            withDetails: false)
                    })
                    guard !req.isEmpty else { return }
                    
                    // issue deletion on our background queue
                    self.observerQueue.addOperation { [weak self] in
                        self?.service!.discard(req)
                    }
                }
            }
        }
        
        // newly generated objects need to be generated
        if let objects = changes[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            let inserted = objects.compactMap({ $0 as? Image })
            if !inserted.isEmpty {
                // create thumb requests on the context queue
                ctx.perform {
                    let req = inserted.compactMap({
                        return ThumbRequest(libraryId: libraryId, image: $0,
                                            withDetails: true)
                    })
                    guard !req.isEmpty else { return }
                    
                    // issue generation request on our background queue
                    self.observerQueue.addOperation { [weak self] in
                        self?.service!.generate(req)
                    }
                }
            }
        }
        
        // TODO: for changed objects… lmao yikes
        if let objects = changes[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            let updated = objects.compactMap({ $0 as? Image })
            if !updated.isEmpty {
                DDLogInfo("Modified images: \(updated)")
            }
        }
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

        self.generate(self.libraryIdStack.last!, images)
    }

    /**
     * Generates thumbnails for each of the dictionaries of image properties. At a minimum, the
     * `identifier` and `originalUrl` fields must exist. The thumbnails are tagged with the
     * provided library id.
     */
    public func generate(_ libraryId: UUID, _ images: [Image]) {
        // convert images to requests
        let requests = images.compactMap({ image in
            return ThumbRequest(libraryId: libraryId, image: image)
        })
        
        self.service!.generate(requests)
    }
    
    /**
     * Retrieve the proxy object for the maintenance endpoint.
     */
    public func getMaintenanceEndpoint(_ callback: @escaping (ThumbXPCMaintenanceEndpoint) -> Void) {
        // already have an endpoint?
        if let endpoint = self.maintenanceService {
            return callback(endpoint)
        }
        // get a handle to the endpoint
        self.service.getMaintenanceEndpoint() { endpoint in
            // create an XPC connection
            self.maintenance = NSXPCConnection(listenerEndpoint: endpoint)

            self.maintenance!.remoteObjectInterface = ThumbXPCProtocolHelpers.makeMaintenanceEndpoint()
            self.maintenance!.resume()
            
            // retrieve the remote object proxy
            self.maintenanceService = (self.maintenance!.remoteObjectProxy as! ThumbXPCMaintenanceEndpoint)
            callback(self.maintenanceService!)
        }
    }
    
    /**
     * Closes the maintenance endpoint connection.
     */
    public func closeMaintenanceEndpoint() {
        // clear out the service
        self.maintenanceService = nil
        
        // invalidate the xpc connection
        self.maintenance!.invalidate()
        self.maintenance = nil
    }

    // MARK: Retrieval
    /**
     * Gets the "best fit" thumbnail image for the specified size.
     */
    public func get(_ image: Image, _ size: CGSize = .zero, _ handler: @escaping GetCallback) {
        if self.libraryIdStack.isEmpty {
            fatalError("No library id has been set; use the long form of generate() or call pushLibraryId()")
        }

        self.get(self.libraryIdStack.last!, image, size, handler)
    }

    /**
     * Gets the "best fit" thumbnail image for the specified size. The image is identified by a parameter
     * dictionary and library id.
     */
    public func get(_ libraryId: UUID, _ image: Image, _ size: CGSize, _ handler: @escaping GetCallback) {
        // prepare a request
        guard let req = ThumbRequest(libraryId: libraryId, image: image) else {
            handler(image.identifier!, .failure(ThumbError.failedToCreateRequest))
            return
        }

        req.size = size

        self.service!.get(req, withReply: { req, inImg, inErr in
            // handle the error case first
            if let error = inErr {
                handler(req.imageId, .failure(error))
            }
            // otherwise, handle success case
            else if let surface = inImg {
                handler(req.imageId, .success(surface))
            }
            // something got seriously fucked
            else {
                handler(req.imageId, .failure(ThumbError.unknownError))
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

        self.cancel(self.libraryIdStack.last!, images.compactMap({ (image) in
            return image.identifier
        }))
    }

    /**
     * Cancels all thumbnail operations for a particular image id.
     */
    public func cancel(_ libraryId: UUID, _ imageIds: [UUID]) {
//        DDLogDebug("Canceling thumb req: libId=\(libraryId), images=\(imageIds)")
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
        /// Failed to create a thumbnail request
        case failedToCreateRequest
    }
}
