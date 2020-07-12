//
//  Data+ReadHelpers.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200615.
//

import Foundation

/**
 * Provides some Cool and Good™ helpers to extract integer values from a data object while respecting
 * endianness.
 */
extension Data {
    /**
     * Reads a given type from the internal buffer taking into account endianness.
     */
    internal func readEndian<T>(_ offset: Int, _ endianness: ByteOrder) -> T where T: EndianConvertible {
        let v: T = self.read(offset)

        switch endianness {
            case .little:
                return T(littleEndian: v)
            case .big:
                return T(bigEndian: v)
        }
    }

    /**
     * Reads the given type from the internal data buffer at the provided offset.
     */
    internal func read<T>(_ offset: Int) -> T where T: ExpressibleByIntegerLiteral {
        var v: T = 0
        let len = MemoryLayout<T>.size

        _ = Swift.withUnsafeMutableBytes(of: &v, {
            self.copyBytes(to: $0, from: offset..<(offset+len))
        })

        return v
    }

    /**
     * Returns a subset of the file's data.
     */
    internal func readRange(_ range: Range<Data.Index>) -> Data {
        return self.subdata(in: range)
    }

    /**
     * Endianness of a value to read
     */
    enum ByteOrder {
        /// Interpret data as little-endian
        case little
        /// Interpret data as big-endian
        case big
    }
}

/// Provide initializers for converting from big/little endian types
public protocol EndianConvertible: ExpressibleByIntegerLiteral {
    init(littleEndian: Self)
    init(bigEndian: Self)
}

extension Int16: EndianConvertible {}
extension UInt16: EndianConvertible {}
extension Int32: EndianConvertible {}
extension UInt32: EndianConvertible {}

