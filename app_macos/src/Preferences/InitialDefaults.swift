//
//  InitialDefaults.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200626.
//

import Foundation
import OSLog

import Bowl

/**
 * Handles registration of initial user defaults values across all suites.
 */
internal class InitialDefaults {
    fileprivate static var logger = Logger(subsystem: Bundle(for: InitialDefaults.self).bundleIdentifier!,
                                         category: "InitialDefaults")
    
    // MARK: - Public interface
    /**
     * Registers the initial values for all user defaults domains.
     */
    internal static func register() {
        // try to read the defaults
        guard let defaults = NSDictionary(contentsOf: Self.defaultsUrl) else {
            Self.logger.error("Failed to load defaults from '\(Self.defaultsUrl)'")
            return
        }
        
        // register the shared defaults
        let standard = defaults["standard"] as! [String: Any]
        UserDefaults.standard.register(defaults: standard)
    }
    
    // MARK: - Initial values
    /// URL to the defaults plist
    private static var defaultsUrl: URL {
        return Bundle.main.url(forResource: "Defaults", withExtension: "plist")!
    }
}
