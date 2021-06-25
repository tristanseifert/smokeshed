//
//  IOSurface+ImageSupport.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200611.
//

import Foundation

import CoreGraphics
import IOSurface

import CocoaLumberjackSwift

/**
 * Extends IOSurface to provide some convenience initializers that can create a surface from various image
 * types.
 */
extension IOSurface {
    /**
     * Creates an IOSurface that contains the given image.
     *
     * TODO: This should really use a 16-bit pixel format (since ProPhoto is so wide) but yes
     */
    public class func fromImage(_ image: CGImage) -> IOSurface? {
        // the surface will be 32bpp, RGBA, ignoring the alpha component
        let surfaceBitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        let props: [IOSurfacePropertyKey: Any] = [
            .width: image.width,
            .height: image.height,
            .bytesPerElement: 4,
            .pixelFormat: kCVPixelFormatType_32RGBA
        ]

        // actually create the surface
        guard let surface = IOSurface(properties: props) else {
            return nil
        }

        // acquire surface lock and get plane address
        surface.lock(options: [], seed: nil)
        let surfaceData = surface.baseAddress

        // create a context with the ProPhoto (ROMM) color space
        guard let colorSpace = CGColorSpace(name: CGColorSpace.rommrgb),
              let ctx = CGContext(data: surfaceData, width: surface.width,
                            height: surface.height,
                            bitsPerComponent: 8,
                            bytesPerRow: surface.bytesPerRow,
                            space: colorSpace,
                            bitmapInfo: surfaceBitmapInfo) else {
            return nil
        }

        // draw the image into it
        let bounds = CGRect(origin: .zero,
                            size: CGSize(width: image.width,
                                         height: image.height))
        ctx.draw(image, in: bounds)

//                ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
//                ctx.fill(bounds)
        
        ctx.flush()

        // unlock the surface
        surface.unlock(options: [], seed: nil)

        return surface
    }
    
    /**
     * Returns an `IOSurfaceRef` for this surface.
     */
    public var surfaceRef: IOSurfaceRef {
        return unsafeBitCast(self, to: IOSurfaceRef.self)
    }
}
