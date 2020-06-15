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
     * Sub-IFD pointer type overrides
     *
     * Some IFD tags (such as EXIF, 0x8769) may be defined as unsigned fields rather than proper sub-IFD
     * type. Any tags that are a) unsigned and b) have an ID in this array will be replaced with sub-IFD tags
     * when decoding.
     */
    public var subIfdTypeOverrides: [UInt16] = []

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
        cfg.subIfdTypeOverrides.append(0x014A)

        return cfg
    }
}
