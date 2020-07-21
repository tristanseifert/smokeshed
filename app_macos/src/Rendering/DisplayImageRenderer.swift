//
//  DisplayImageRenderer.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200719.
//

import Foundation

import Metal

import Smokeshop
import CocoaLumberjackSwift

/**
 * Renders full images for editing into a smaller viewport that is displayed to the user.
 *
 * This is essentially a thin wrapper around the XPC™
 */
internal class DisplayImageRenderer {
    /// Remote object proxy for the renderer
    private var proxy: RendererUserInteractiveXPCProtocol? = nil
    
    // MARK: - Initialization
    /**
     * Given a remote proxy object, create a display image renderer.
     */
    internal init(_ proxy: RendererUserInteractiveXPCProtocol) {
        self.proxy = proxy
    }
    
    /**
     * Release the renderer resources when deallocating.
     */
    deinit {
        if let proxy = self.proxy {
            proxy.destroy()
        }
    }
    
    // MARK: - Viewport
    /**
     * Updates the viewport.
     *
     * - Parameter visible: Rect describing the part of the image that is drawn into the output texture
     * - Parameter callback: Invoked when the viewport has updated, or if something goes wrong.
     */
    func setViewport(_ visible: CGRect, _ callback: @escaping (Result<Void, Error>) -> Void) {
        guard self.proxy != nil else {
            return callback(.failure(Errors.invalidProxy))
        }
        
        // validate args
        guard visible != .zero else {
            return callback(.failure(Errors.invalidViewport))
        }
        
        // pass call to XPC service
        self.proxy!.setViewport(visible) {
            if let err = $0 {
                return callback(.failure(err))
            } else {
                return callback(.success(Void()))
            }
        }
    }
    
    /**
     * Resizes the viewport texture, generating it if not yet existing.
     *
     * - Parameter size: Pixel size of the output texture
     * - Parameter viewport: Rect describing the part of the image that is drawn into the output texture
     */
    func getOutputTexture(_ size: CGSize, viewport: CGRect, _ callback: @escaping(Result<MTLSharedTextureHandle, Error>) -> Void) {
        guard self.proxy != nil else {
            return callback(.failure(Errors.invalidProxy))
        }
        
        // validate args
        guard size != .zero else {
            return callback(.failure(Errors.invalidSize))
        }
//        guard viewport != .zero else {
//            return callback(.failure(Errors.invalidViewport))
//        }
        
        // pass call to XPC service
        self.proxy!.resizeTexture(size: size, viewport: viewport) { err, texture in
            precondition((err != nil) || (texture != nil), "Invalid XPC response")
            
            // did the resize fail?
            if let err = err {
                return callback(.failure(err))
            }
            // did we get a texture handle?
            else if let handle = texture {
                return callback(.success(handle))
            }
        }
    }
    
    // MARK: - Drawing
    /**
     * Forces the renderer to update the contents of the texture.
     *
     * - Parameter callback: Invoked when the redraw operation fails or completes.
     */
    func redraw(_ callback: @escaping (Result<Void, Error>) -> Void) {
        guard self.proxy != nil else {
            return callback(.failure(Errors.invalidProxy))
        }
        
        // call through to XPC service
        self.proxy!.redraw() { err in
            // did the drawing fail?
            if let err = err {
                return callback(.failure(err))
            }
            // drawing succeeded
            else {
                return callback(.success(Void()))
            }
        }
    }
    
    /**
     * Updates the renderer to display the provided image.
     *
     * All adjustments currently applied to the image are serialized and sent to the rendering service. The result is drawn into the
     * output texture based on the viewport.
     *
     * - Note: This method does not observe the image for changes. You have to handle this yourself.
     */
    internal func setImage(_ library: LibraryBundle, _ image: Image, _ callback: @escaping(Result<Void, Error>) -> Void) {
        // lol ya feel
        return callback(.success(Void()))
    }
    
    /**
     * Sets the render descriptor to use in rendering.
     *
     * - Parameter callback: Invoked once the render descriptor is set, or if there was an error validating it.
     */
    private func setRenderDescriptor(_ descriptor: [AnyHashable: Any], _ callback: @escaping (Result<Void, Error>) -> Void) {
        guard self.proxy != nil else {
            return callback(.failure(Errors.invalidProxy))
        }
        
        // call through to XPC service with the descriptor
        self.proxy!.setRenderDescriptor(descriptor) {
            if let err = $0 {
                return callback(.failure(err))
            } else {
                return callback(.success(Void()))
            }
        }
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// The proxy object is invalid.
        case invalidProxy
        
        /// The size of the texture is invalid
        case invalidSize
        /// The specified viewport is invalid
        case invalidViewport
    }
}
