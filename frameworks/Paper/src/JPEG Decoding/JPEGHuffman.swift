//
//  JPEGHuffman.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200615.
//

import Foundation

import CocoaLumberjackSwift

class JPEGHuffman {
    /// Decoder that is using the decoder
    private weak var jpeg: JPEGDecoder?
    /// Huffman table slots 0-3
    private var tables: [TableSlot: Table] = [:]

    // MARK: - Initialization
    /**
     * Creates a new huffman coder for the provided JPEG decoder.
     */
    init(_ decoder: JPEGDecoder) {
        self.jpeg = decoder
    }

    // MARK: - Marker
    /**
     * Reads Huffman tables out of a DHT marker.
     *
     * Each DHT marker contains one or more Huffman tables; this attempts to read them all. To do this in
     * one pass, we just naiively track however many bytes each table consumed; if there's anything left
     * after the first table, try reading another.
     */
    internal func readTable(atOffset off: Int) throws -> Int? {
        // read the length of the payload and extract it
        let length: UInt16 = self.jpeg!.readEndian(off + Self.offsetLength)
        let tableBytes = Int(length) - 2

        let tableOffset = off + Self.offsetTableStart
        let tableRange = tableOffset..<(tableOffset+tableBytes)
        let chunk = self.jpeg!.readRange(tableRange)

        // decode tables
        let tables = try self.tablesFrom(chunk: chunk)
        self.tables.merge(tables, uniquingKeysWith: { (_, new) in new })

        DDLogVerbose("Decoded tables: \(tables)")

        return (off + 2 + Int(length))
    }

    // MARK: Table parsing
    /**
     * Reads all tables out of the given data payload chunk.
     *
     * This chunk contains all bytes immediately following the length value, up to the number of bytes of
     * payload indicated.
     */
    internal func tablesFrom(chunk inChunk: Data) throws -> [TableSlot: Table] {
        var chunk = inChunk
        var tableBytes = chunk.count

        var tables: [TableSlot: Table] = [:]

        // read all tables until no more data remains
        while tableBytes > 0 {
            let ret = try self.readTableChunk(chunk)
            tables[ret.1] = ret.2

            // get the next chunk
            let bytesRead = ret.0
            if (tableBytes - bytesRead) > 0 {
                chunk = chunk.advanced(by: bytesRead)
            }
            tableBytes -= bytesRead
        }

        // all data _should_ have been consumed
        guard tableBytes == 0 else {
            throw ReadError.invalidLength(read: (chunk.count - tableBytes),
                                          actual: chunk.count)
        }

        return tables
    }

    /**
     * Reads a single table out the provided data chunk. The total number of bytes consumed is returned as
     * well as a reference to the table.
     */
    private func readTableChunk(_ chunk: Data) throws -> (Int, TableSlot, Table) {
        // read table class and destination slot
        let T: UInt8 = chunk.read(Self.offsetT)

        guard (T & 0xF0) == 0x00 else {
            throw ReadError.illegalTc((T & 0xF0) >> 4)
        }
        guard let slot = TableSlot(rawValue: Int(T & 0x0F)) else {
            throw ReadError.illegalTh(T & 0x0F)
        }

        // Read Li[0..15]: counts for each code length
        var Li: [UInt8] = []

        for i in 0..<16 {
            Li.append(chunk.read(Self.offsetLi0 + i))
        }

        // build a Huffman map of (length, code) -> value
        let table = Table()

        var huffvalOff = Self.offsetVij0
        var code: UInt16 = 0

        var huffBytesRead = 0

        for i in 0..<16 {
            for _ in 0..<Li[i] {
                // read a byte from the Vij table
                let val: UInt8 = chunk.read(huffvalOff)
                huffBytesRead = huffBytesRead + 1

                table.addValue(length: (i + 1), code: code, val)

                // value for the next code word
                code = code + 1
                // read the next HUFFVAL byte
                huffvalOff = huffvalOff + 1
            }

            // next code is one bit longer
            code = code << 1
        }

        // bytes read: T + Li[0..15] + mt
        return ((huffBytesRead + 16 + 1), slot, table)
    }

    // MARK: Offsets
    /// Length field (including two bytes for length)
    static let offsetLength: Int = 2
    /// First byte of the first table entry
    static let offsetTableStart: Int = 4

    /// Offset to the Tc and Th fields, relative to the first byte of the table entry
    static let offsetT: Int = 0
    /// Li_0: first of 16 code word lengths
    static let offsetLi0: Int = 1
    /// Vij_0: First entry in the HUFFVAL table
    static let offsetVij0: Int = 17

    // MARK: - Tables
    /**
     * Represents a Huffman table.
     */
    internal class Table: CustomStringConvertible {
        private struct TableKey: Hashable {
            private(set) internal var length: Int
            private(set) internal var code: UInt16

            init(_ length: Int, _ code: UInt16) {
                self.length = length
                self.code = code
            }
        }

        /// Mapping of (length, code) -> value
        private var data: [TableKey: UInt8] = [:]

        /**
         * Creates an uninitialized table. You must call `addValue(length:code:_:)` to populate
         * the table.
         */
        init() { }

        /**
         * Adds a new value to the table.
         */
        internal func addValue(length: Int, code: UInt16, _ value: UInt8) {
            self.data[TableKey(length, code)] = value
        }

        /// Pretty debug print the table
        var description: String {
            var values: String = ""

            // sort keys in ascending order by key
            let sortedKeys = self.data.keys.sorted(by: {
                return ($0.code < $1.code)
            })

            for key in sortedKeys {
                let codeStr = String(key.code, radix: 2)
                let padded = codeStr.leftPadding(toLength: 16, withPad: "0")
                values = values.appendingFormat("%@ (len %2u) -> %02x\n",
                                                padded, key.length,
                                                self.data[key]!)
            }

            values.removeLast()
            return String(format: "<Huffman table: %@>", values)
        }
    }

    // MARK: - Types
    /**
     * A Huffman table slot
     */
    internal enum TableSlot: Int {
        case table0 = 0
        case table1 = 1
        case table2 = 2
        case table3 = 3
    }

    // MARK: - Errors
    /**
     * Failures reading Huffman tables from a DHT marker
     */
    internal enum ReadError: Error {
        /// The Tc (table class) value is illegal; it must be 0 for lossless JPEG
        case illegalTc(_ actual: UInt8)
        /// Invalid Th (table destination slot) value; must be 0-3
        case illegalTh(_ actual: UInt8)
        /// Something weird is going on reading the tables; DHT marker had too much/too little data
        case invalidLength(read: Int, actual: Int)
    }
}



extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        let newLength = self.count
        if newLength < toLength {
            return String(repeatElement(character, count: toLength - newLength)) + self
        } else {
            return self.substring(from: index(self.startIndex, offsetBy: newLength - toLength))
        }
    }
}
