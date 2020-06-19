//
//  MakerNotesInfo.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200618.
//

import Foundation

extension CR2Reader {
    /**
     * Information about sensor dimensions and borders
     */
    internal struct SensorInfo: CustomStringConvertible {
        var description: String {
            return String(format: "<Sensor size: %dx%d (%dx%d); border: [%d, %d, %d, %d]>",
                          self.width, self.height, self.effectiveWidth,
                          self.effectiveHeight, self.borderLeft,
                          self.borderTop, self.borderRight, self.borderBottom)
        }

        /// Total sensor width
        var width: Int = 0
        /// Total sensor height
        var height: Int = 0

        /// Effective width
        var effectiveWidth: Int = 0
        /// Effective height
        var effectiveHeight: Int = 0

        /// Number of columns from the left that are a part of the border
        var borderLeft: Int = 0 {
            didSet { self.updateEffectiveSize() }
        }
        /// Number of lines from the top that are a part of the border
        var borderTop: Int = 0 {
            didSet { self.updateEffectiveSize() }
        }
        /// Columns between this and the right side are part of the border
        var borderRight: Int = 0 {
            didSet { self.updateEffectiveSize() }
        }
        /// Lines between this and the last one are a part of the bottom border
        var borderBottom: Int = 0 {
            didSet { self.updateEffectiveSize() }
        }

        /**
         * Recomputes the effective size of the image.
         */
        internal mutating func updateEffectiveSize() {
            self.effectiveWidth = (self.borderRight - self.borderLeft) + 1
            self.effectiveHeight = (self.borderBottom - self.borderTop) + 1
        }
    }
}
