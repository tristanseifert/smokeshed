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
    
    /// Maintenance endpoint
    private var maintenance: MaintenanceEndpoint! = nil

    // MARK: - XPC Calls
    /**
     * Loads the thumbnail directory, if not done already.
     */
    func wakeUp(withReply reply: @escaping (Error?) -> Void) {
        // open thumbnail directory if needed
        if self.directory == nil {
            do {
                self.directory = try ThumbDirectory()
                self.generator = Generator(self.directory)
                self.retriever = Retriever(self.directory)
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
     * Discards thumbnail data for all images specified.
     *
     * Images are identified only by their library id and image id; the URL and orientation are ignored.
     */
    func discard(_ requests: [ThumbRequest]) {
        self.generator?.discard(requests)
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
    
    // MARK: - Errors
    // XPC errors
    private enum XPCError: Error {
        /// Request is in flight, retry later
        case requestInFlight
    }
}
