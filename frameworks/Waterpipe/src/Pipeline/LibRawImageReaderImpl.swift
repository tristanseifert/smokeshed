//
//  LibRawImageReaderImpl.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200816.
//

import Foundation
import UniformTypeIdentifiers
import Accelerate

import Paper

/**
 * Implements support for reading generic camera raw files, using LibRaw.
 */
internal class LibRawImageReaderImpl: ImageReaderImpl {
    /// URL from which the image file was read
    private(set) var url: URL?
    /// Type of the file read from disk
    private(set) var type: UTType
    
    /// Size of the original image, in pixels
    var size: CGSize {
        return self.reader.size
    }
    
    /// Image reader instance
    private var reader: LibRawReader!
    
    // MARK: - Initialization
    /**
     * Initializes a new CR2 reader with the given file.
     */
    required init(withFileAt url: URL, _ type: UTType) throws {
        self.url = url
        self.type = type
        
        self.reader = try LibRawReader(fromUrl: url, decodeRawData: true, decodeThumbs: true)
    }
    
    // MARK: - Decoding
    typealias ImageBuffer = ImageReader.ImageBuffer
    
    /**
     * Decodes the image and returns a bitmap buffer with the specified pixel format.
     *
     * The decoded CR2 data is kept around memory, including the sensor-native format bitmap. After the first call has decoded
     * the image, further calls just convert that bitmap to the requested format.
     */
    func decode(_ format: ImageReader.BitmapFormat) throws -> ImageBuffer {
        // decode image if needed
        try self.reader.decode()
        
        // lastly, convert to the output pixel format
        switch format {
        case .float32:
            return try self.convert16UTo32F()
        case .float16:
            /// XXX: completely untested lmfao
            fatalError("unimplemented")
        }
    }
    
    /**
     * Converts a 16-bit unsigned buffer into a 32-bit float buffer.
     */
    private func convert16UTo32F() throws -> ImageBuffer {
        guard let inData = self.reader.debayered else {
            throw Errors.invalidDecode
        }
        
        // create descriptor for input buffer
        var inBuf = vImage_Buffer(data: inData.mutableBytes,
                                  height: UInt(self.size.height),
                                   width: UInt(self.size.width) * 4,
                                   rowBytes: Int(self.size.width * 4 * 2))
        
        // allocate output buffer
        let bytes = self.size.height * self.size.width * 4 * 4
        let floatData = NSMutableData(length: Int(bytes))!
        
        var outBuf = vImage_Buffer(data: floatData.mutableBytes,
                                   height: UInt(self.size.height),
                                   width: UInt(self.size.width) * 4,
                                   rowBytes: Int(self.size.width * 4 * 4))
        
        // perform the conversion (assuming 14-bit components on input)
        let err = vImageConvert_16UToF(&inBuf, &outBuf, 0, (1.0 / 65536.0), .zero)
        guard err == kvImageNoError else {
            throw Errors.bufferConvertFailed(err)
        }
        
        return ImageBuffer(data: floatData as Data, bytesPerRow: Int(self.size.width) * 4 * 4,
                           rows: UInt(self.size.height), cols: UInt(self.size.width))
    }
    
    // MARK: - Pipeline support
    /**
     * Adds color space conversion to the start of all pipeline state objects created with this image.
     */
    func insertProcessingElements(_ state: RenderPipelineState) throws {
        
    }
    
    // MARK: - Type identification
    /// Type identifier of CR2 files
    static let uti = UTType("public.camera-raw-image")!
    
    /**
     * Determines if the specified UTI is supported by this reader.
     */
    static func supportsType(_ type: UTType) -> Bool {
        return type.conforms(to: Self.uti)
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// The image failed to decode properly
        case invalidDecode
        /// An error occurred in converting from the raw pixel format to the pipeline pixel format
        case bufferConvertFailed(_ error: vImage_Error)
        /// There is no color space conversion matrix for the given camera model
        case noConversionMatrixFor(_ model: String?)
    }
}
