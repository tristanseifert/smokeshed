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
        let components = Calendar.current.dateComponents([.day, .month, .year], from: self)

        return Calendar.current.date(from: components)
    }
}
