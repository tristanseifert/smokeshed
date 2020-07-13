//
//  XPCDelegate.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200610.
//

import Foundation

import Bowl
import CocoaLumberjackSwift

/**
 * Implements the XPC listener delegate.
 */
class XPCDelegate: NSObject, NSXPCListenerDelegate {
    /**
     * Implements the actual thumbnail processing. There's one instance shared between every connected
     * XPC client, allocated lazily.
     */
    private lazy var handler = ThumbServer()
    
    /**
     * Perform some basic initialization of the thumb service.
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
        DDLogVerbose("Received connection request from \(newConnection)")

        // if we get here, the connection should proceed
        newConnection.exportedInterface = ThumbXPCProtocolHelpers.make()
        newConnection.exportedObject = self.handler
        newConnection.resume()

        return true
    }
    
    /**
     * Registers default values for configuration.
     */
    private func registerDefaults() {
        // read defaults dict
        let url = Bundle(for: Self.self).url(forResource: "Defaults", withExtension: "plist")!
        let defaults = NSDictionary(contentsOf: url) as! [String: Any]
        
        // thumb service defaults
        UserDefaults.standard.register(defaults: defaults)
        
        // register default thumb path if required
        if UserDefaults.standard.object(forKey: "thumbStorageUrl") == nil {
            let thumbDir = ContainerHelper.groupAppCache(component: .thumbHandler)
            let bundleUrl = thumbDir.appendingPathComponent("Thumbs.smokethumbs", isDirectory: true)
            UserDefaults.standard.thumbStorageUrl = bundleUrl
        }
    }
}
