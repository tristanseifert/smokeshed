//
//  Bitstream.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200616.
//

import Foundation

/**
 * Provides access to a segment of data as a stream of bits.
 */
internal class Bitstream {
    /// Data backing the stream
    internal var data: Data

    // MARK: - Initialization
    /**
     * Creates a new bitstream with the given backing data.
     */
    internal init(withData data: Data) {
        self.data = data
    }

    // MARK: - Reading
    /// Index into the backing store we're reading from
    internal var rdOffset: Int = 0
    /// Number of bits yet to be read out of the read buffer
    internal var rdBufLeft: Int = 0
    /// Read buffer of one byte
    internal var rdBuf: UInt8 = 0

    /**
     * Reads the next byte from the backing store into the bit read buffer.
     *
     * Override this function to implement custom behavior, such as escaped value handling.
     *
     * - Returns: `true` if the read should succeed; false otherwise.
     */
    internal func _fillReadBuffer() -> Bool {
        self.rdBuf = self.data[self.rdOffset]
        self.rdBufLeft = 8

        self.rdOffset += 1

        return true
    }

    /**
     * Reads the next bit out of the stream.
     *
     * The bit will be in the least significant bit of the returned value.
     */
    internal func readNext() -> UInt8? {
        // refill read buffer if needed
        if self.rdBufLeft == 0, self.rdOffset < self.data.count {
            // if refill wants us to stop reading, honor that
            guard self._fillReadBuffer() else {
                return nil
            }
        }
        // if the buffer is still empty, we've reached the end of the data
        guard self.rdBufLeft > 0 else {
            return nil
        }

        // read the first bit out of the read buffer (MSB)
        let bit = ((self.rdBuf & 0x80) >> 7)

        // advance the read buffer
        self.rdBuf = self.rdBuf << 1
        self.rdBufLeft -= 1

        // return the bit we've read
        return bit
    }

    /**
     * Reads a bit string of the specified length from the stream, if there is enough data remaining.
     *
     * The maximum length of a bit string is 64 bits. If we reach end of stream before the total amount of
     * bits are returned, everything that's been read is discarded.
     *
     * This is horribly slow and could definitely be improved.
     */
    internal func readString(_ length: Int) -> UInt64? {
        // length shouldn't be longer than the return type
        guard length <= 64 else {
            return nil
        }

        // begin reading the string
        var result: UInt64 = 0

        for _ in 0..<length {
            guard let bit = self.readNext() else {
                return nil
            }

            result = result << 1
            result |= UInt64(bit & 0x01)
        }

        // return the created value
        return result
    }
}
