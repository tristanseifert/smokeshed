//
//  XPCDelegate.swift
//  Renderer
//
//  Created by Tristan Seifert on 20200712.
//

import Foundation
import OSLog
import Bowl

/**
 * Implements the XPC listener delegate.
 */
internal class XPCDelegate: NSObject, NSXPCListenerDelegate {
    fileprivate static var logger = Logger(subsystem: Bundle(for: XPCDelegate.self).bundleIdentifier!,
                                         category: "XPCDelegate")
    
    /// Render server
    private var server = RenderServer()
    
    /**
     * Perform some basic initialization of the renderer.
     */
    override init() {
        super.init()
        self.registerDefaults()
    }

    /**
     * Determines if the connection should be accepted. We authenticate the connecting client by checking
     * its code signature.
     */
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        Self.logger.debug("Received connection request from \(newConnection)")

        // if we get here, the connection should proceed
        newConnection.exportedInterface = RendererXPCProtocolHelpers.makeRemote()
        newConnection.exportedObject = self.server
        newConnection.resume()

        return true
    }
    
    /**
     * Registers default values for configuration.
     */
    private func registerDefaults() {
        // read defaults dict and register the defaults
        let url = Bundle(for: Self.self).url(forResource: "Defaults", withExtension: "plist")!
        let defaults = NSDictionary(contentsOf: url) as! [String: Any]
        
        UserDefaults.standard.register(defaults: defaults)
    }
}

