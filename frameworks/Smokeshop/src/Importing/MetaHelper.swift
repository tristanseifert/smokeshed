//
//  MetaHelper.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Paper

/**
 * Provides some helpers to extract basic information from an image's metadata dictionary.
 */
internal class MetaHelper {
    /// Metadata reader using ImageIO
    private lazy var defaultReader = ImageIOMetadataReader()

    /**
     * Extracts image metadata from the image at the given URL.
     */
    internal func getMeta(_ image: URL, _ type: UTType) throws -> ImageMeta {
        // CR2 image?
        if type.conforms(to: UTType("com.canon.cr2-raw-image")!) {
            return try self.metaFromCr2(image)
        }
        // generic image type
        else if type.conforms(to: UTType.image) {
            return try self.metaFromImageIo(image)
        }

        // if we get here, no compatible metadata reader was found
        throw MetaError.unsupportedFormat
    }

    // MARK: - Metadata readers
    /**
     * Reads metadata from a Canon RAW (CR2) image
     */
    private func metaFromCr2(_ image: URL) throws -> ImageMeta {
        let reader = try CR2Reader(fromUrl: image, decodeRawData: false,
                                   decodeThumbs: false)
        let image = try reader.decode()
        
        return image.meta!
    }
    
    /**
     * Uses ImageIO to read the metadata from the provided file. This is supported for most image types on
     * the system.
     */
    private func metaFromImageIo(_ image: URL) throws -> ImageMeta {
        return try self.defaultReader.getMetadata(image)
    }

    // MARK: - Helpers
    /**
     * Extracts the orientation from the given image metadata.
     */
    internal func orientation(_ meta: ImageMeta) throws -> Image.ImageOrientation {
        if let orientation = meta.tiff?.orientation {
            let val = CGImagePropertyOrientation(rawValue: orientation.rawValue)

            switch val {
                case .down, .downMirrored:
                    return Image.ImageOrientation.cw180

                case .right, .rightMirrored:
                    return Image.ImageOrientation.cw90

                case .left, .leftMirrored:
                    return Image.ImageOrientation.ccw90

                case .up, .upMirrored:
                    return Image.ImageOrientation.normal

                // TODO: should this be a special value?
                case .none:
                    return Image.ImageOrientation.normal

                default:
                    throw MetaError.unknownOrientation
            }
        }

        // no orientation information in image
        return Image.ImageOrientation.unknown
    }

    // MARK: - Errors
    /**
     * Errors that can take place during metadata processing
     */
    enum MetaError: Error {
        /// The image format is not currently supported
        case unsupportedFormat
        /// The image could not be opened for metadata reading
        case sourceCreateFailed
        /// Metadata could not be retrieved for the image
        case copyPropertiesFailed
        /// Failed to read size information for the image
        case failedToSizeImage
        /// The image orientation is unknown
        case unknownOrientation
    }
}
