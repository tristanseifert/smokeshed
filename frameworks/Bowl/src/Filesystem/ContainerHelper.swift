//
//  ContainerHelper.swift
//  Bowl (macOS)
//
//  📦🥪 contain that sand
//
//
//  Created by Tristan Seifert on 20200605.
//

import Foundation
import CocoaLumberjackSwift

/**
 * Provides helpers to work with both the application specific and group container. The app container should
 * be preferred for application caches, logs, and other temporary data; while working data should go into the
 * group container.
 */
public class ContainerHelper {
    /// App group name, this must be hardcoded. lol sorry
    private static let groupName = "8QDQ246B94.SmokeShed"
    
    /// Base URL to the group container
    public static var groupContainer: URL {
        let fm = FileManager.default
        
        // safe to force unwrap since always valid on macOS
        return fm.containerURL(forSecurityApplicationGroupIdentifier: groupName)!
    }
    
    
    
    /// Base URL of the application specific cache directory
    public static var appCache: URL? {
        do {
            return try FileManager.default.url(for: .cachesDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        } catch {
            DDLogError("Failed to get cache dir: \(error)")
            return nil
        }
    }
    
    /// Base URL of the application specific data directory
    public static var appData: URL? {
        do {
            return try FileManager.default.url(for: .applicationSupportDirectory,
                                       in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        } catch {
            DDLogError("Failed to get application support dir: \(error)")
            return nil
        }
    }
}
