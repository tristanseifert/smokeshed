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
    public static let groupName = "8QDQ246B94.me.tseifert.SmokeShed"
    
    /// Base URL to the group container
    public static var groupContainer: URL {
        let fm = FileManager.default
        
        // safe to force unwrap since always valid on macOS
        return fm.containerURL(forSecurityApplicationGroupIdentifier: groupName)!
    }
    /// Application support directory for group container
    public static var groupAppData: URL {
        return self.groupContainer.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
    }
    /// Cache for group container
    public static var groupCache: URL {
        return self.groupContainer.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
    }
    /// Group logs directory
    public static var groupLogs: URL {
        return self.groupContainer.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }
    
    /**
     * Returns the group container url for the given sub-component.
     *
     * The container name is formed by appending the base group name, with a dot, then the specified
     * sub-component name.
     */
    public static func groupContainer(component: Component) -> URL {
        let fm = FileManager.default
        return fm.containerURL(forSecurityApplicationGroupIdentifier: Self.groupName)!
    }
    
    /**
     * Returns the group app data url for the given sub-component.
     */
    public static func groupAppData(component: Component) -> URL {
        let url = Self.groupContainer(component: component)
        return url.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(component.rawValue, isDirectory: true)
    }
    
    /**
     * Returns the group caches url for the given sub-component.
     */
    public static func groupAppCache(component: Component) -> URL {
        let url = Self.groupContainer(component: component)
        return url.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
            .appendingPathComponent(component.rawValue, isDirectory: true)
    }
    
    /**
     * Returns the group logs url for the given sub-component.
     */
    public static func groupAppLogs(component: Component) -> URL {
        let url = Self.groupContainer(component: component)
        return url.appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent(component.rawValue, isDirectory: true)
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
    
    /// Container subcomponents
    public enum Component: String {
        /// Thumbnail  XPC service
        case thumbHandler = "me.tseifert.smokeshed.xpc.hand"
        /// Rendering XPC service
        case renderer = "me.tseifert.smokeshed.xpc.renderer"
    }
}
