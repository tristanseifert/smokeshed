//
//  RendererXPCProtocolHelpers.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200712.
//

import Foundation

import Waterpipe

/**
 * Helpers for working with the renderer XPC protocol
 */
internal class RendererXPCProtocolHelpers {
    /**
     * Creates an XPC interface for the remote side of the connection, which implements `RendererXPCProtocol`
     */
    static internal func makeRemote() -> NSXPCInterface {
        let int = NSXPCInterface(with: RendererXPCProtocol.self)

        // renderer type dispensers
        int.setInterface(Self.makeUserInteractive(),
                         for: #selector(RendererXPCProtocol.getDisplayRenderer(_:withReply:)),
                         argumentIndex: 1, ofReply: true)
        
        int.setInterface(Self.makeBitmap(),
                         for: #selector(RendererXPCProtocol.getBitmapRenderer(withReply:)),
                         argumentIndex: 1, ofReply: true)
        
        int.setInterface(Self.makeFile(),
                         for: #selector(RendererXPCProtocol.getFileRenderer(withReply:)),
                         argumentIndex: 1, ofReply: true)

        return int
    }
    
    /**
     * Creates an XPC interface for a display renderer.
     */
    static private func makeUserInteractive() -> NSXPCInterface {
        let int = NSXPCInterface(with: RendererUserInteractiveXPCProtocol.self)
        
        let renderDescClass = NSSet(array: [
            RenderDescriptor.self
        ]) as! Set<AnyHashable>
        int.setClasses(renderDescClass,
                       for: #selector(RendererUserInteractiveXPCProtocol.setRenderDescriptor(_:withReply:)),
                       argumentIndex: 0, ofReply: false)
        
        let tiledImageClass = NSSet(array: [
            TiledImage.TiledImageArchive.self
        ]) as! Set<AnyHashable>
        int.setClasses(tiledImageClass,
                       for: #selector(RendererUserInteractiveXPCProtocol.setRenderDescriptor(_:withReply:)),
                       argumentIndex: 1, ofReply: true)

        return int
    }
    
    /**
     * Creates an XPC interface for a bitmap renderer.
     */
    static private func makeBitmap() -> NSXPCInterface {
        let int = NSXPCInterface(with: RendererBitmapXPCProtocol.self)
        
        let renderDescClass = NSSet(array: [
            RenderDescriptor.self
        ]) as! Set<AnyHashable>
        int.setClasses(renderDescClass,
                       for: #selector(RendererBitmapXPCProtocol.render(_:withReply:)),
                       argumentIndex: 0, ofReply: false)

        return int
    }
    
    /**
     * Creates an XPC interface for a file renderer.
     */
    static private func makeFile() -> NSXPCInterface {
        let int = NSXPCInterface(with: RendererFileXPCProtocol.self)
        
        let renderDescClass = NSSet(array: [
            RenderDescriptor.self
        ]) as! Set<AnyHashable>
        int.setClasses(renderDescClass,
                       for: #selector(RendererFileXPCProtocol.render(_:_:withReply:)),
                       argumentIndex: 0, ofReply: false)

        return int
    }
    
    /**
     * Create the XPC interface for the maintenance endpoint.
     */
    static internal func makeMaintenanceEp() -> NSXPCInterface {
        let int = NSXPCInterface(with: RendererMaintenanceXPCProtocol.self)

        return int
    }
    
    /// No initialization allowed lol
    private init() {}
}
