//
//  Date+BowlExtensions.swift
//  Bowl (macOS)
//
//  Created by Tristan Seifert on 20200610.
//

import Foundation

/**
 * Provide some commonly used date operations.
 */
extension Date {
    /**
     * Returns a version of the date with the time information stripped.
     */
    public func withoutTime() -> Date! {
        var components = Calendar.current.dateComponents([.day, .month, .year], from: self)
        components.hour = 0
        components.minute = 0
        components.second = 0
        
        components.timeZone = TimeZone(secondsFromGMT: 0)!
        return Calendar.current.date(from: components)
    }
}
