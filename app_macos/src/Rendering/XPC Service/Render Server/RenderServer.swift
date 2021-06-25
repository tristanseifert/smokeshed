//
//  RenderServer.swift
//  Renderer
//
//  Created by Tristan Seifert on 20200714.
//

import Foundation

import CocoaLumberjackSwift

/**
 * Implements the render server, which provides the XPC interface to the app for rendering. It also allows dispensing of renderer
 * instances.
 */
internal class RenderServer: RendererXPCProtocol {
    /**
     * An array keeping track of all currently active renderers.
     *
     * This serves to keep a strong reference to them until whoever was using them on the other side of the XPC connection no longer
     * needs them. However, this also means that their resources _will_ be leaked if not properly released.
     */
    private var renderers: [UUID: Renderer] = [:]
    
    // MARK: - Initialization
    /// Notification observer for "renderer released"
    private var rendererReleasedObs: NSObjectProtocol! = nil
    
    /**
     * Adds an observer for the "renderer released" notification
     */
    init() {
        let c = NotificationCenter.default
        
        self.rendererReleasedObs = c.addObserver(forName: .rendererReleased, object: nil,
                                                 queue: nil) { [weak self] note in
            guard let obj = note.userInfo,
                  let id = obj["identifier"] as? UUID,
                  let renderer = self?.renderers[id] else {
                DDLogWarn("Failed to get renderer from release notification: \(note)")
                return
            }
            
            DDLogVerbose("Releasing renderer \(renderer) (have: \(self?.renderers.count ?? 0))")
            self?.renderers.removeValue(forKey: id)
            DDLogVerbose("Total renderers remaining: \(self?.renderers.count ?? 0)")
        }
    }
    
    /**
     * Removes notification observers
     */
    deinit {
        if let obs = self.rendererReleasedObs {
            NotificationCenter.default.removeObserver(obs)
        }
    }
    
    // MARK: - XPC Interface
    /// Maintenance endpoint (lazily allocated in response to the `getMaintenanceEndpoint()` call
    private var maintenance: MaintenanceEndpoint! = nil
    
    // MARK: Renderer instantiation
    /**
     * Creates a renderer that writes to files.
     */
    func getFileRenderer(withReply callback: @escaping (Error?, RendererFileXPCProtocol?) -> Void) {
        // TODO: implement
    }
    
    /**
     * Creates a bitmap renderer. The best device is automatically chosen.
     */
    func getBitmapRenderer(withReply callback: @escaping (Error?, RendererBitmapXPCProtocol?) -> Void) {
        // TODO: implement
    }
    
    /**
     * Try to create a display renderer on the given device.
     */
    func getDisplayRenderer(_ deviceRegistryId: UInt64, withReply callback: @escaping (Error?, RendererUserInteractiveXPCProtocol?) -> Void) {
        do {
            let devices = MTLCopyAllDevices()
            guard let device = devices.first(where: { $0.registryID == deviceRegistryId }) else {
                throw Errors.invalidDeviceId(deviceRegistryId)
            }
            
            // create a renderer
            let renderer = try UserInteractiveRenderer(device)
            self.renderers[renderer.identifier] = renderer
            
            // run response callback
            return callback(nil, renderer)
        } catch {
            return callback(error, nil)
        }
    }
    
    // MARK: Management
    /**
     * Allocates the maintenance endpoint, if needed, and returns a reference to it.
     */
    func getMaintenanceEndpoint(withReply reply: @escaping (NSXPCListenerEndpoint) -> Void) {
        // allocate endpoint if needed
        if self.maintenance == nil {
            self.maintenance = MaintenanceEndpoint()
        }
        
        // get the connection
        reply(self.maintenance.endpoint)
    }
    
    // MARK: Errors
    enum Errors: Error {
        /// The provided registry id does not correspond to a valid device.
        case invalidDeviceId(_ id: UInt64)
    }
}

/**
 * Interface of all renderer objects
 */
internal class Renderer {
    /// Unique id for the renderer
    var identifier: UUID
    
    init() {
        self.identifier = UUID()
    }
}

internal extension Notification.Name {
    /// A renderer is being released and is no longer needed. Notification object is the renderer.
    static let rendererReleased = Notification.Name("me.tseifert.smokeshed.xpc.hand.renderer.release")
}
