//
//  TiledImage.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200727.
//

import Foundation
import simd
import Metal
import MetalPerformanceShaders

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
    /// Pixel format of the underlying texture
    public var pixelFormat: MTLPixelFormat {
        if let texture = self.texture {
            return texture.pixelFormat
        }
        return .invalid
    }

    /// Number of tiles per row 
    public var tilesPerRow: UInt {
        return UInt(ceil(self.imageSize.width / CGFloat(self.tileSize)))
    }

    /// Information for each of the tiles; each index corresponds to one tile in the texture
    private var tileInfo: [TileInfo] = []
    /// Number of tiles
    public var numTiles: Int {
        return self.tileInfo.count
    }

    /// 2D array texture backing this image
    private(set) internal var texture: MTLTexture! = nil
    /// If backed by a temporary image, this is the image.
    private(set) internal var tempImage: MPSImage? = nil
    
    /// Buffer containing information about each of the tiles
    private(set) internal var tileInfoBuffer: MTLBuffer!

    // MARK: - Initialization
    /**
     * Creates a new tiled image backed by a permanently allocated texture.
     *
     * - Parameter shared: Whether the texture allocated is shareable or not.
     */
    public init?(device: MTLDevice, forImageSized imageSize: CGSize, tileSize: UInt, _ pixelFormat: MTLPixelFormat = .rgba32Float, _ shared: Bool = false) {
        self.device = device
        self.tileSize = tileSize
        self.imageSize = imageSize

        // attempt to allocate the texture
        let desc = Self.textureDescriptorFor(size: imageSize, tileSize, pixelFormat)

        if shared {
            guard let texture = device.makeSharedTexture(descriptor: desc) else {
                return nil
            }
            self.texture = texture
        } else {
            guard let texture = device.makeTexture(descriptor: desc) else {
                return nil
            }
            self.texture = texture
        }

        // calculate tile info and allocate the info buffer
        self.tileInfo = Self.tileInfoForImage(imageSize, tileSize)
        
        guard let infoBuf = try? self.makeTileInfoBuffer() else {
            return nil
        }
        self.tileInfoBuffer = infoBuf
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

        // calculate tile info and allocate the info buffer
        self.tileInfo = Self.tileInfoForImage(imageSize, tileSize)
        
        guard let infoBuf = try? self.makeTileInfoBuffer() else {
            return nil
        }
        self.tileInfoBuffer = infoBuf
    }
    
    /**
     * Creates a tiled image based on an archive form.
     */
    fileprivate init?(archive: TiledImageArchive) {
        self.device = archive.handle.device
        guard let texture = self.device.makeSharedTexture(handle: archive.handle) else {
            return nil
        }
        self.texture = texture
        
        self.tileSize = archive.tileSize
        self.imageSize = archive.imageSize
        
        // decode tile info and allocate the GPU side buffer
        self.tileInfo = archive.tileInfo
        guard let infoBuf = try? self.makeTileInfoBuffer() else {
            return nil
        }
        self.tileInfoBuffer = infoBuf
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
        // set up a blit command encoder
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw Errors.invalidBlitEncoder
        }
        
        // calculate tile counts
        let wholeTilesPerRow = Int(floor(imageSize.width / CGFloat(destination.tileSize)))
        let tilesPerRow = Int(ceil(imageSize.width / CGFloat(destination.tileSize)))
        
        let rows = Int(ceil(imageSize.height / CGFloat(destination.tileSize)))
        let wholeRows = Int(floor(imageSize.height / CGFloat(destination.tileSize)))
        
        // copy data
        for row in 0..<rows {
            for col in 0..<tilesPerRow {
                // get the size to copy (a full tile, except for right and bottom edges
                var copySize = MTLSize(width: Int(destination.tileSize),
                                       height: Int(destination.tileSize),
                                       depth: 1)
                
                if col == (tilesPerRow - 1), wholeTilesPerRow != tilesPerRow {
                    copySize.width = Int(imageSize.width) - (Int(destination.tileSize) * wholeTilesPerRow)
                }
                
                if row == (rows - 1), wholeRows != rows {
                    copySize.height = Int(imageSize.height) - (Int(destination.tileSize) * wholeRows)
                }
                
                // calculate index into texture array and buffer and perform copy
                let index = (row * tilesPerRow) + col
                let bytesPerPixel = Int(destination.tileSize) * 4 * 4
                let offset = (row * Int(destination.tileSize) * bytesPerRow) + (col * bytesPerPixel)
                
                encoder.copy(from: imageBuffer, sourceOffset: offset,
                             sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: 0,
                             sourceSize: copySize, to: destination.texture,
                             destinationSlice: index, destinationLevel: 0,
                             destinationOrigin: MTLOrigin(), options: [])
            }
        }
        
        // ensure texture is updated, then complete encoding
        encoder.synchronize(resource: destination.texture)

        encoder.endEncoding()
    }
    
    // MARK: Helpers
    /**
     * Informs that the image has been read from.
     *
     * This is really just used in case we're backed by a temporary texture.
     */
    internal func didRead() {
        if let temp = self.tempImage as? MPSTemporaryImage {
            temp.readCount -= 1
        }
    }
    
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

        return numTiles
    }

    /**
     * Generates tile metadata for the given size/tile size combination.
     */
    private class func tileInfoForImage(_ size: CGSize, _ tileSize: UInt) -> [TileInfo] {
        var info: [TileInfo] = []

        // calculate tile counts
        let wholeTilesPerRow = Int(floor(size.width / CGFloat(tileSize)))
        let tilesPerRow = Int(ceil(size.width / CGFloat(tileSize)))
        
        let rows = Int(ceil(size.height / CGFloat(tileSize)))
        let wholeRows = Int(floor(size.height / CGFloat(tileSize)))
        
        // copy data
        for row in 0..<rows {
            for col in 0..<tilesPerRow {
                // get the size to copy (a full tile, except for right and bottom edges
                var copySize = MTLSize(width: Int(tileSize),
                                       height: Int(tileSize),
                                       depth: 1)
                
                if col == (tilesPerRow - 1), wholeTilesPerRow != tilesPerRow {
                    copySize.width = Int(size.width) - (Int(tileSize) * wholeTilesPerRow)
                }
                
                if row == (rows - 1), wholeRows != rows {
                    copySize.height = Int(size.height) - (Int(tileSize) * wholeRows)
                }
            
                // create the info struct
                var tileInfo = TileInfo()
                tileInfo.activeRegion = SIMD2<Float>(Float(copySize.width), Float(copySize.height))
                tileInfo.origin = SIMD2<Float>(Float(col * Int(tileSize)),
                                               Float(row * Int(tileSize)))

                info.append(tileInfo)
            }
        }
        
        // done
        return info
    }
    
    /**
     * Creates a buffer of vertex data for the given tiled image.
     */
    private func makeTileInfoBuffer() throws -> MTLBuffer {
        var data: [TileBufferEntry] = []
        
        // add entries for each tile
        for i in 0..<self.numTiles {
            let visibleRegion = self.visibleRegionForTile(i)!
            let visible = SIMD2<Float>(Float(visibleRegion.width), Float(visibleRegion.height))
            
            let origin = self.originForTile(i)!
            let pos = SIMD2<Float>(Float(origin.x), Float(origin.y))
            
            data.append(TileBufferEntry(position: pos, visibleRegion: visible, slice: i)
)
        }
        
        // create a buffer
        let vertexBufSz = data.count * MemoryLayout<TileBufferEntry>.stride
        return self.device.makeBuffer(bytes: data, length: vertexBufSz)!
    }
    
    /**
     * Returns an XPC-friendly representation of a tiled image.
     */
    public func toArchive() -> TiledImageArchive? {
        // the texture backing us MUST be shareable here
        guard self.texture.isShareable else {
            return nil
        }
        
        return TiledImageArchive(image: self)
    }
    
    /**
     * Gets the active region for the given tile.
     */
    public func visibleRegionForTile(_ tile: Int) -> CGSize? {
        guard tile < self.tileInfo.count else {
            return nil
        }
        let info = self.tileInfo[tile]

        return CGSize(width: CGFloat(info.activeRegion.x), height: CGFloat(info.activeRegion.y))
    }
    
    /**
     * Gets the top-left origin for the given tile.
     */
    public func originForTile(_ tile: Int) -> CGPoint? {
        guard tile < self.tileInfo.count else {
            return nil
        }
        let info = self.tileInfo[tile]
        
        return CGPoint(x: CGFloat(info.origin.x), y: CGFloat(info.origin.y))
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Size of the destination tiled image is invalid
        case invalidDestinationSize
        /// Failed to create a blit command encoder
        case invalidBlitEncoder
    }

    // MARK: - Types
    /**
     * Entry in the tile "tile info buffer"; this contains an entry for each tile (slice) of the texture, defining some information about it.
     */
    public struct TileBufferEntry {
        public init(position: SIMD2<Float>, visibleRegion: SIMD2<Float>, slice: Int) {
            self.position = position
            self.visible = visibleRegion
        }
        
        /// Relative image position (x, y) of the tile
        var position = SIMD2<Float>()
        /// Visible region of this slice
        var visible = SIMD2<Float>()
        
        internal static func makeDescriptor() -> MTLVertexDescriptor {
            let vertexDesc = MTLVertexDescriptor()
            
            vertexDesc.attributes[0].format = .float2
            vertexDesc.attributes[0].bufferIndex = 0
            vertexDesc.attributes[0].offset = 0
            
            vertexDesc.attributes[1].format = .float2
            vertexDesc.attributes[1].bufferIndex = 0
            vertexDesc.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
            
            vertexDesc.layouts[0].stride = MemoryLayout<TileBufferEntry>.stride
            
            return vertexDesc
        }
    }
    
    /**
     * Per tile metadata
     */
    fileprivate struct TileInfo: Codable {
        /// Active region of the tile (top left origin)
        var activeRegion = SIMD2<Float>()
        /// Position of the tile origin (top left) relative to the overall image
        var origin = SIMD2<Float>()
    }
    
    /**
     * Serializable object that represents a tiled image, and can be sent via XPC
     */
    @objc(SWPTiledImageArchive) public class TiledImageArchive: NSObject, NSSecureCoding {
        /// Implement secure coding, so we can be sent across XPC boundaries
        public static var supportsSecureCoding: Bool = true

        /// Shared texture handle
        fileprivate var handle: MTLSharedTextureHandle! = nil
        /// Tile info
        fileprivate var tileInfo: [TileInfo] = []
        /// Size of each tile, in pixels. Tiles are square.
        private(set) public var tileSize: UInt = 0
        /// Original image size
        private(set) public var imageSize: CGSize = .zero
        
        /**
         * Encodes info about the tiled image into the archive.
         */
        public func encode(with coder: NSCoder) {
            coder.encode(self.handle, forKey: "textureHandle")
            coder.encode(self.tileSize, forKey: "tileSize")
            coder.encode(self.imageSize, forKey: "imageSize")
            
            // encode using codable
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            if let data = try? encoder.encode(self.tileInfo) {
                coder.encode(data, forKey: "tileInfoData")
            }
        }
        
        /**
         * Creates an archive from a given tiled image.
         */
        fileprivate init?(image: TiledImage) {
            guard let handle = image.texture.makeSharedTextureHandle() else {
                return nil
            }
            self.handle = handle
        
            self.tileInfo = image.tileInfo
            self.tileSize = image.tileSize
            self.imageSize = image.imageSize
        }
        
        /**
         * Decodes the tiled image archive into an object.
         */
        public required init?(coder: NSCoder) {
            // decode the shared texture
            guard let handle = coder.decodeObject(of: MTLSharedTextureHandle.self,
                                                  forKey: "textureHandle") else {
                return nil
            }
            self.handle = handle
        
            // tile and image sizes
            self.tileSize = UInt(coder.decodeInteger(forKey: "tileSize"))
            self.imageSize = coder.decodeSize(forKey: "imageSize")
        
            // tile info
            let decoder = PropertyListDecoder()
            guard let infoData = coder.decodeObject(of: NSData.self,
                                                    forKey: "tileInfoData"),
                  let info = try? decoder.decode([TileInfo].self, from: infoData as Data) else {
                return nil
            }
            self.tileInfo = info
        }
        
        /**
         * Generates a tiled image from the archive.
         */
        public func toTiledImage() -> TiledImage? {
            return TiledImage(archive: self)
        }
    }
}
