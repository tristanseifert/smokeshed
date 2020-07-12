//
//  RendererXPCProtocolHelpers.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200712.
//

import Foundation

/**
 * Helpers for working with the renderer XPC protocol
 */
internal class RendererXPCProtocolHelpers {
    /**
     * Creates an XPC interface for the remote side of the connection, which implements `RendererXPCProtocol`
     */
    static internal func makeRemote() -> NSXPCInterface {
        let int = NSXPCInterface(with: RendererXPCProtocol.self)

        // set up the dispense() request
        int.setInterface(Self.makeHandler(),
                         for: #selector(RendererXPCProtocol.dispense(_:handler:withReply:)),
                         argumentIndex: 1, ofReply: false)
        
        int.setInterface(Self.makeInstance(),
                         for: #selector(RendererXPCProtocol.dispense(_:handler:withReply:)),
                         argumentIndex: 1, ofReply: true)

        return int
    }
    
    /**
     * Creates an XPC interface for app-side handler objects.
     */
    static private func makeHandler() -> NSXPCInterface {
        let int = NSXPCInterface(with: RendererHandlerXPCProtocol.self)

        return int
    }
    
    /**
     * Creates an XPC interface for remote side renderer instance.
     */
    static private func makeInstance() -> NSXPCInterface {
        let int = NSXPCInterface(with: RendererInstanceXPCProtocol.self)

        return int
    }
    
    /// No initialization allowed lol
    private init() {}
}
