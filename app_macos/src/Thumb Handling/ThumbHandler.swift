//
//  ThumbHandler.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200610.
//

import Foundation
import AppKit
import IOSurface
import OSLog

import Smokeshop

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
class ThumbHandler: ThumbXPCHandler {
    fileprivate static var logger = Logger(subsystem: Bundle(for: ThumbHandler.self).bundleIdentifier!,
                                         category: "ThumbHandler")
    
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
    /// Observer for quit notification
    private var quitObs: NSObjectProtocol? = nil
    
    /**
     * Creates a new thumb handler instance. This establishes a connection to the thumb generator XPC
     * service and tells it about our state.
     */
    private init() {
        self.observerQueue.name = "ThumbHandler MOC Observers"
        self.observerQueue.qualityOfService = .utility
        self.observerQueue.maxConcurrentOperationCount = 1
        
        self.establishXpcConnection()
        
        // subscribe for the quit notification
        self.quitObs = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                              object: nil, queue: nil) { _ in
            // on quit, save thumb status
            self.service.save() {
                if let error = $0 {
                    Self.logger.error("Failed to save thumb service state: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /**
     * Remove observers on deallocation
     */
    deinit {
        self.removeImageObservers()
        
        if let obs = self.quitObs {
            NotificationCenter.default.removeObserver(obs)            
        }
    }

    /**
     * Establishes an XPC connection to the thumb handler.
     */
    private func establishXpcConnection() {
        // create the XPC connection
        self.xpc = NSXPCConnection(serviceName: "me.tseifert.smokeshed.xpc.hand")

        self.xpc.remoteObjectInterface = ThumbXPCProtocolHelpers.make()
        
        // when invalidated, print a message and retry
        self.xpc.invalidationHandler = {
            Self.logger.warning("Thumb XPC connection invalidated")
            self.xpc = nil
        }
        
        // on interruption, attempt to get the service again
        self.xpc.interruptionHandler = {
            Self.logger.warning("Thumb connection interrupted; reconnecting")
            self.getService()
        }
        
        // connect that shit and get service
        self.xpc.resume()

        self.getService()
        self.wakeXpcService()
    }
    
    /**
     * Gets a handle to the remote XPC object.
     */
    private func getService() {
        self.service = self.xpc.remoteObjectProxyWithErrorHandler { error in
            Self.logger.error("Failed to get remote object proxy: \(error.localizedDescription)")
        } as? ThumbXPCProtocol
    }

    /**
     * Tells the XPC service to initialize itself.
     */
    private func wakeXpcService() {
        self.service!.wakeUp(handler: self, withReply: { error in
            // handle errors… not much we can do but invalidate connection
            guard error == nil else {
                Self.logger.error("Failed to wake thumb service: \(error!.localizedDescription)")

                self.service = nil

                self.xpc.invalidate()
                self.xpc = nil
                return
            }

            // cool, we're ready for service™
            Self.logger.debug("Thumb handler has woken up")
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
                    Self.logger.error("Failed to open library in thumb handler: \(err.localizedDescription)")
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
                        Self.logger.error("Failed to save thumb data: \(error.localizedDescription)")
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
                        return ThumbRequest(libraryId: libraryId, libraryUrl: self.library!.url, image: $0,
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
                        return ThumbRequest(libraryId: libraryId, libraryUrl: self.library!.url, image: $0,
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
        
        // updated images should get their thumbs updated (unless only metadata changed)
        if let objects = changes[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            let updated = objects.compactMap({ $0 as? Image })
            if !updated.isEmpty {
                // TODO: handle this
            }
        }
    }

    // MARK: - External API
    // MARK: Prefetch
    /**
     * Prefetch data for a single image.
     */
    public func prefetch(_ image: Image) {
        self.prefetch([image])
    }
    
    /**
     * Prefetches thumbnail data for all of the provided images.
     */
    public func prefetch(_ images: [Image]) {
        if self.libraryIdStack.isEmpty {
            fatalError("No library id has been set; use the long form of prefetch() or call pushLibraryId()")
        }

        self.prefetch(self.libraryIdStack.last!, images)
    }
    
    /**
     * Prefetch data for all images in the given library.
     */
    public func prefetch(_ libraryId: UUID, _ images: [Image]) {
        let requests = images.compactMap({ image in
            return ThumbRequest(libraryId: libraryId, libraryUrl: self.library!.url, image: image, withDetails: false)
        })
        
        self.service?.prefetch(requests)
    }
    
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
            return ThumbRequest(libraryId: libraryId, libraryUrl: self.library!.url, image: image, withDetails: true)
        })
        
        self.service!.generate(requests)
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
        guard let req = ThumbRequest(libraryId: libraryId, libraryUrl: self.library!.url, image: image, withDetails: false) else {
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
//        Self.logger.debug("Canceling thumb req: libId=\(libraryId), images=\(imageIds)")
    }
    
    // MARK: Maintenance
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
        self.maintenance?.invalidate()
        self.maintenance = nil
    }
    
    // MARK: - Event callbacks
    /// Map of observer id -> callback. This allows us to remove it later
    private var thumbCallbacks: [UUID: ((UUID, UUID) -> Void)] = [:]
    /// Protect access to the thumb callbacks dict
    private var thumbCallbacksSem = DispatchSemaphore(value: 1)
    
    /// Observers for thumb changes (key is image id, value is a set of callback UUIDs)
    private var thumbCallbacksMap: [UUID: Set<UUID>] = [:]
    /// Protect access to the thumb callbacks map dict
    private var thumbCallbacksMapSem = DispatchSemaphore(value: 1)
    
    /**
     * Post a notification indicating that the thumbnail for this image has changed.
     */
    func thumbChanged(inLibrary library: UUID, _ imageId: UUID) {
//        Self.logger.info("Thumb changed: library id \(library), image id \(imageId)")
        
        // fire all observers for the image id
        self.thumbCallbacksMapSem.wait()
        
        if let callbacks = self.thumbCallbacksMap[imageId] {
//            Self.logger.debug("Callbacks for \(imageId): \(callbacks)")
            
            // invoke each handler
            self.thumbCallbacksSem.wait()
            
            for callbackId in callbacks {
                if let callback = self.thumbCallbacks[callbackId] {
                    callback(library, imageId)
                }
            }
            
            self.thumbCallbacksSem.signal()
        }
        
        self.thumbCallbacksMapSem.signal()
    }
    
    /**
     * Adds a thumbnail observer callback.
     *
     * - Returns: A token (a UUID) that can be used to remove this observer later.
     */
    public func addThumbObserver(imageId: UUID, _ observer: @escaping (UUID, UUID) -> Void) -> UUID {
        // insert the observer
        let token = UUID()
        
        self.thumbCallbacksSem.wait()
        self.thumbCallbacks[token] = observer
        self.thumbCallbacksSem.signal()
        
        // add it to the callback map
        self.thumbCallbacksMapSem.wait()
        
        if let set = self.thumbCallbacksMap[imageId] {
            var newSet = set
            newSet.insert(token)
            
            self.thumbCallbacksMap[imageId] = newSet
        } else {
            // create a set
            self.thumbCallbacksMap[imageId] = Set([token])
        }
        
        self.thumbCallbacksMapSem.signal()
        
//        Self.logger.trace("Added observer for image \(imageId): token is \(token)")
        
        // return the token
        return token
    }
    
    /**
     * Removes a thumbnail observer callback based on a previously issued token.
     */
    public func removeThumbObserver(_ token: UUID) {
//        Self.logger.trace("Removing observer for token \(token)")
        
        // search the callbacks map for this token
        self.thumbCallbacksMapSem.wait()
        
        for var set in self.thumbCallbacksMap.values {
            if set.contains(token) {
                set.remove(token)
                break
            }
        }
        
        self.thumbCallbacksMapSem.signal()
    
        // remove the actual callback
        self.thumbCallbacksSem.wait()
        self.thumbCallbacks.removeValue(forKey: token)
        self.thumbCallbacksSem.signal()
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
