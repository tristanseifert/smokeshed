//
//  MetaHelper.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation
import CoreServices
import ImageIO
import CoreGraphics

import CocoaLumberjackSwift

/**
 * Provides some helpers to extract basic information from an image's metadata dictionary.
 */
internal class MetaHelper {
    /// Date formatter for converting EXIF date strings to date
    private var dateFormatter = DateFormatter()

    /**
     * Initializes the metadata helper.
     */
    init() {
        // set up the EXIF date parser
        self.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        self.dateFormatter.dateFormat = "yyyy':'MM':'dd HH':'mm':'ss"
    }

    /**
     * Extracts image metadata from the image at the given URL.
     */
    internal func getMeta(_ image: URL, type uti: String) throws -> [String: AnyObject] {
        // generic image type
        if UTTypeConformsTo(uti as CFString, kUTTypeImage) {
            return try self.metaFromImageIo(image)
        }

        // if we get here, no compatible metadata reader was found
        throw MetaError.unsupportedFormat
    }

    // MARK: - Metadata readers
    /**
     * Uses ImageIO to read the metadata from the provided file. This is supported for most image types on
     * the system.
     */
    private func metaFromImageIo(_ image: URL) throws -> [String: AnyObject] {
        // create an image source
        guard let src = CGImageSourceCreateWithURL(image as CFURL, nil) else {
            throw MetaError.sourceCreateFailed
        }

        // get the properties
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil),
            let meta = props as? [String: AnyObject] else {
                throw MetaError.copyPropertiesFailed
        }

        return meta
    }

    // MARK: - Helpers
    /**
     * Gets the image size (in pixels) from the given metadata.
     */
    internal func size(_ meta: [String: AnyObject]) throws -> CGSize {
        guard let width = meta[kCGImagePropertyPixelWidth as String] as? NSNumber,
            let height = meta[kCGImagePropertyPixelHeight as String] as? NSNumber else {
                throw MetaError.failedToSizeImage
        }

        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    /**
     * Extracts the capture date of the iamge from the exif data.
     */
    internal func captureDate(_ meta: [String: AnyObject]) throws -> Date? {
        if let exif = meta[kCGImagePropertyExifDictionary as String],
            let dateStr = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
            let date = self.dateFormatter.date(from: dateStr) {
            return date
        }

        // failed to get date :(
        return nil
    }

    /**
     * Extracts the orientation from the given image metadata.
     */
    internal func orientation(_ meta: [String: AnyObject]) throws -> Image.ImageOrientation {
        if let orientation = meta[kCGImagePropertyOrientation as String] as? NSNumber {
            let val = CGImagePropertyOrientation(rawValue: orientation.uint32Value)

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
