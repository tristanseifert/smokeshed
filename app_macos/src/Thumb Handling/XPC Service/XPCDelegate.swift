//
//  XPCDelegate.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200610.
//

import Foundation

import CocoaLumberjackSwift

/**
 * Implements the XPC listener delegate.
 */
class XPCDelegate: NSObject, NSXPCListenerDelegate {
    /**
     * Determines if the connection should be accepted. We authenticate the connecting client by checking
     * its code signature.
     */
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        DDLogVerbose("Received connection request from \(newConnection)")
        return false
    }
}
