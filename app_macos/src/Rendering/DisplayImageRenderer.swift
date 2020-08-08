//
//  DisplayImageRenderer.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200719.
//

import Foundation

import Metal

import Waterpipe
import Smokeshop
import CocoaLumberjackSwift

/**
 * Renders full images for editing into a smaller viewport that is displayed to the user.
 *
 * This is essentially a thin wrapper around the XPC™
 */
internal class DisplayImageRenderer {
    /// Remote object proxy for the renderer
    private var proxy: RendererUserInteractiveXPCProtocol! = nil
    
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
    internal func setImage(_ library: LibraryBundle, _ image: Image, _ callback: @escaping(Result<TiledImage, Error>) -> Void) {
        do {
            let desc = try RenderDescriptor(library: library, image: image)
            self.setRenderDescriptor(desc, callback)
        } catch {
            return callback(.failure(error))
        }
    }
    
    /**
     * Sets the render descriptor to use in rendering.
     *
     * - Parameter callback: Invoked once the render descriptor is set, or if there was an error validating it.
     */
    private func setRenderDescriptor(_ descriptor: RenderDescriptor, _ callback: @escaping (Result<TiledImage, Error>) -> Void) {
        guard self.proxy != nil else {
            return callback(.failure(Errors.invalidProxy))
        }
        
        // call through to XPC service with the descriptor
        self.proxy!.setRenderDescriptor(descriptor) { err, archive in
            do {
                // throw error if non-nil
                if let err = err {
                    throw err
                }
                
                // try to decode the tiled image
                guard let archive = archive,
                      let image = archive.toTiledImage() else {
                    throw Errors.failedToDecodeTiledImageArchive
                }
                
                return callback(.success(image))
            } catch {
                return callback(.failure(error))
            }
        }
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// The proxy object is invalid.
        case invalidProxy
        
        /// The size of the texture is invalid
        case invalidSize
        /// The tiled image could not be decoded.
        case failedToDecodeTiledImageArchive
    }
}

extension RenderDescriptor {
    /**
     * Initializes a render descriptor based on a particular image.
     */
    public convenience init(library: LibraryBundle, image: Image) throws {
        self.init()
        
        // get the image and library urls
        self.urlRelativeBase = library.url
        guard let url = image.getUrl(relativeTo: self.urlRelativeBase) else {
            throw Errors.invalidImageUrl
        }
        self.url = url
        
        // create bookmark for library
        var relinquish = self.urlRelativeBase!.startAccessingSecurityScopedResource()
    
        let bm = try self.urlRelativeBase!.bookmarkData(options: [.minimalBookmark],
                                                       includingResourceValuesForKeys: nil,
                                                       relativeTo: nil)
        self.urlRelativeBaseBookmark = bm
    
        if relinquish {
            self.urlRelativeBase!.stopAccessingSecurityScopedResource()
        }
        
        // create bookmark for the image url
        relinquish = url.startAccessingSecurityScopedResource()
        
        self.urlBookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: self.urlRelativeBase)
        
        if relinquish {
            url.stopAccessingSecurityScopedResource()
        }
    }
    
    enum Errors: Error {
        /// Image url is invalid
        case invalidImageUrl
    }
}
