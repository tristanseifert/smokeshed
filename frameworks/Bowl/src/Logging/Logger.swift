//
//  GlobalLogger.swift
//  Bowl (macOS)
//
//  🌍🌎🌏 globalize that shit 🌏🌎🌍
//
//  Created by Tristan Seifert on 20200605.
//

import CocoaLumberjackSwift

/**
 * The global logger is responsible for setting up the CocoaLumberjack implementation, as well as thinly
 * wrapping its log functions.
 */
public class Logger {
    /**
     * Initializes the logger. This must be called once before any logging takes place.
     */
    public static func setup() {
        // use the OS logger endpoint
        DDLog.add(DDOSLogger.sharedInstance)
        
        // log to files
    }
}
