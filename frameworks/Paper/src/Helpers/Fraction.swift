//
//  Fraction.swift
//  Paper (macOS)
//
//  Created by Tristan Seifert on 20200619.
//

import Foundation

/**
 * Generic fraction class
 */
public struct Fraction {
    /// Numerator (top)
    private(set) public var numerator: Int
    /// Denominator (bottom)
    private(set) public var denominator: Int
    
    /// Decimal representation of the fraction
    public var value: Double {
        return Double(self.numerator) / Double(self.denominator)
    }
    
    /// A fraction that has no value
    internal static let none = Fraction(numerator: 0, denominator: 0)
}
