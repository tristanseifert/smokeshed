//
//  SizeTransformer.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200609.
//

import Foundation
import OSLog

/**
 * Implements a transformer that converts between binary data and a CGSize struct. (Really, this encodes the
 * size as an NSValue and encodes that)
 */
public class SizeTransformer: ValueTransformer {
    fileprivate static var logger = Logger(subsystem: Bundle(for: SizeTransformer.self).bundleIdentifier!,
                                         category: "SizeTransformer")
    
    /**
     * The output of the transformer is binary data.
     */
    override public class func transformedValueClass() -> AnyClass {
        return NSData.self
    }

    /**
     * Reverse transformations (Data -> CGSize) are possible.
     */
    override public class func allowsReverseTransformation() -> Bool {
        return true
    }

    /**
     * Transforms an input rect to binary data by archiving it.
     */
    public override func transformedValue(_ inVal: Any?) -> Any? {
        guard let value = inVal else {
            return nil
        }

        do {
            return try NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)
        } catch {
            Self.logger.error("Failed to encode data: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /**
     * Transforms binary data back to a rect by unarchiving.
     */
    public override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else {
            Self.logger.error("Failed to get input as data: \(String(describing: value))")
            return nil
        }
        do {
            guard let v = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: data) else {
                Self.logger.error("Failed to unarchive data: \(data)")
                return nil
            }

            return v
        } catch {
            Self.logger.error("Failed to decode data: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /**
     * Registers the transformer. This must be called at least once at startup.
     */
    public class func register() {
        ValueTransformer.setValueTransformer(SizeTransformer(), forName: .sizeTransformerName)
    }
}

extension NSValueTransformerName {
    /// Name of the CGSize <-> Data transformer
    static let sizeTransformerName = NSValueTransformerName(rawValue: "SizeTransformer")
}
