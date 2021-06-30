//
//  CR2ImageReaderImpl.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200728.
//

import Foundation
import UniformTypeIdentifiers
import Accelerate
import simd
import Paper

/**
 * Implements support for reading Canon CR2 files.
 */
internal class CR2ImageReaderImpl: ImageReaderImpl {
    /// URL from which the image file was read
    private(set) var url: URL?
    /// Type of the file read from disk
    private(set) var type: UTType
    
    /// Size of the original image, in pixels
    var size: CGSize {
        guard let image = self.image else {
            return .zero
        }
        return image.visibleImageSize
    }
    
    /// CR2 reader instance
    private var reader: CR2Reader!
    /// Decoded raw image
    private var image: CR2Image?
    
    /// Sensor  -> Working color space matrix
    private var sensorMatrix: simd_float3x3?
    
    // MARK: - Initialization
    /**
     * Initializes a new CR2 reader with the given file.
     */
    required init(withFileAt url: URL, _ type: UTType) throws {
        self.url = url
        self.type = type
        
        self.reader = try CR2Reader(fromUrl: url, decodeRawData: true, decodeThumbs: false)
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
        if self.image == nil {
            self.image = try self.reader.decode()
        }
        guard let image = self.image else {
            throw Errors.cr2DecodeFailed
        }
        
        // debayer
        let wb = self.image!.rawWbMultiplier.map(NSNumber.init)
        
        let bytes = image.visibleImageSize.width * image.visibleImageSize.height * 4 * 2
        let outData = NSMutableData(length: Int(bytes))!
        
        PAPDebayerer.debayer(image.rawValues!, withOutput: outData,
                             imageSize: image.visibleImageSize, andAlgorithm: 1,
                             vShift: UInt(image.rawValuesVshift), wbShift: wb,
                             blackLevel: image.rawBlackLevel as [NSNumber])
        
        // lastly, convert to the output pixel format
        switch format {
        case .float32:
            return try self.convert16UTo32F(outData, image)
        case .float16:
            /// XXX: completely untested lmfao
            return try self.convert16UTo16FInPlace(outData, image)
        }
    }
    
    /**
     * Converts a 16-bit unsigned buffer into a 32-bit float buffer.
     */
    private func convert16UTo32F(_ inData: NSMutableData, _ image: CR2Image) throws -> ImageBuffer {
        // create descriptor for input buffer
        var inBuf = vImage_Buffer(data: inData.mutableBytes,
                                   height: UInt(image.visibleImageSize.height),
                                   width: UInt(image.visibleImageSize.width) * 4,
                                   rowBytes: Int(image.visibleImageSize.width * 4 * 2))
        
        // allocate output buffer
        let bytes = image.visibleImageSize.width * image.visibleImageSize.height * 4 * 4
        let floatData = NSMutableData(length: Int(bytes))!
        
        var outBuf = vImage_Buffer(data: floatData.mutableBytes,
                                   height: UInt(image.visibleImageSize.height),
                                   width: UInt(image.visibleImageSize.width) * 4,
                                   rowBytes: Int(image.visibleImageSize.width * 4 * 4))
        
        // perform the conversion (assuming 14-bit components on input)
        let err = vImageConvert_16UToF(&inBuf, &outBuf, 0, (1.0 / 16384.0), .zero)
        guard err == kvImageNoError else {
            throw Errors.bufferConvertFailed(err)
        }
        
        return ImageBuffer(data: floatData as Data, bytesPerRow: Int(image.visibleImageSize.width) * 4 * 4,
                           rows: UInt(image.visibleImageSize.height), cols: UInt(image.visibleImageSize.width))
    }
    
    /**
     * Converts a 16-bit unsigned buffer into a 16-bit float buffer, in place.
     */
    private func convert16UTo16FInPlace(_ inData: NSMutableData, _ image: CR2Image) throws -> ImageBuffer {
        // the same descriptor is used for input and output
        var buf = vImage_Buffer(data: inData.mutableBytes,
                                height: UInt(image.visibleImageSize.height),
                                width: UInt(image.visibleImageSize.width) * 4,
                                rowBytes: Int(image.visibleImageSize.width * 4 * 2))
        
        // perform the conversion (assuming 14-bit components on input)
        let err = vImageConvert_16Uto16F(&buf, &buf, .zero)
        guard err == kvImageNoError else {
            throw Errors.bufferConvertFailed(err)
        }
        
        return ImageBuffer(data: inData as Data, bytesPerRow: Int(image.visibleImageSize.width) * 4 * 2,
                           rows: UInt(image.visibleImageSize.height), cols: UInt(image.visibleImageSize.width))
    }
    
    // MARK: - Pipeline support
    /**
     * Adds color space conversion to the start of all pipeline state objects created with this image.
     */
    func insertProcessingElements(_ state: RenderPipelineState) throws {
        // get the color conversion matrix for the image
        if self.sensorMatrix == nil {
            guard let modelName = self.image?.meta.cameraModel,
                  let colorInfo = CameraColorInfo(),
                  let matrix = try colorInfo.xyzMatrixForModel(modelName) else {
                throw Errors.noConversionMatrixFor(self.image?.meta.cameraModel)
            }
            
            self.sensorMatrix = matrix
        }
        
        // convert from sensor RGB to working color space
        let converter = try MatrixMultiply(state.device, matrix: self.sensorMatrix!)
        state.add(converter, group: .readerImpl)
    }
    
    // MARK: - Type identification
    /// Type identifier of CR2 files
    static let uti = UTType("com.canon.cr2-raw-image")!
    
    /**
     * Determines if the specified UTI is supported by this reader.
     */
    static func supportsType(_ type: UTType) -> Bool {
        return type.conforms(to: Self.uti)
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// The CR2 decode failed for some reason
        case cr2DecodeFailed
        /// An error occurred in converting from the raw pixel format to the pipeline pixel format
        case bufferConvertFailed(_ error: vImage_Error)
        /// There is no color space conversion matrix for the given camera model
        case noConversionMatrixFor(_ model: String?)
    }
}
