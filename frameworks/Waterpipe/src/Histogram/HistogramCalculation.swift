//
//  HistogramCalculation.swift
//  Waterpipe (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

import Foundation
import Metal
import simd
import CocoaLumberjackSwift

/**
 * Calculates a histogram over an image on the GPU.
 */
public class HistogramCalculator {
    /// Metal device on which we operate
    private(set) public var device: MTLDevice! = nil

    // MARK: - Initialization
    /// Shader code library
    private var library: MTLLibrary!
    /// Compute pass descriptor
    private var state: MTLComputePipelineState!
    /// Command queue for executing on
    private var queue: MTLCommandQueue!
    
    /***
     * Initializes a new tiled image histogram calculator for the specified device.
     */
    public init(device: MTLDevice) throws {
        self.device = device
        
        // create the shader library
        let thisBundle = Bundle(for: type(of: self))
        self.library = try device.makeDefaultLibrary(bundle: thisBundle)
        
        // set up compute pipeline state
        guard let queue = device.makeCommandQueue() else {
            throw Errors.failedResourceAlloc
        }
        self.queue = queue
        
        guard let function = self.library.makeFunction(name: "HistogramRGBY") else {
            throw Errors.failedLoadingFunction
        }
        
        let desc = MTLComputePipelineDescriptor()
        desc.computeFunction = function
        desc.buffers[0].mutability = .immutable
        
        self.state = try device.makeComputePipelineState(descriptor: desc, options: [],
                                                         reflection: nil)
    }
    
    // MARK: - Calculation
    /**
     * Calculates the histogram over the given tiled image's RGB channels, as well as its luminance.
     *
     * - Note: This method runs synchronously on the caller thread.
     */
    public func calculateHistogram(_ image: TiledImage, buckets: UInt = 256) throws -> HistogramData {
        precondition(image.device.registryID == self.device.registryID)
        precondition(buckets >= 1)
        
        // calculate the threadgroup sizes
        let w = self.state.threadExecutionWidth
        let h = self.state.maxTotalThreadsPerThreadgroup / w
        let threadsPerThreadgroup = MTLSize(width: w, height: h, depth: 1)
        let threadsPerGrid = MTLSize(width: Int(image.tileSize), height: Int(image.tileSize),
                                     depth: Int(image.numTiles))
        
        // create uniform and per-tile info buffer
        var uniform = Uniform(buckets: buckets)
        guard let uniformBuf = self.device.makeBuffer(bytes: &uniform,
                                                      length: MemoryLayout<Uniform>.stride) else {
            throw Errors.failedResourceAlloc
        }
        
        // allocate the output buffers
        var output = HistogramData(buckets: buckets)
        
        var outBuffers: [MTLBuffer] = []
        let outBufferLength = MemoryLayout<UInt>.stride * Int(buckets)
        
        for _ in 0..<4 {
            guard let buf = self.device.makeBuffer(length: outBufferLength,
                                                   options: .storageModeShared) else {
                throw Errors.failedResourceAlloc
            }
            
            outBuffers.append(buf)
        }
        
        // create command encoder
        guard let cmdBuffer = self.queue.makeCommandBuffer(),
              let encoder = cmdBuffer.makeComputeCommandEncoder() else {
            throw Errors.failedResourceAlloc
        }
        cmdBuffer.enqueue()
        
        // perform computification
        encoder.setComputePipelineState(self.state)
        encoder.setTexture(image.texture, index: 0)
        
        encoder.setBuffer(uniformBuf, offset: 0, index: 0)
        encoder.setBuffer(image.tileInfoBuffer!, offset: 0, index: 1)
        
        for i in 0..<4 {
            encoder.setBuffer(outBuffers[i], offset: 0, index: (i + 2))
        }
        
        encoder.dispatchThreads(threadsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
        
        // wait for completion
        cmdBuffer.commit()
        cmdBuffer.waitUntilCompleted()
        
        try output.copyFromBuffers(outBuffers)
        
        // done!
        return output
    }
    
    // MARK: - Types
    /**
     * Result of a histogram calculation
     *
     * This contains the raw count values of pixel occurrences for each channel. These can be accessed either as is, or fuckified into
     * normalized 0-1 range, where 1 is the maximum count value across all channels.
     */
    public struct HistogramData {
        /// Number of buckets per channel
        private(set) public var buckets: Int
        
        /// Frequency counts for the red channel
        private(set) public var redData: [UInt] = []
        /// Frequency counts for the green channel
        private(set) public var greenData: [UInt] = []
        /// Frequency counts for the blue channel
        private(set) public var blueData: [UInt] = []
        /// Frequency counts for luminance
        private(set) public var lumaData: [UInt] = []
        
        // MARK: - Initialization
        /**
         * Initializes a new histogram data object with the given number of buckets.
         */
        fileprivate init(buckets: UInt) {
            self.buckets = Int(buckets)
            
            self.redData.reserveCapacity(self.buckets)
            self.greenData.reserveCapacity(self.buckets)
            self.blueData.reserveCapacity(self.buckets)
            self.lumaData.reserveCapacity(self.buckets)
        }
        
        /**
         * Copies data out of the given Metal buffers (in RGBY order) and into this histogram.
         */
        fileprivate mutating func copyFromBuffers(_ buffers: [MTLBuffer]) throws {
            precondition(buffers.count == 4)
            
            // copy the channels
            self.redData = self.bufferToArray(buffers[0])
            self.greenData = self.bufferToArray(buffers[1])
            self.blueData = self.bufferToArray(buffers[2])
            self.lumaData = self.bufferToArray(buffers[3])
        }
        
        /**
         * Reads the contents of a Metal buffer and returns an array of its contents.
         */
        private func bufferToArray(_ buffer: MTLBuffer) -> [UInt] {
            var data = [UInt]()
            data.reserveCapacity(self.buckets)
            
            let bufferPtr = buffer.contents()
            let bufferData = bufferPtr.bindMemory(to: UInt32.self, capacity: self.buckets)
            
            for j in 0..<self.buckets {
                data.append(UInt(bufferData[j]))
            }
            
            return data
        }
        
        // MARK: - Access
        /// Scale factor for the histogram data; this it the largest of the values in the RGB array.
        public var rgbScale: Double {
            let maxes = [self.redData.max()!, self.greenData.max()!, self.blueData.max()!]
            return Double(maxes.max()!)
        }
        
        /// Scale factor for the luminance component of the histogram
        public var yScale: Double {
            return Double(self.lumaData.max()!)
        }
    }
    
    /**
     * Uniform buffer for compute kernel
     */
    private struct Uniform {
        /// Number of buckets in the histogram
        var buckets = UInt()
    }
    
    // MARK: - Errors
    enum Errors: Error {
        /// Call failed because a required resource couldn't be allocated.
        case failedResourceAlloc
        /// Failed to load shader code
        case failedLoadingFunction
        /// A buffer could not be accessed directly
        case failedBufferContents
    }
}
