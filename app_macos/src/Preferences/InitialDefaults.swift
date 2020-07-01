//
//  InitialDefaults.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200626.
//

import Foundation

import Bowl
import CocoaLumberjackSwift

/**
 * Handles registration of initial user defaults values across all suites.
 */
internal class InitialDefaults {
    // MARK: - Public interface
    /**
     * Registers the initial values for all user defaults domains.
     */
    internal static func register() {
        // try to read the defaults
        guard let defaults = NSDictionary(contentsOf: Self.defaultsUrl) else {
            DDLogError("Failed to load defaults from '\(Self.defaultsUrl)'")
            return
        }
        
        // register the shared defaults
        let standard = defaults["standard"] as! [String: Any]
        UserDefaults.standard.register(defaults: standard)
        
        // thumb service defaults
        let thumb = defaults["thumb"] as! [String: Any]
        UserDefaults.thumbShared.register(defaults: thumb)
        
        // register default thumb path if required
        if UserDefaults.thumbShared.object(forKey: "thumbStorageUrl") == nil {
            let thumbDir = ContainerHelper.groupAppCache(component: .thumbHandler)
            let bundleUrl = thumbDir.appendingPathComponent("Thumbs.smokethumbs", isDirectory: true)
            UserDefaults.thumbShared.thumbStorageUrl = bundleUrl
        }
    }
    
    // MARK: - Initial values
    /// URL to the defaults plist
    private static var defaultsUrl: URL {
        return Bundle.main.url(forResource: "Defaults", withExtension: "plist")!
    }
}
