//
//  Image+CoreDataClass.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData

import Bowl
import CocoaLumberjackSwift

@objc(Image)
public class Image: NSManagedObject {
    /**
     * Sets a randomly generated identifier when the image is first created.
     */
    public override func awakeFromInsert() {
        super.awakeFromInsert()

        self.identifier = UUID()
    }

    /**
     * Returns the date the image was captured, but with the time stripped. This allows grouping by capture
     * date much more easily.
     */
    @objc dynamic public var dayCaptured: Date! {
        // bail out if there's no date provided
        guard let date = self.dateCaptured else {
            return nil
        }

        return date.withoutTime()
    }

    // MARK: Image size syntactic sugar
    /**
     * Image size
     */
    @objc dynamic public var imageSize: CGSize {
        get {
            guard let w = self.pvtImageSize?["w"] as? Double,
                  let h = self.pvtImageSize?["h"] as? Double else {
                DDLogError("Failed to decode stored image size '\(String(describing: self.pvtImageSize))'")
                return CGSize(width: -1, height: -1)
            }

            return CGSize(width: w, height: h)
        }
        set(newValue) {
            self.pvtImageSize = [
                "w": newValue.width,
                "h": newValue.height
            ]
        }
    }

    // MARK: - KVO Support
    /**
     * Allow calculated properties to be properly dependent on the private backing storage property.
     */
    class override public func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String> {
        var keyPaths = super.keyPathsForValuesAffectingValue(forKey: key)

        // handle image size
        if key == "imageSize" {
            keyPaths = keyPaths.union(["pvtImageSize"])
        }
        // handle the day captured
        else if key == "dayCaptured" {
            keyPaths = keyPaths.union(["dateCaptured"])
        }

        return keyPaths
    }
}
