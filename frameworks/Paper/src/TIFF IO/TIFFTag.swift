//
//  TIFFTag.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation

import CocoaLumberjackSwift

extension TIFFReader {
    // MARK: - Base tag
    /**
     * Base tag class; this is reads the tag ID, type, and data length.
     */
    public class BaseTag: CustomStringConvertible {
        /// File offset of the first byte of this tag entry
        private(set) internal var fileOffset: Int

        /// TIFF tag ID
        private(set) public var id: UInt16 = 0
        /// Tag type
        private(set) internal var rawType: UInt16 = 0
        /// Number of elements in the tag
        private(set) internal var count: UInt32 = 0
        /// Raw value read from the offset field
        private(set) internal var offsetField: UInt32 = 0

        /// Data type (if known) as enum
        private(set) fileprivate var type: TagDataType? = nil

        /// Directory containing this tag
        private(set) internal var directory: TIFFReader.IFD

        /// Debug description
        public var description: String {
            return String(format: "Tag %04x <type: %d, count: %d>", self.id,
                          self.rawType, self.count)
        }

        /**
         * Read the tag ID, data type and data length from the tag.
         */
        internal init(_ ifd: IFD, fileOffset off: Int) throws {
            self.directory = ifd
            self.fileOffset = off

            self.id = ifd.file!.readEndian(off)
            self.rawType = ifd.file!.readEndian(off+Self.typeOffset)
            self.count = ifd.file!.readEndian(off+Self.countOffset)
            self.offsetField = ifd.file!.readEndian(off+Self.dataOffset)

            self.type = TagDataType(rawValue: self.rawType)
        }

        /**
         * Creates the appropriate tag type at the given file offset.
         */
        internal class func make(_ ifd: IFD, fileOffset off: Int) throws -> BaseTag {
            // read the data type
            let rawType: UInt16 = ifd.file!.readEndian(off+Self.typeOffset)
            let count: UInt32 = ifd.file!.readEndian(off+Self.countOffset)

            let type = TagDataType(rawValue: rawType)

            if let type = type {
                switch type {
                    // unsigned integer types
                    case .byte, .short, .long:
                        // single count
                        if count == 1 {
                            return try TagUnsigned(ifd, fileOffset: off)
                        }
                        // multiple entries
                        else {
                            return try TagUnsignedArray(ifd, fileOffset: off)
                        }

                    // string
                    case .string:
                        return try TagString(ifd, fileOffset: off)

                    // known, but unimplemented types
                    default:
                        return try TagUnknown(ifd, fileOffset: off)
                }
            }

            // if we get here, data type was not implemented. create unknown tag
            return try TagUnknown(ifd, fileOffset: off)
        }

        enum TagError: Error {
            /// Unknown tag data type
            case unknownDataType(_ type: UInt16)
        }

        /// Offset of the TIFF tag id from the start of the tag
        fileprivate static let idOffset: Int = 0
        /// Offset to the data type field from the start of the tag
        fileprivate static let typeOffset: Int = 2
        /// Offset to the count field from the start of the tag
        fileprivate static let countOffset: Int = 4
        /// Offset to the data content/file offset field from start of tag
        fileprivate static let dataOffset: Int = 8

        /// Total size of a single tag
        internal static let size: Int = 12
    }

    /**
     * A tag with an unsupported (unknown) data type
     */
    internal final class TagUnknown: BaseTag {
        public override var description: String {
            return String(format: "Tag %04x <type: %d, count: %d, off: %08x>",
                          self.id, self.rawType, self.count, self.offsetField)
        }

        internal override init(_ ifd: IFD, fileOffset off: Int) throws {
            try super.init(ifd, fileOffset: off)
        }

    }

    // MARK: - String type
    /**
     * TIFF tag representing a string
     */
    public final class TagString: BaseTag {
        /// String value of this tag
        private(set) public var value: String = ""

        /// Debug description
        public override var description: String {
            return String(format: "Tag %04x <string: \"%@\">", self.id, self.value)
        }

        /**
         * Creates a string tag.
         */
        internal override init(_ ifd: IFD, fileOffset off: Int) throws {
            try super.init(ifd, fileOffset: off)
            try self.readStringBytes()
        }

        /**
         * Reads string bytes.
         */
        private func readStringBytes() throws {
            // reads the raw bytes
            let start = Int(self.offsetField)
            let end = start + Int(self.count)
            let bytes = self.directory.file!.readRange(start..<end)

            // create an ASCII string
            guard let str = String(bytes: bytes, encoding: .ascii) else {
                throw TagError.stringDecodeFailed(bytes)
            }
            self.value = str
        }

        enum TagError: Error {
            /// Failed to convert the string to ASCII
            case stringDecodeFailed(_ bytes: Data)
        }
    }

    // MARK: - Integer types
    /**
     * Base type for unsigned integer tags
     */
    public class BaseTagUnsigned: BaseTag {
        /// Original field size
        public var originalFieldWidth: FieldWidth {
            return FieldWidth(type: self.type!)!
        }

        /**
         * Reads an unsigned value of the original field width from the provided file offset. The value is
         * then upcasted to a 32-bit unsigned integer.
         */
        fileprivate func readUnsigned(from offset: Int) -> UInt32 {
            switch self.originalFieldWidth {
                case .byte:
                    let v: UInt8 = self.directory.file!.read(offset)
                    return UInt32(v)
                case .short:
                    let v: UInt16 = self.directory.file!.readEndian(offset)
                    return UInt32(v)
                case .long:
                    let v: UInt32 = self.directory.file!.readEndian(offset)
                    return v
            }
        }
    }

    /**
     * A TIFF tag representing an unsigned integer; this may be either 8, 16 or 32 bits in size.
     */
    public final class TagUnsigned: BaseTagUnsigned {
        /// Unsigned integer value; this is upcast from smaller types.
        private(set) public var value: UInt32 = 0

        /// Debug description
        public override var description: String {
            return String(format: "Tag %04x <field width: %d, unsigned: %d>",
                          self.id, self.originalFieldWidth.rawValue, self.value)
        }

        /**
         * Creates the unsigned integer tag.
         */
        internal override init(_ ifd: IFD, fileOffset off: Int) throws {
            try super.init(ifd, fileOffset: off)
            self.readValue()
        }

        /**
         * Reads the value as either an 8, 16, or 32-bit unsigned integer.
         */
        private func readValue() {
            let valOff = self.fileOffset + Self.dataOffset
            self.value = self.readUnsigned(from: valOff)
        }
    }

    /**
     * A TIFF tag containing an array of unsigned integer values. Regardless of the actual field width, each
     * value is upcasted to 32-bit integer.
     */
    public final class TagUnsignedArray: BaseTagUnsigned {
        /// Array of integer values
        private(set) public var value: [UInt32] = []

        /// Debug description
        public override var description: String {
            return String(format: "Tag %04x <field width: %d, unsigned array: [%@]>",
                          self.id, self.originalFieldWidth.rawValue,
                          self.value.map(String.init).joined(separator: ", "))
        }

        /**
         * Creates the unsigned integer array tag.
         */
        internal override init(_ ifd: IFD, fileOffset off: Int) throws {
            try super.init(ifd, fileOffset: off)
            try self.readValue()
        }

        /**
         * Reads `count` unsigned integer values from the location pointed to by the offset field.
         */
        private func readValue() throws {
            let dataStart = Int(self.offsetField)

            for i in 0..<Int(self.count) {
                // read a single entry from the offset
                let offset = dataStart + (i * self.originalFieldWidth.rawValue)
                let value = self.readUnsigned(from: offset)
                self.value.append(value)
            }
        }
    }


    // MARK: - Types
    /**
     * Data type widths. Take the raw value to get the width in bytes
     */
    public enum FieldWidth: Int {
        /// 8-bit integer
        case byte = 1
        /// 16-bit integer
        case short = 2
        /// 32-bit integer
        case long = 4

        /**
         * Creates a field width define from an underlying tag type.
         */
        fileprivate init?(type: TagDataType) {
            switch type {
                case .byte:
                    self = .byte
                case .short:
                    self = .short
                case .long:
                    self = .long

                // unknown type
                default:
                    return nil
            }
        }
    }

    /**
     * Different data types represented by a TIFF tag
     */
    fileprivate enum TagDataType: UInt16 {
        /// NULL-terminated ASCII string
        case string = 2

        /// Unsigned 8-bit integer
        case byte = 1
        /// Unsigned 16-bit integer
        case short = 3
        /// Unsigned 32-bit integer
        case long = 4
    }
}
