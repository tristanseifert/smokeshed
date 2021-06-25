//
//  ThumbServer.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200611.
//

import Foundation
import CoreGraphics

import Waterpipe
import CocoaLumberjackSwift

/**
 * Provides the interface used by XPC clients to generate and request thumbnail images.
 */
class ThumbServer: ThumbXPCProtocol {
    /// Thumbnail directory
    private var directory: ThumbDirectory! = nil
    /// Generator for creating/deleting thumbs
    private var generator: Generator! = nil
    /// Retrieving thumbs
    private var retriever: Retriever! = nil
    /// Prefetching thumbnail data
    private var prefetcher: Prefetcher! = nil
    
    /// Maintenance endpoint
    private var maintenance: MaintenanceEndpoint! = nil
    
    /// handler proxy object to call into when thumbs are updated
    private(set) internal var eventHandlerProxy: ThumbXPCHandler? = nil
    
    // MARK: - Initialization
    /**
     * Initialize a new thumb server.
     */
    init() {
        self.addThumbObservers()
    }
    
    /**
     * Ensure thumbs observers are removed on dealloc.
     */
    deinit {
        self.removeThumbObservers()
    }

    // MARK: - XPC Calls
    /**
     * Loads the thumbnail directory, if not done already.
     */
    func wakeUp(handler: ThumbXPCHandler, withReply reply: @escaping (Error?) -> Void) {
        /// XPC proxy for the event handler, it must be stored
        self.eventHandlerProxy = handler
        
        // open thumbnail directory if needed
        if self.directory == nil {
            do {
                self.directory = try ThumbDirectory()
                self.generator = Generator(self.directory)
                self.retriever = Retriever(self.directory)
                self.prefetcher = Prefetcher(self.directory)
            } catch {
                DDLogError("Failed to open thumb directory: \(error)")
                return reply(error)
            }
            
            // if we get here, directory opened successfully
            reply(nil)
        }
        // otherwise, nothing to be done
        else {
            reply(nil)
        }
    }
    
    /**
     * Opens a library with the given UUID. This will create an entry for it in the library directory if needed.
     */
    func openLibrary(_ libraryId: UUID, withReply reply: @escaping (Error?) -> Void) {
        DDLogVerbose("Opening thumb library: \(libraryId)")
        
        do {
            try self.directory.openLibrary(libraryId)
        } catch {
            DDLogError("Failed to open library: \(error)")
            return reply(error)
        }
        
        // library was opened successfully
        reply(nil)
    }
    
    /**
     * Saves all thumbnail data.
     */
    func save(withReply reply: @escaping (Error?) -> Void) {
        do {
            // first, save all chunks
            try self.directory.chonker.flushDirtyChunks()
            
            // then, save the object context
            try self.directory.save()
        } catch {
            DDLogError("Failed to save thumbnail data: \(error)")
            return reply(error)
        }
        
        // if we get here, save succeeded
        return reply(nil)
    }
    
    /**
     * Generates a thumbnail for the image specified in the request. This is dispatched to the background
     * processing thread.
     */
    func generate(_ requests: [ThumbRequest]) {
        self.generator.generate(requests)
    }
    
    /**
     * Prefetch data for the provided images. This serves as a hint that thumbnails for them will likely be requested soon.
     *
     * In this implementation, we call through to the prefetch handler, which will fault in information for each of the chunks, and then try
     * to warm up the chunk cache for them as well.
     */
    func prefetch(_ requests: [ThumbRequest]) {
        self.prefetcher.prefetch(requests)
    }
    
    /**
     * Discards thumbnail data for all images specified.
     *
     * Images are identified only by their library id and image id; the URL and orientation are ignored.
     */
    func discard(_ requests: [ThumbRequest]) {
        self.generator.discard(requests)
    }

    /**
     * Gets the thumbnail for the provided image.
     */
    func get(_ request: ThumbRequest, withReply reply: @escaping (ThumbRequest, IOSurface?, Error?) -> Void) {
        // is the (library id, thumb id) pair in progress?
        guard !self.generator.isInFlight(request) else {
            // TODO: run callback when generation completes
            return reply(request, nil, XPCError.requestInFlight)
        }
        
        // try to get the image
        self.retriever.retrieve(request) { result in
            switch result {
            // create an IOSurface from the image
            case .success(let image):
                let surface = IOSurface.fromImage(image)
                reply(request, surface, nil)
                surface?.decrementUseCount()
                
            // propagate failures to caller
            case .failure(let error):
                DDLogError("Failed to create thumb: \(error)")
                reply(request, nil, error)
            }
        }
    }
    
    /**
     * Gets a reference to the maintenance endpoint.
     */
    func getMaintenanceEndpoint(withReply reply: @escaping (NSXPCListenerEndpoint) -> Void) {
        // allocate endpoint if needed
        if self.maintenance == nil {
            self.maintenance = MaintenanceEndpoint(self.directory)
        }
        
        // get the connection
        reply(self.maintenance.endpoint)
    }
    
    // MARK: Notifications handling
    /// Notification observers
    private var thumbNotificationObs: [NSObjectProtocol] = []
    
    /// Queue on which thumb creation/update notifications are posted
    private var thumbNotificationQueue: OperationQueue = {
       let queue = OperationQueue()
        
        queue.qualityOfService = .utility
        queue.name = "Thumb Notification Observer Queue"
        queue.maxConcurrentOperationCount = 1
        
        return queue
    }()
    
    /**
     * Add observers for thumb notifications
     */
    private func addThumbObservers() {
        let c = NotificationCenter.default
        
        // thumb created
        let o1 = c.addObserver(forName: .thumbCreated, object: nil,
                               queue: self.thumbNotificationQueue) { notif in
            if let created = notif.userInfo?["created"] as? [[UUID]] {
                for obj in created {
                    // there must be two items
                    guard obj.count == 2 else { continue }
                    
                    let libraryId = obj[0]
                    let imageId = obj[1]
                    
                    self.eventHandlerProxy?.thumbChanged(inLibrary: libraryId, imageId)
                }
            }
        }
        self.thumbNotificationObs.append(o1)
        
        // thumb updated
        let o2 = c.addObserver(forName: .thumbUpdated, object: nil,
                               queue: self.thumbNotificationQueue) { notif in
            if let created = notif.userInfo?["updated"] as? [[UUID]] {
                for obj in created {
                    // there must be two items
                    guard obj.count == 2 else { continue }
                    
                    let libraryId = obj[0]
                    let imageId = obj[1]
                    
                    self.eventHandlerProxy?.thumbChanged(inLibrary: libraryId, imageId)
                }
            }
        }
        self.thumbNotificationObs.append(o2)
    }
    
    /**
     * Removes thumb notification observers.
     */
    private func removeThumbObservers() {
        let c = NotificationCenter.default
        
        for obs in self.thumbNotificationObs {
            c.removeObserver(obs)
        }
    }
    
    // MARK: - Errors
    // XPC errors
    private enum XPCError: Error {
        /// Request is in flight, retry later
        case requestInFlight
    }
}

extension Notification.Name {
    /**
     * Thumbnail was created notification
     *
     * Info dictionary contains an array of two-element arrays, containing first the library id, then the image id, of the thumbnails for
     * which data was created.
     */
    internal static let thumbCreated = Notification.Name("me.tseifert.smokeshed.xpc.hand.thumb.created")
    
    /**
     * Thumbnail was updated notification
     *
     * Info dictionary contains an array of two-element arrays, containing first the library id, then the image id, of the thumbnails for
     * which data was updated.
     */
    internal static let thumbUpdated = Notification.Name("me.tseifert.smokeshed.xpc.hand.thumb.updated")
}
