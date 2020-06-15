//
//  TIFFDirectory.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation

extension TIFFReader {
    /**
     * Represents a single image directory (IFD) from a TIFF file.
     */
    public class IFD: CustomStringConvertible {
        // MARK: - Properties
        /// File that owns us
        internal weak var file: TIFFReader?
        /// File offset of the first byte of this IFD
        internal var headerOff: Int
        /// Number of tags, according to the header
        private var numTags: UInt16 = 0

        /// File offset of the next IFD, if any.
        internal var nextOff: Int? = nil

        /// Index of this IFD relative to its parent collection (file or sub-IFD tag)
        private(set) public var index: Int = 0
        /// All tags in this IFD
        private(set) public var tags: [BaseTag] = []

        /// debug string description
        public var description: String {
            return String(format: "IFD: <offset: %d, tags (%d): %@>",
                          self.headerOff, self.tags.count, self.tags)
        }

        // MARK: - Initialization
        /**
         * Creates a new IFD starting at the provided index in the TIFF file. Errors will be thrown if the
         * IFD could not be read.
         */
        internal init(inFile: TIFFReader, _ offset: Int, index: Int) throws {
            // store the file and offset
            self.index = index
            self.file = inFile
            self.headerOff = offset

            // read the header tags
            try self.readHeader()
        }

        /**
         * Decodes the contents of the IFD.
         */
        internal func decode() throws {
            try self.decodeTags()
        }

        // MARK: - Header
        /**
         * Reads the IFD header.
         */
        private func readHeader() throws {
            // read the number of tags
            self.numTags = self.file!.readEndian(self.headerOff)

            // each header is 12 bytes; skip and read next ifd off
            let toSkip = 12 * Int(self.numTags)
            let next: UInt32 = self.file!.readEndian(self.headerOff+2+toSkip)

            if next > self.file!.length {
                throw DecodeError.invalidNextOff(next)
            }
            if next != 0 {
                self.nextOff = Int(next)
            }
        }

        // MARK: - Tags
        /**
         * Decodes each of the tags.
         */
        private func decodeTags() throws {
            let tagBase = self.headerOff + 2

            for i in 0..<self.numTags {
                let tagOff = tagBase + (Int(i) * BaseTag.size)
                let tag = try BaseTag.make(self, fileOffset: tagOff)

                self.tags.append(tag)
            }
        }

        /**
         * Whether a tag with the given type exists.
         */
        public func hasTag(withId id: UInt16) -> Bool {
            return self.tags.contains(where: {
                return ($0.id == id)
            })
        }

        /**
         * Gets a reference to the tag with the specified id.
         */
        public func getTag(byId id: UInt16) -> BaseTag? {
            return self.tags.first(where: {
                return ($0.id == id)
            })
        }

        // MARK: - Errors
        /**
         * IFD decoding errors
         */
        enum DecodeError: Error {
            /// The offset to the next IFD is invalid.
            case invalidNextOff(_ read: UInt32)
        }
    }
}
