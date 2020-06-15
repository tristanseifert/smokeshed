//
//  TIFFReaderConfig.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation

/**
 * Defines the configuration for the TIFF reader when reading files.
 */
public struct TIFFReaderConfig {
    /**
     * Sub-IFD pointer type overrides for unsigned tags
     *
     * Some IFD tags (such as EXIF, 0x8769) may be defined as unsigned fields rather than proper sub-IFD
     * type. Any tags that are a) unsigned long and b) have an ID in this array will be replaced with sub-IFD
     * tags when decoding.
     */
    public var subIfdUnsignedOverrides: [UInt16] = []

    /**
     * Sub-IFD pointer type overrides for byte sequence tags
     *
     * RAW formats often use, for example, the MakerNote EXIF tag (0x927c) to point to a byte sequence
     * (TIFF type 7) that's in actuality a sub-iFD. Tags a) whose ID is in this array, and b) whose type is
     * byte sequence will be replaced with a sub-IFD tag when decoding.
     * Because the TIFF standard mandates that the `count` field for the byte sequence type is the total
     * number of bytes, the sub-IFD decoder does NOT try to validate the total number of IFDs that were
     * decoded by comparing that against the `count` field.
     */
    public var subIfdByteSeqOverrides: [UInt16] = []

    /**
     * Require that the count field on a sub-IFD type tag matches exactly the actual number of IFDs that
     * were discovered by following the "next IFD" pointer. Disabling may help some more… broken file
     * formats to work.
     */
    public var subIfdEnforceCount = true

    // MARK: - Initialization
    /**
     * Initializes a new TIFF reader config.
     */
    public init() {

    }

    // MARK: - Helpers
    /**
     * Default configuration
     */
    public static var standard: TIFFReaderConfig {
        var cfg = TIFFReaderConfig()

        // Tag SubIFD pointing to sub IFDs may be a long
        cfg.subIfdUnsignedOverrides.append(0x014A)

        return cfg
    }
}
