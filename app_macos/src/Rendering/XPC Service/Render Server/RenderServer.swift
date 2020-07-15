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
    // MARK: - XPC Interface
    
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
        // TODO: implement
    }
    
    // MARK: Management
    /**
     * Allocates the maintenance endpoint, if needed, and returns a reference to it.
     */
    func getMaintenanceEndpoint(withReply reply: @escaping (NSXPCListenerEndpoint) -> Void) {
        // TODO: implement
    }
}
