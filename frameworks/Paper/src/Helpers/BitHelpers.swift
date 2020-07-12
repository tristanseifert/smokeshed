//
//  BitHelpers.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200616.
//

import Foundation

extension FixedWidthInteger {
    /// Reverses the bits in the integer
    var bitSwapped: Self {
        var v = self
        var s = Self(v.bitWidth)

        precondition(s.nonzeroBitCount == 1, "Bit width must be a power of two")

        var mask = ~Self(0)
        repeat  {
            s = s >> 1
            mask ^= mask << s
            v = ((v >> s) & mask) | ((v << s) & ~mask)
        } while s > 1
        return v
    }
}
