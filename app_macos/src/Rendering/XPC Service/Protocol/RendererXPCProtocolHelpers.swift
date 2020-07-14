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
        
        // request UUIDs
        let uuidClass = NSSet(array: [
            NSUUID.self
        ]) as! Set<AnyHashable>

        int.setClasses(uuidClass,
                       for: #selector(RendererHandlerXPCProtocol.jobCompleted(_:_:)),
                       argumentIndex: 0, ofReply: false)

        int.setClasses(uuidClass,
                       for: #selector(RendererHandlerXPCProtocol.jobFailed(_:_:)),
                       argumentIndex: 0, ofReply: false)

        return int
    }
    
    /**
     * Creates an XPC interface for remote side renderer instance.
     */
    static private func makeInstance() -> NSXPCInterface {
        let int = NSXPCInterface(with: RendererInstanceXPCProtocol.self)

        // request UUIDs
        let uuidClass = NSSet(array: [
            NSUUID.self
        ]) as! Set<AnyHashable>

        int.setClasses(uuidClass,
                       for: #selector(RendererInstanceXPCProtocol.render(_:withReply:)),
                       argumentIndex: 1, ofReply: true)

        return int
    }
    
    /// No initialization allowed lol
    private init() {}
}
