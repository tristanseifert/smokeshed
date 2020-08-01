//
//  DebayerTests.swift
//  PaperTests
//
//  Created by Tristan Seifert on 20200621.
//

import XCTest

import Accelerate
import Metal

import Paper
import Bowl

import CocoaLumberjackSwift

class DebayerTests: XCTestCase {
    /**
     * Set up logging before tests run.
     */
    override func setUp() {
        Bowl.Logger.setup()
    }

    // MARK: - Reading tests
    /**
     * Reads and debayers the `birb.cr2` file to collect timing info.
     */
    func testCr2BirbDebayerTiming() {
        measure {
            do {
                let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                          withExtension: "cr2")!

                let reader = try CR2Reader(fromUrl: url, decodeRawData: true, decodeThumbs: true)
                let image = try reader.decode()
                
                // get white balance values
                let wb = image.rawWbMultiplier.map(NSNumber.init)

                DDLogVerbose("Black levels: \(image.rawBlackLevel)")
                DDLogVerbose("WB multipliers: \(wb)")
                
                // attempt debayering
                let bytes = image.visibleImageSize.width * image.visibleImageSize.height * 4 * 3
                let outData = NSMutableData(length: Int(bytes))!
                
                PAPDebayerer.debayer(image.rawValues!, withOutput: outData,
                                     imageSize: image.visibleImageSize, andAlgorithm: 1,
                                     vShift: UInt(image.rawValuesVshift), wbShift: wb,
                                     blackLevel: image.rawBlackLevel as [NSNumber])
                
                // convert to XYZ color space
                var error: NSError? = nil
                PAPColorSpaceConverter.shared().convert(outData,
                                                        withModel: image.meta.cameraModel!,
                                                        size: image.meta.size!,
                                                        andError: &error)
                
                if let err = error {
                    throw err
                }
            } catch {
                DDLogError("Error during test: \(error)")
                XCTAssertNotNil(error, "Error during test")
            }
        }
    }
    
    /**
     * Reads in the `birb.cr2` RAW file once, then attempts to debayer it.
     */
    func testCr2BirbDebayer() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                  withExtension: "cr2")!

        let reader = try CR2Reader(fromUrl: url, decodeRawData: true, decodeThumbs: true)
        let image = try reader.decode()
        
        // get white balance values
        let wb = image.rawWbMultiplier.map(NSNumber.init)

        DDLogVerbose("Black levels: \(image.rawBlackLevel)")
        DDLogVerbose("WB multipliers: \(wb)")
        
        // attempt debayering
        let bytes = image.visibleImageSize.width * image.visibleImageSize.height * 4 * 3
        let outData = NSMutableData(length: Int(bytes))!
        
        PAPDebayerer.debayer(image.rawValues!, withOutput: outData,
                             imageSize: image.visibleImageSize, andAlgorithm: 1,
                             vShift: UInt(image.rawValuesVshift), wbShift: wb,
                             blackLevel: image.rawBlackLevel as [NSNumber])
        
        // convert to XYZ color space
        var error: NSError? = nil
        PAPColorSpaceConverter.shared().convert(outData,
                                                withModel: image.meta.cameraModel!,
                                                size: image.meta.size!,
                                                andError: &error)
        
        if let err = error {
            throw err
        }
        
        // save that shit
        let attach2 = XCTAttachment(data: outData as Data)
        attach2.name = String(format: "debayered")
        attach2.lifetime = .keepAlways
        self.add(attach2)
    }
    
    /**
     * Reads in the `birb.cr2` RAW file once, then attempts to debayer it and color correct it using Metal.
     */
    func testCr2BirbDebayerMetal() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "birb",
                                                  withExtension: "cr2")!

        let reader = try CR2Reader(fromUrl: url, decodeRawData: true, decodeThumbs: true)
        let image = try reader.decode()
        
        // get white balance values
        let wb = image.rawWbMultiplier.map(NSNumber.init)

        DDLogVerbose("Black levels: \(image.rawBlackLevel)")
        DDLogVerbose("WB multipliers: \(wb)")
        
        // attempt debayering
        let bytes = image.visibleImageSize.width * image.visibleImageSize.height * 4 * 2
        let outData = NSMutableData(length: Int(bytes))!
        
        PAPDebayerer.debayer(image.rawValues!, withOutput: outData,
                             imageSize: image.visibleImageSize, andAlgorithm: 1,
                             vShift: UInt(image.rawValuesVshift), wbShift: wb,
                             blackLevel: image.rawBlackLevel as [NSNumber])
        
        // convert from 16 bit unsigned to 32 bit float (assuming 14 bit components)
        let floatData = NSMutableData(length: Int(bytes * 2))!
        
        var inBuf = vImage_Buffer(data: outData.mutableBytes,
                                   height: UInt(image.visibleImageSize.height),
                                   width: UInt(image.visibleImageSize.width) * 4,
                                   rowBytes: Int(image.visibleImageSize.width * 4 * 2))
        
        var outBuf = vImage_Buffer(data: floatData.mutableBytes,
                                   height: UInt(image.visibleImageSize.height),
                                   width: UInt(image.visibleImageSize.width) * 4,
                                   rowBytes: Int(image.visibleImageSize.width * 4 * 4))
        
        let err = vImageConvert_16UToF(&inBuf, &outBuf, 0, (1.0 / 16384.0), .zero)
        XCTAssertEqual(err, kvImageNoError, "Failed to convert to 32 bit float buffer")
        
        // convert to XYZ color space
        let device = MTLCreateSystemDefaultDevice()!
        XCTAssertEqual(device.readWriteTextureSupport, MTLReadWriteTextureTier.tier2)
        
        let queue = device.makeCommandQueue()!
        
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float,
                                                            width: Int(image.visibleImageSize.width),
                                                            height: Int(image.visibleImageSize.height),
                                                            mipmapped: false)
        desc.storageMode = .managed
        desc.usage.insert(.shaderWrite)
        desc.usage.insert(.shaderRead)
        
        let texture = device.makeTexture(descriptor: desc)!
        let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
        texture.replace(region: region, mipmapLevel: 0, withBytes: floatData.bytes,
                        bytesPerRow: desc.width * 4 * 4)
        
        let converter = try MetalColorConverter(device)
        
        let buffer = queue.makeCommandBuffer()!
        buffer.enqueue()
        
        try converter.encode(buffer, input: texture, output: nil,
                             modelName: image.meta.cameraModel!)
        
        // ensure texture is synced
        let encoder = buffer.makeBlitCommandEncoder()!
        encoder.synchronize(resource: texture)
        encoder.endEncoding()
        
        // invoke buffer
        buffer.commit()
        buffer.waitUntilCompleted()
        
        XCTAssertNil(buffer.error, "Compute buffer failed: \(buffer.error!)")
        
        // read texture out
        let texOutData = NSMutableData(length: Int(bytes * 2))!
        texture.getBytes(texOutData.mutableBytes, bytesPerRow: desc.width*4*4, from: region,
                         mipmapLevel: 0)
                
        // save that shit
        let attach2 = XCTAttachment(data: texOutData as Data)
        attach2.name = String(format: "metal_converted")
        attach2.lifetime = .keepAlways
        self.add(attach2)
    }
    
    /**
     * Reads in the `meow.cr2` RAW file once, then attempts to debayer it.
     */
    func testCr2MeowDebayer() throws {
        let url = Bundle(for: type(of: self)).url(forResource: "meow",
                                                  withExtension: "cr2")!

        let reader = try CR2Reader(fromUrl: url, decodeRawData: true, decodeThumbs: true)
        let image = try reader.decode()
        
        // get white balance values
        let wb = image.rawWbMultiplier.map(NSNumber.init)

        DDLogVerbose("Black levels: \(image.rawBlackLevel)")
        DDLogVerbose("WB multipliers: \(wb)")
        
        // attempt debayering
        let bytes = image.visibleImageSize.width * image.visibleImageSize.height * 4 * 3
        let outData = NSMutableData(length: Int(bytes))!
        
        PAPDebayerer.debayer(image.rawValues!, withOutput: outData,
                             imageSize: image.visibleImageSize, andAlgorithm: 1,
                             vShift: UInt(image.rawValuesVshift), wbShift: wb,
                             blackLevel: image.rawBlackLevel as [NSNumber])
        
        // convert to XYZ color space
        var error: NSError? = nil
        PAPColorSpaceConverter.shared().convert(outData,
                                                withModel: image.meta.cameraModel!,
                                                size: image.meta.size!,
                                                andError: &error)
        
        if let err = error {
            throw err
        }
        
        // save that shit
        let attach2 = XCTAttachment(data: outData as Data)
        attach2.name = String(format: "debayered")
        attach2.lifetime = .keepAlways
        self.add(attach2)
    }

}
