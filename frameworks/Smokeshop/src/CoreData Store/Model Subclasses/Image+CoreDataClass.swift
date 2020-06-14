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
    // MARK: Object lifecycle
    /**
     * Sets a randomly generated identifier when the image is first created, and sets up default values for
     * transient properties.
     */
    public override func awakeFromInsert() {
        super.awakeFromInsert()

        self.identifier = UUID()
        self.updateTransients()
    }

    /**
     * Calculates transient properties when the object is loaded.
     */
    public override func awakeFromFetch() {
        super.awakeFromFetch()

        self.updateTransients()
    }

    /**
     * Updates computed properties as needed.
     */
    public override func didChangeValue(forKey key: String) {
        super.didChangeValue(forKey: key)

        // update the day captured
        if key == #keyPath(Image.dateCaptured) {
            self.dayCaptured = self.dateCaptured?.withoutTime()
        }
    }

    // MARK: Transient variables
    /**
     * Updates all transient variables.
     */
    private func updateTransients() {
        // update capture day
        self.dayCaptured = self.dateCaptured?.withoutTime()
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
