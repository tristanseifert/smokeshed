//
//  Image+CoreDataClass.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData

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

    /**
     * Allow image size to be properly dependent on the private backing storage property.
     */
    class override public func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String> {
        var keyPaths = super.keyPathsForValuesAffectingValue(forKey: key)

        if key == "imageSize" {
            keyPaths = keyPaths.union(["pvtImageSize"])
        }

        return keyPaths
    }
}
