//
//  RendererXPCProtocol.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200712.
//

import Foundation
import Cocoa
import Metal
import OSLog

import Waterpipe

/**
 * Interface of the object exported by the renderer XPC service
 */
@objc protocol RendererXPCProtocol {
    /**
     * Gets a renderer suitable for user interactive display. Rendering takes place on the specified Metal device.
     *
     * This is the most heavyweight renderer, and is heavily optimized towards user responsiveness rather than accuracy or memory
     * usage.
     *
     * - Note: Using a device other than the one that drives the display on which the view is drawn will incur significant performance
     * penalties due to texture copies required for display.
     *
     * - Parameter deviceRegistryId: The `registryID` value of the `MTLDevice` on which to render.
     * - Parameter error: If non-nil, the error that caused the allocation of the renderer to fail.
     * - Parameter renderer: If non-nil, a reference to the renderer.
     */
    func getDisplayRenderer(_ deviceRegistryId: UInt64, withReply callback: @escaping (_ error: Error?, _ renderer: RendererUserInteractiveXPCProtocol?) -> Void)
    
    /**
     * Creates a renderer that produces bitmaps.
     *
     * This renderer is optimized for performing single-shot renders into bitmaps that will be consumed on the CPU.
     *
     * - Parameter error: If non-nil, the error that caused the allocation of the renderer to fail.
     * - Parameter renderer: If non-nil, a reference to the renderer.
     */
    func getBitmapRenderer(withReply callback: @escaping (_ error: Error?, _ renderer: RendererBitmapXPCProtocol?) -> Void)
    
    /**
     * Create a renderer that writes the resultant image to an on-disk file.
     *
     * For building export flows, this renderer is preferred as data is directly written to file without incurring extra memory or XPC
     * overhead. It's optimized to produce the highest quality output.
     *
     * - Parameter error: If non-nil, the error that caused the allocation of the renderer to fail.
     * - Parameter renderer: If non-nil, a reference to the renderer.
     */
    func getFileRenderer(withReply callback: @escaping (_ error: Error?, _ renderer: RendererFileXPCProtocol?) -> Void)
    
    
    
    /**
     * Gets a reference to the maintenance endpoint.
     *
     * - Parameter endpoint: Connection to use to access the maintenance endpoint.
     */
    func getMaintenanceEndpoint(withReply reply: @escaping (_ endpoint: NSXPCListenerEndpoint) -> Void)
}

/**
 * User-interactive display renderer
 *
 * The resulting image is rendered through a viewport into a texture, which is shared to the app and displayed there. User
 * interactions will update this viewport, while the output texture remains a constant size.
 *
 * Before being usable, you must call `resizeTexture(size:viewport:withReply)` at least once to create the output texture.
 *
 * - Note: This renderer will not update the contents of the output texture until `redraw(withReply:)` is called.
 */
@objc(RendererUserInteractiveXPCProtocol) protocol RendererUserInteractiveXPCProtocol {
    /**
     * Sets the render descriptor describing the render.
     *
     * If the image being drawn doesn't change, the renderer attempts to do as little work as possible by re-using intermediate data
     * from previous renders. Otherwise, a full re-render is performed.
     *
     * - Parameter descriptor: Render descriptor to use for any subsequent render passes
     * - Parameter error: If non-nil, the render descriptor was not applied because of this error.
     */
    func setRenderDescriptor(_ descriptor: RenderDescriptor, withReply reply: @escaping (_ error: Error?, _ outImage: TiledImage.TiledImageArchive?) -> Void)

    /**
     * Redraws the contents of the output texture.
     *
     * You can observe the progress of the drawing process using `Progress`.
     *
     * - Parameter reply: Callback invoked if an error occurs during rendering, or the render completes successfully.
     * - Parameter error: If non-nil, the error that caused drawing to fail.
     */
    func redraw(withReply reply: @escaping (_ error: Error?) -> Void)
    
    /**
     * Releases all resources allocated by the renderer, including its output texture.
     *
     * You must discontinue use of any resources previously provided by the renderer (such as output textures) prior to making this call,
     * or the results are undefined.
     */
    func destroy()
}

/**
 * Offline bitmap renderer
 *
 * The best GPU (or group of GPUs) is automagically selected by the renderer, but this selection can be influenced by some user
 * settings. Since bitmaps are going to be consumed by the CPU almost exclusively, the Metal device selected may not necessarily be the
 * same device as is displaying the interface.
 */
@objc(RendererBitmapXPCProtocol) protocol RendererBitmapXPCProtocol {
    /**
     * Queues the given render descriptor to be rendered to a bitmap.
     *
     * You can observe the progress of the render using `Progress`.
     *
     * - Parameter descriptor: Render descriptor describing the bitmap to produce.
     * - Parameter error: If non-nil, the error that caused rendering to fail.
     * - Parameter bitmap: If successful, the bitmap that was rendered.
     */
    func render(_ descriptor: RenderDescriptor, withReply reply: @escaping (_ error: Error?, _ bitmap: NSImage?) -> Void)
    
    /**
     * Releases all resources allocated by the renderer.
     */
    func release()
}

/**
 * Export (file) renderer
 *
 * This is a specialization of the bitmap renderer, but instead of sending the output as a bitmap to the app, it's written directly to a file. This
 * allows for much lower overhead if exporting images.
 */
@objc(RendererFileXPCProtocol) protocol RendererFileXPCProtocol {
    /**
     * Queues the given render descriptor to be rendered to a file.
     *
     * You can observe the progress of the render using `Progress`.
     *
     * - Parameter descriptor: Render descriptor describing the image to produce.
     * - Parameter options: Where the output file is written, its format, and any format-specific options.
     * - Parameter error: If non-nil, the error that caused rendering to fail; otherwise, assume success.
     */
    func render(_ descriptor: RenderDescriptor, _ options: [AnyHashable: Any], withReply reply: @escaping (_ error: Error?) -> Void)
    
    /**
     * Releases all resources allocated by the renderer.
     */
    func release()
}

/**
 * String dictionary keys for the XPC service configuration
 */
public enum RendererXPCConfigKey: String {
    /// Whether the GPU for offline rendering is selected automatically
    case autoselectOfflineRenderDevice = "autoselectOfflineRenderDevice"
    /// Registry id of the GPU to use for offline rendering, if not autoselected
    case offlineRenderDeviceId = "offlineRenderDeviceId"
    /// Whether the GPU used for rendering the display view is the same as the one driving the view
    case matchDisplayDevice = "matchDisplayDevice"
    /// Registry id of the GPU to use for display rendering, if not always matching the display device
    case displayRenderDeviceId = "displayRenderDeviceId"
}

/**
 * Defines the interface exposed by the maintenance endpoint.
 */
@objc protocol RendererMaintenanceXPCProtocol {
    /**
     * Gets the current renderer service configuration.
     *
     * - Parameter config: Current render service configuration
     */
    func getConfig(withReply reply: @escaping(_ config: [String: Any]) -> Void)
    
    /**
     * Sets the renderer service configuration.
     *
     * - Parameter config: A dictionary of configuration keys to change
     */
    func setConfig(_ config: [String: Any])
}

/**
 * Render descriptor
 */
@objc(RendererXPCJobDescriptor) public class RenderDescriptor: NSObject, NSSecureCoding {
    fileprivate static var logger = Logger(subsystem: Bundle(for: RenderDescriptor.self).bundleIdentifier!,
                                         category: "RenderDescriptor")
    
    /// We support secure coding, required for XPC
    public static var supportsSecureCoding: Bool = true
    
    /// Should all cached render state be thrown away?
    internal(set) public var discardCaches: Bool = false
    
    /// URL to the image
    internal(set) public var url: URL! = nil
    /// Bookmark data for the image url
    internal var urlBookmark: Data? = nil
    
    /// URL to which the bookmark is relative to
    internal var urlRelativeBase: URL? = nil
    /// Bookmark data for the base url
    internal var urlRelativeBaseBookmark: Data?
    
    public override init() {
        super.init()
    }
    
    /**
     * Encodes the render descriptor into its wire format.
     */
    public func encode(with coder: NSCoder) {
        // encode url data
        if let bookmark = self.urlBookmark {
            coder.encode(bookmark, forKey: "url.bookmark")
            coder.encode(self.urlRelativeBase, forKey: "url.base")
            
            if let data = self.urlRelativeBaseBookmark {
                coder.encode(data, forKey: "url.base.bookmark")
            }
        } else if let url = self.url {
            coder.encode(url, forKey: "url")
        }
        
        // encode some other flags
        coder.encode(self.discardCaches, forKey: "discardCaches")
    }
    
    /**
     * Decodes a render descriptor from its serialized representation.
     */
    public required init?(coder: NSCoder) {
        // attempt to decode the url by resolving the bookmark or just taking the raw url value
        if let bookmark = coder.decodeObject(of: NSData.self, forKey: "url.bookmark") as Data? {
            do {
                // decode base url bookmark or read it
                var base: URL! = coder.decodeObject(of: NSURL.self, forKey: "url.base") as URL?
                
                if let data = coder.decodeObject(of: NSData.self, forKey: "url.base.bookmark") as Data? {
                    // this is just a minimal bookmark
                    do {
                        var isStale: Bool = false
                        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI],
                                          relativeTo: nil, bookmarkDataIsStale: &isStale)
                        base = url
                    } catch {
                        Self.logger.error("Failed to decode base url bookmark data (\(data)): \(error.localizedDescription)")
                        return nil
                    }
                }
                
                self.urlRelativeBase = base
                
                var isStale: Bool = false
                let url = try URL(resolvingBookmarkData: bookmark,
                                  options: [.withoutUI, .withSecurityScope],
                                  relativeTo: base, bookmarkDataIsStale: &isStale)
                self.url = url
            } catch {
                Self.logger.error("Failed to decode url bookmark data (\(bookmark)): \(error.localizedDescription)")
                return nil
            }
        } else if let url = coder.decodeObject(of: NSURL.self, forKey: "url") as URL? {
            self.url = url
        }
        
        // decode flags
        self.discardCaches = coder.decodeBool(forKey: "discardCaches")
        
        // call through to super init
        super.init()
    }
}
