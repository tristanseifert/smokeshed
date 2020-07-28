//
//  TiledImageScaler.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200727.
//

import Foundation
import Metal
import MetalPerformanceShaders

/**
 * Implements scaling of tiled images by reducing tile sizes down to a new size.
 */
public class TiledImageScaler {
    /// Metal device on which the scaling is done
    private var device: MTLDevice! = nil

    // MARK: - Initialization
    /***
     * Initializes a new tiled image scaler for the specified device.
     */
    public init(device: MTLDevice) {
        self.device = device
    }

    // MARK: - Encoding
    /**
     * Scales the image by the given factor.
     */
    public func encode(commandBuffer: MTLCommandBuffer, scale: UInt, input: TiledImage, output: TiledImage) throws {
        precondition(self.device.registryID == commandBuffer.device.registryID, "Command buffer must be on same device")
        // TODO: implement
    }
}
