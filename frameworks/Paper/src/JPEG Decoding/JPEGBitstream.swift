//
//  JPEGBitstream.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200616.
//

import Foundation

/**
 * Extension to the standard bitstream that understands JPEG escapes (0xFF00) during stream reading.
 */
internal class JPEGBitstream: Bitstream {
    /**
     * Implement our custom refill behavior.
     */
    internal override func _fillReadBuffer() -> Bool {
        // is the next byte 0xFF?
        if self.data[self.rdOffset] == 0xFF {
            // make sure there is one more byte
            guard (self.rdOffset + 1) < self.data.count else {
                return false
            }

            // is the next byte 0x00?
            if self.data[self.rdOffset + 1] == 0x00 {
                // we found an escaped 0xFF byte; skip past the 0x00 after tho
                self.rdBuf = self.data[self.rdOffset]
                self.rdBufLeft = 8

                self.rdOffset += 2
            }
            // if not 0x00, we found a marker. abort read
            else {
                return false
            }
        }
        // it's not, invoke super behavior
        else {
            return super._fillReadBuffer()
        }

        return true
    }
}
