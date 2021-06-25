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
    public static func setup(component: ContainerHelper.Component?) {
        // use the OS logger endpoint
        DDLog.add(DDOSLogger.sharedInstance)
        
        // create logfile directory if required
        var logsUrl = ContainerHelper.groupLogs
        
        if let component = component {
            logsUrl = ContainerHelper.groupAppLogs(component: component)
        }
        
        let fm = FileManager.default
        if !fm.fileExists(atPath: logsUrl.path) {
            do {
                try fm.createDirectory(at: logsUrl,
                                       withIntermediateDirectories: true,
                                       attributes: nil)
            } catch {
                DDLogError("Failed to create logs url '\(logsUrl)': \(error)")
            }
        }
        
        // set up the file logger: rotate once a week, keep 8 weeks
        let manager = DDLogFileManagerDefault(logsDirectory: logsUrl.path)
        manager.maximumNumberOfLogFiles = 8
        
        let fileLogger = DDFileLogger(logFileManager: manager)
        fileLogger.rollingFrequency = TimeInterval(3600 * 24 * 7)
        fileLogger.maximumFileSize = 0
        
        DDLog.add(fileLogger)
    }
    
    /**
     * Convenience wrapper for setup without a component (for main app and tests)
     */
    public static func setup() {
        Self.setup(component: nil)
    }
}
