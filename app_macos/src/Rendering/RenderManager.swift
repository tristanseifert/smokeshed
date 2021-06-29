//
//  RenderManager.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200716.
//

import Foundation
import Metal
import OSLog

/**
 * Manages the connection to the renderer service.
 */
class RenderManager {
    fileprivate static var logger = Logger(subsystem: Bundle(for: RenderManager.self).bundleIdentifier!,
                                         category: "RenderManager")
    
    /// Shared instance of the render manager
    public static var shared = RenderManager()

    // MARK: - Initialization
    /**
     * Establishes an XPC connection to the render service, and initializes some other state.
     */
    private init() {
        self.establishXpcConnection()
    }
    
    // MARK: XPC Connection
    /// Connection to the XPC service
    private var xpc: NSXPCConnection! = nil
    /// Render server XPC proxy object
    private var renderer: RendererXPCProtocol! = nil

    /**
     * Establishes a connection to the renderer XPC service.
     */
    private func establishXpcConnection() {
        // create the XPC connection
        self.xpc = NSXPCConnection(serviceName: Self.xpcServiceName)
        self.xpc.remoteObjectInterface = RendererXPCProtocolHelpers.makeRemote()

        // on invalidation, we must re-create the xpc connection
        self.xpc.invalidationHandler = {
            Self.logger.warning("Renderer XPC connection invalidated!")
            self.xpc = nil
        }
        
        // don't have to do anything on interruption, this should work automatically
        self.xpc.interruptionHandler = {
            Self.logger.info("Renderer XPC connection interrupted; reconnecting")
        }
        
        // connect that shit and get service
        self.xpc.resume()
        self.renderer = self.xpc.remoteObjectProxyWithErrorHandler() { error in
            Self.logger.error("Failed to get renderer XPC service remote proxy: \(error.localizedDescription)")
        } as? RendererXPCProtocol
    }
    
    // MARK: - Public interface
    /// Connection to the maintenance endpoint
    private var maintenanceXpc: NSXPCConnection? = nil
    /// Maintenance endpoint object proxy
    private var maintenanceProxy: RendererMaintenanceXPCProtocol? = nil
    /// Reference count to the maintenance endpoint: number of times `getMaintenanceEndpoint(_:)` was called
    private var maintenanceRefCount: UInt = 0
    
    // MARK: Maintenance
    /**
     * Retrieve the proxy object for the maintenance endpoint.
     *
     * - Note: Each call to this method (if successful) must be balanced with a call to `closeMaintenanceEndpoint()`.
     */
    public func getMaintenanceEndpoint(_ callback: @escaping (Result<RendererMaintenanceXPCProtocol, Error>) -> Void) {
        // already have an endpoint?
        if let endpoint = self.maintenanceProxy {
            self.maintenanceRefCount += 1
            return callback(.success(endpoint))
        }
        // get a handle to the endpoint
        self.renderer.getMaintenanceEndpoint() { endpoint in
            // create an XPC connection
            self.maintenanceXpc = NSXPCConnection(listenerEndpoint: endpoint)

            self.maintenanceXpc!.remoteObjectInterface = RendererXPCProtocolHelpers.makeMaintenanceEp()
            self.maintenanceXpc!.resume()
            
            // retrieve the remote object proxy
            let proxy = self.maintenanceXpc?.remoteObjectProxyWithErrorHandler() { error in
                callback(.failure(error))
            }
            guard proxy != nil else {
                return
            }
            
            // try to convert it
            self.maintenanceProxy = proxy as? RendererMaintenanceXPCProtocol
            guard self.maintenanceProxy != nil else {
                return callback(.failure(MaintenanceErrors.invalidRemoteProxy))
            }
            
            self.maintenanceRefCount += 1
            return callback(.success(self.maintenanceProxy!))
        }
    }
    
    /**
     * Closes the maintenance endpoint connection.
     */
    public func closeMaintenanceEndpoint() {
        guard self.maintenanceRefCount != 0 else {
            Self.logger.error("Attempt to decrement ref count past 0")
            return
        }
        
        // decrement ref count and release if 0
        self.maintenanceRefCount -= 1
        
        if self.maintenanceRefCount == 0 {
            // clear out the service
            self.maintenanceProxy = nil
            
            // invalidate the xpc connection
            self.maintenanceXpc!.invalidate()
            self.maintenanceXpc = nil
        }
    }
    
    // MARK: - Renderers
    /**
     * Gets a display renderer.
     *
     * This renderer will run on the device specified, or the system default device otherwise.
     */
    public func getDisplayRenderer(_ device: MTLDevice?, callback: @escaping (Result<DisplayImageRenderer, Error>) -> Void) {
        // get the registry id for the device
        var registryId = device?.registryID ?? 0
        
        if registryId == 0 {
            registryId = MTLCreateSystemDefaultDevice()!.registryID
        }
        
        // ask the service to make a renderer
        self.renderer.getDisplayRenderer(registryId) { err, proxy in
            precondition((err != nil) || (proxy != nil), "Invalid xpc response")
            
            // was there an error?
            if let err = err {
                return callback(.failure(err))
            }
            // did we get a proxy?
            else if let proxy = proxy {
                let renderer = DisplayImageRenderer(proxy)
                return callback(.success(renderer))
            }
        }
    }
    
    // MARK: - Errors
    enum MaintenanceErrors: Error {
        /// The remote proxy of the maintenance endpoint does not implement the expected protocol
        case invalidRemoteProxy
    }
    
    // MARK: - Constants
    /// Service name (on macOS, bundle id) of the renderer XPC service
    private static let xpcServiceName = "me.tseifert.smokeshed.xpc.renderer"
}
