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
public struct Fraction: Codable {
    /// Numerator (top)
    private(set) public var numerator: Int
    /// Denominator (bottom)
    private(set) public var denominator: Int
    
    /// Decimal representation of the fraction
    public var value: Double {
        return Double(self.numerator) / Double(self.denominator)
    }
    
    /**
     * Creates a new fraction with the provdied numerator and denominator.
     */
    init(numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
    }
    /**
     * Creates a new fraction from a double value.
     */
    init(_ value: Double) {
        let precision = 1000000
        
        let integral = floor(value)
        let frac = value - integral
        
        let gcd = Self.gcd(Int(frac * Double(precision)), precision)
        
        let denom = (precision / gcd)
        var num = (Int(round(frac * Double(precision))) / gcd)
        num += denom * Int(integral)
        
        self.init(numerator: num, denominator: denom)
    }
    
    /**
     * Computes the greatest common divisor between two numbers.
     */
    static func gcd(_ a: Int, _ b: Int) -> Int {
        if a == 0 {
            return b
        } else if b == 0 {
            return a
        }
        
        if a < b {
            return Self.gcd(a, b % a)
        } else {
            return Self.gcd(b, a % b)
        }
    }
    
    /// A fraction that has no value
    internal static let none = Fraction(numerator: 0, denominator: 0)
}
