//
//  XPCDelegate.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200610.
//

import Foundation
import Security

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
     * Determines if the connection should be accepted. We authenticate the connecting client by checking
     * its code signature.
     */
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        DDLogVerbose("Received connection request from \(newConnection)")

        // attempt to validate the connecting client
        do {
            // get a reference to its code signature and its info
            let code = try XPCCSHelpers.getXpcGuest(newConnection)
            let info = try XPCCSHelpers.getSigningInfo(code)

            // ensure the signature satisfies our checks
            try XPCCSHelpers.validateSignatureState(info)
            try XPCCSHelpers.validateSignature(code)
        } catch {
            DDLogError("Failed to validate connecting client (\(newConnection)): \(error)")
            return false
        }

        // if we get here, the connection should proceed
        newConnection.exportedInterface = ThumbXPCProtocolHelpers.make()
        newConnection.exportedObject = self.handler
        newConnection.resume()

        return true
    }
}
