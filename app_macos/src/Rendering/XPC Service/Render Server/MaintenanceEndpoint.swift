//
//  MaintenanceEndpoint.swift
//  Renderer
//
//  Created by Tristan Seifert on 20200716.
//

import Foundation

import CocoaLumberjackSwift

internal class MaintenanceEndpoint: NSObject, RendererMaintenanceXPCProtocol, NSXPCListenerDelegate {
    /// Queue on which the XPC connection is created
    private var listenQueue = DispatchQueue(label: "Maintenance Endpoint")
    
    // MARK: - Initialization
    /**
     * Instantiates the maintenance endpoint, including its associated XPC listener.
     */
    override init() {
        super.init()
        
        self.setUpListener()
    }
    
    /**
     * Clean up the XPC resources on dealloc.
     */
    deinit {
        self.listener.invalidate()
    }
    
    // MARK: - XPC
    /// XPC endpoint on which the maintenance endpoint is listening
    internal var endpoint: NSXPCListenerEndpoint! {
        return self.listener.endpoint
    }
    /// Listener for the maintenance endpoint
    private var listener: NSXPCListener!
    
    /**
     * Initializes the XPC listener.
     */
    private func setUpListener() {
        self.listener = NSXPCListener.anonymous()
        self.listener.delegate = self
        
        self.listenQueue.async {
            self.listener.resume()
        }
    }
    
    // MARK: XPC Delegate
    /**
     * Determines if the caller is allowed to access this interface.
     */
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection new: NSXPCConnection) -> Bool {
        DDLogVerbose("Connection to maintenance endpoint: \(new)")
        
        // create the connection
        new.exportedInterface = RendererXPCProtocolHelpers.makeMaintenanceEp()
        new.exportedObject = self
        new.resume()
        
        return true
    }
    
    // MARK: External Interface
    /**
     * Gets the current XPC service configuration.
     */
    func getConfig(withReply reply: @escaping ([String : Any]) -> Void) {
        var rep = UserDefaults.standard.dictionaryRepresentation()
        rep = rep.filter({
            return (RendererXPCConfigKey(rawValue: $0.key) != nil)
        })
        
        reply(rep)
    }
    
    /**
     * Updates the xpc service configuration.
     */
    func setConfig(_ config: [String : Any]) {
        let values = config.filter({
            return (RendererXPCConfigKey(rawValue: $0.key) != nil)
        })
        
        UserDefaults.standard.setValuesForKeys(values)
    }
}
