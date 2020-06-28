//
//  UserDefaults+Shared.swift
//  Bowl (macOS)
//
//  Created by Tristan Seifert on 20200626.
//

import Foundation

/**
 * Provides an interface to the various shared user defaults used by various app components.
 */
extension UserDefaults {
    /// Thumbnail preferences
    public static var thumbShared: UserDefaults {
        let suite = String(format: "%@.thumb", ContainerHelper.groupName)
        return UserDefaults(suiteName: suite)!
    }
}
