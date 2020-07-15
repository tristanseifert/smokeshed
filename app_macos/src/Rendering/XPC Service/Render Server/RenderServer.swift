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
    /**
     * Instantiates a renderer for the given type and returns a reference to it.
     */
    func dispense(_ type: RendererType, handler: RendererHandlerXPCProtocol, withReply reply: @escaping (Error?, RendererInstanceXPCProtocol?) -> Void) {
        
    }    
}
