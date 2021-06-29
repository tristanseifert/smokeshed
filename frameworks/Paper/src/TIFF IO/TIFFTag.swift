//
//  TIFFTag.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation

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
        private(set) weak internal var directory: TIFFReader.IFD?

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
            let cfg = ifd.file!.config

            // read the data type
            let id: UInt16 = ifd.file!.readEndian(off+Self.idOffset)
            let rawType: UInt16 = ifd.file!.readEndian(off+Self.typeOffset)
            let count: UInt32 = ifd.file!.readEndian(off+Self.countOffset)

            let type = TagDataType(rawValue: rawType)

            if let type = type {
                switch type {
                    // unsigned integer types
                    case .byte, .short, .long:
                        // single count
                        if count == 1 {
                            // check for the sub-IFD override
                            if type == .long && cfg.subIfdUnsignedOverrides.contains(id) {
                                return try TagSubIfd(ifd, fileOffset: off)
                            } else {
                                return try TagUnsigned(ifd, fileOffset: off)
                            }
                        }
                        // multiple entries
                        else {
                            return try TagUnsignedArray(ifd, fileOffset: off)
                        }

                    // string
                    case .string:
                        return try TagString(ifd, fileOffset: off)

                    // rational (fraction)
                    case .rational:
                        // single rational value
                        if count == 1 {
                            return try TagRational<UInt32>(ifd, fileOffset: off)
                        }
                        // array of rational values
                        else {
                            return try TagRationalArray<UInt32>(ifd, fileOffset: off)
                    }
                    // signed rational (fraction)
                    case .signedRational:
                        if count == 1 {
                            return try TagRational<Int32>(ifd, fileOffset: off)
                        }
                        else {
                            return try TagRationalArray<Int32>(ifd, fileOffset: off)
                    }

                    // pointer to sub-IFDs
                    case .subIfd:
                        return try TagSubIfd(ifd, fileOffset: off)

                    // untyped byte array
                    case .byteSeq:
                        if cfg.subIfdByteSeqOverrides.contains(id) {
                            return try TagSubIfd(ifd, fileOffset: off, false, single: true)
                        } else {
                            return try TagByteSeq(ifd, fileOffset: off)
                        }
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
            var bytes: Data!
            
            // for 4 or less bytes, the offset field contains the data
            if self.count <= 4 {
                let start = Int(self.fileOffset + Self.dataOffset)
                let end = start + Int(self.count)
                bytes = self.directory!.file!.readRange(start..<end)
            }
            // otherwise, read subdata
            else {
                // reads the raw bytes
                let start = Int(self.offsetField)
                let end = start + Int(self.count)
                bytes = self.directory!.file!.readRange(start..<end)
            }
            
            // strip the last zero byte
            if bytes[bytes.count-1] == 0x00 {
                bytes = bytes.subdata(in: 0..<(bytes.count-1))
            }
                
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
                    let v: UInt8 = self.directory!.file!.read(offset)
                    return UInt32(v)
                case .short:
                    let v: UInt16 = self.directory!.file!.readEndian(offset)
                    return UInt32(v)
                case .long:
                    let v: UInt32 = self.directory!.file!.readEndian(offset)
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
            return String(format: "Tag %04x <field width: %d, unsigned: %u>",
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
            if self.value.count < 50 {
                return String(format: "Tag %04x <field width: %d, unsigned array: [%@]>",
                              self.id, self.originalFieldWidth.rawValue,
                              self.value.map(String.init).joined(separator: ", "))
            } else {
                return String(format: "Tag %04x <field width: %d, unsigned array: %d items]>",
                              self.id, self.originalFieldWidth.rawValue,
                              self.value.count)
            }
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

    // MARK: - Rational
    /**
     * Base type for rational tags
     */
    public class BaseTagRational<T>: BaseTag where T: FractionType {
        /**
         * Rational value representation
         */
        public struct Fraction: CustomStringConvertible {
            /// Debug string representation
            public var description: String {
                return String(format: "%d/%d (%f)", Int(self.numerator),
                              Int(self.denominator), self.value)
            }

            /// Numerator
            fileprivate(set) public var numerator: T = 0
            /// Denominator
            fileprivate(set) public var denominator: T = 0

            /// Calculated double value
            public var value: Double {
                return Double(numerator) / Double(denominator)
            }
        }

        /**
         * Reads a rational value from the given file offset.
         */
        fileprivate func readRational(_ offset: Int) throws -> Fraction {
            var frac = Fraction()

            let f = self.directory!.file!

            frac.numerator = f.readEndian(offset + self.numeratorOffset)
            frac.denominator = f.readEndian(offset + self.denominatorOffset)

            return frac
        }


        /// Location of the numerator relative to the tag data chunk
        fileprivate let numeratorOffset: Int = 0
        /// Location of the denominator relative to the tag data chunk
        fileprivate let denominatorOffset: Int = 4

        /// Size of a single rational value
        fileprivate let rationalSize: Int = 8
    }

    /**
     * TIFF tag representing a rational value, defined by a numerator and denominator. A convenience for
     * getting the value as a double is provided.
     */
    public final class TagRational<T>: BaseTagRational<T> where T: FractionType {
        /// Rational value
        private(set) public var rational = Fraction()

        /// Numerator
        public var numerator: T {
            return rational.numerator
        }
        /// Denominator
        public var denominator: T {
            return rational.denominator
        }

        /// Calculated double value
        public var value: Double {
            return rational.value
        }

        /// Debug description
        public override var description: String {
            return String(format: "Tag %04x <rational: %@>", self.id,
                          String(describing: self.rational))
        }

        /**
         * Creates a rational value tag.
         */
        internal override init(_ ifd: IFD, fileOffset off: Int) throws {
            try super.init(ifd, fileOffset: off)

            // read numerator/denominator
            let start = Int(self.offsetField)
            self.rational = try self.readRational(start)
        }
    }

    /**
     * A TIFF tag containing an array of rational values.
     */
    public final class TagRationalArray<T>: BaseTagRational<T> where T: FractionType {
        /// Array of fraction values
        private(set) public var value: [Fraction] = []

        /// Debug description
        public override var description: String {
            if self.value.count < 50 {
                return String(format: "Tag %04x <rational array: [%@]>",
                              self.id,
                              self.value.map(String.init).joined(separator: ", "))
            } else {
                return String(format: "Tag %04x <rational array: %d items]>",
                              self.id, self.value.count)
            }
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
                let offset = dataStart + (i * 8)
                self.value.append(try self.readRational(offset))
            }
        }
    }

    // MARK: - Sub-IFD
    /**
     * TIFF tag pointing to a linked list of IFDs, similarly to how the TIFF header points to an IFD. This allows
     * images to contain arbitrary sub-IFDs.
     */
    public final class TagSubIfd: BaseTag {
        /// IFDs pointed to by thie value
        private(set) public var value: [IFD] = []

        /// Debug description
        public override var description: String {
            return String(format: "Tag %04x <ifds: %@>", self.id, self.value)
        }


        /**
         * Creates a sub-IFD value tag. The offset pointer contains the file offset to the first IFD object; the
         * remaining IFDs are discovered by following the "next IFD" pointer in this first object. The count
         * value must match the actual number of IFDs discovered.
         */
        internal init(_ ifd: IFD, fileOffset off: Int, _ validate: Bool, single: Bool) throws {
            try super.init(ifd, fileOffset: off)

            // decode all IFDs, starting with the first one
            var offset: Int? = Int(self.offsetField)

            while let i = offset {
                offset = try self.readIfd(ifd, from: i, isSingle: single)
            }

            // ensure count matches
            if validate && ifd.file!.config.subIfdEnforceCount {
                if self.value.count != Int(self.count) {
                    throw TagError.countMismatch(expected: Int(self.count),
                                                 actual: self.value.count)
                }
            }
        }

        override convenience init(_ ifd: TIFFReader.IFD, fileOffset off: Int) throws {
            try self.init(ifd, fileOffset: off, true, single: false)
        }

        /**
         * Decodes a single IFD at the given address, and appends it to our values array.
         */
        private func readIfd(_ parent: IFD, from: Int, isSingle: Bool) throws -> Int? {
            // create the IFD
            let ifd = try IFD(inFile: parent.file!, from, index: self.value.count, single: isSingle)
            try ifd.decode()

            self.value.append(ifd)

            // return the file offset of the next one
            return ifd.nextOff
        }

        enum TagError: Error {
            /// The number of actually decoded IFDs did not match the count field.
            case countMismatch(expected: Int, actual: Int)
        }
    }

    // MARK: - Byte sequence
    /**
     * TIFF tag pointing to untyped byte data.
     */
    public final class TagByteSeq: BaseTag {
        /// Data pointed to by this tag
        private(set) public var value: Data = Data()

        /// Debug description
        public override var description: String {
            return String(format: "Tag %04x <bytes: %@>", self.id,
                          String(describing: self.value))
        }

        /**
         * Initializes a byte sequence tag.
         */
        internal override init(_ ifd: IFD, fileOffset off: Int) throws {
            try super.init(ifd, fileOffset: off)

            // more than four bytes, the value is a data pointer
            if self.count > 4 {
                let start = Int(self.offsetField)
                let end = start + Int(self.count)
                self.value = self.directory!.file!.readRange(start..<end)
            }
            // four or less bytes, read directly from the data offset field
            else {
                let start = Int(self.fileOffset + Self.dataOffset)
                let end = start + Int(self.count)
                self.value = self.directory!.file!.readRange(start..<end)
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

        /// Rational number (two 32-bit values representing a fraction's numerator and denominator)
        case rational = 5
        /// Signed rational number
        case signedRational = 10

        /// Untyped byte sequence
        case byteSeq = 7

        /// Sub-IFD
        case subIfd = 13
    }
}

/// Type for a rational IFD tag's fraction value
public protocol FractionType: EndianConvertible, BinaryInteger {}

extension UInt16: FractionType {}
extension Int16: FractionType {}
extension UInt32: FractionType {}
extension Int32: FractionType {}
