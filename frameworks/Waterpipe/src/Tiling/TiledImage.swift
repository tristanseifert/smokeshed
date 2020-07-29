//
//  TiledImage.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200727.
//

import Foundation
import Metal
import MetalPerformanceShaders

import CocoaLumberjackSwift

/**
 * Represents an image to be run through the processing chain, but sliced up into equal sized tiles.
 *
 * Tiled rendering is used to minimize texture size demands and allow scalability to huge images. This does create some extra
 * complication in rendering, though.
 *
 * Each tiled image is backed by a 2D array texture, where each slice is a separate tile.
 */
public class TiledImage {
    /// Device on which the tiled image is stored. The textures are private to the GPU.
    private(set) public var device: MTLDevice! = nil
    /// Size of each tile, in pixels. Tiles are square.
    private(set) public var tileSize: UInt = 0
    /// Original image size
    private(set) public var imageSize: CGSize = .zero

    /// Number of tiles per row 
    public var tilesPerRow: UInt {
        return UInt(ceil(self.imageSize.width / CGFloat(self.tileSize)))
    }

    /// 2D array texture backing this image
    private(set) internal var texture: MTLTexture! = nil
    /// If backed by a temporary image, this is the image.
    private(set) internal var tempImage: MPSImage? = nil

    // MARK: - Initialization
    /**
     * Creates a new tiled image backed by a permanently allocated texture.
     */
    public init?(device: MTLDevice, forImageSized imageSize: CGSize, tileSize: UInt, _ pixelFormat: MTLPixelFormat = .rgba32Float) {
        self.device = device
        self.tileSize = tileSize
        self.imageSize = imageSize

        // attempt to allocate the texture
        let desc = Self.textureDescriptorFor(size: imageSize, tileSize, pixelFormat)
        guard let texture = device.makeTexture(descriptor: desc) else {
            return nil
        }

        self.texture = texture
    }

    /**
     * Creates a tiled image backed by a temporary image.
     *
     * - Parameter readCount: Number of times the tiled image is read from
     */
    public init?(buffer: MTLCommandBuffer, imageSize: CGSize, tileSize: UInt, _ pixelFormat: MTLPixelFormat = .rgba32Float, _ readCount: UInt = 1) {
        self.device = buffer.device
        self.tileSize = tileSize
        self.imageSize = imageSize

        // allocate temporary image based on texture descriptor
        let desc = Self.textureDescriptorFor(size: imageSize, tileSize, pixelFormat)
        let image = MPSTemporaryImage(commandBuffer: buffer, textureDescriptor: desc) 
    
        self.tempImage = image
        self.texture = image.texture
    }

    /**
     * Encodes into the command buffer a series of commands needed to copy the image data out of the provided buffer
     * and into the provided tiled image.
     *
     * - Parameter commandBuffer: Command buffer onto which 0+ compute/blit passes are encoded to copy the image
     * - Parameter imageBuffer: Metal buffer containing input pixel data
     * - Parameter imageSize: Size of the original image in the buffer
     * - Parameter bytesPerRow: Number of bytes per row of pixel data (stride) in the buffer
     * - Parameter pixelFormat: Format of pixel data in the buffer
     * - Parameter destination: Tiled image to receive data (must be the same size)
     *
     * - Throws: If encoding the commands fails, or a precondition isn't met.
     */
    public class func copyBufferToImage(_ commandBuffer: MTLCommandBuffer, _ imageBuffer: MTLBuffer,
            _ imageSize: CGSize, _ bytesPerRow: Int, _ pixelFormat: MTLPixelFormat, _ destination: TiledImage) throws {
        // validate size
        guard imageSize == destination.imageSize else {
            throw Errors.invalidDestinationSize
        }
        
        // TODO: implement
    }
    
    // MARK: Helpers
    /**
     * Returns the texture descripto to hold the data for an image with the given size and pixel format.
     */
    private class func textureDescriptorFor(size: CGSize, _ tileSize: UInt, _ format: MTLPixelFormat) -> MTLTextureDescriptor {
        let numTiles = Self.entriesForImage(size, tileSize)

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: Int(tileSize),
                                                            height: Int(tileSize), mipmapped: false)
        desc.textureType = .type2DArray
        desc.arrayLength = Int(numTiles)
        desc.storageMode = .private
        desc.allowGPUOptimizedContents = true
        desc.usage = [.shaderRead, .shaderWrite]

        return desc
    }

    /**
     * Calculates the number of array entries in a texture for a given image and tile size.
     */
    private class func entriesForImage(_ size: CGSize, _ tileSize: UInt) -> UInt {
        let cols = UInt(ceil(size.width / CGFloat(tileSize)))
        let rows = UInt(ceil(size.height / CGFloat(tileSize)))
        let numTiles = cols * rows
        
        precondition(numTiles <= 2048) // metal limitation on array length
        DDLogVerbose("Tiles for image sized \(size) (tile size \(tileSize)): \(numTiles)")

        return numTiles
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Size of the destination tiled image is invalid
        case invalidDestinationSize
    }
}
