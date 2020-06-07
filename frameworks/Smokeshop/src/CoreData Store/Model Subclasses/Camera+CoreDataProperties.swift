//
//  Camera+CoreDataProperties.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData


extension Camera {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Camera> {
        return NSFetchRequest<Camera>(entityName: "Camera")
    }

    @NSManaged public var identifier: UUID?
    @NSManaged public var name: String?
    @NSManaged public var detail: NSAttributedString?
    @NSManaged public var make: String?
    @NSManaged public var localizedModel: String?
    @NSManaged public var mount: String?
    @NSManaged public var exifName: String?
    @NSManaged public var images: NSSet?

}

// MARK: Generated accessors for images
extension Camera {

    @objc(addImagesObject:)
    @NSManaged public func addToImages(_ value: Image)

    @objc(removeImagesObject:)
    @NSManaged public func removeFromImages(_ value: Image)

    @objc(addImages:)
    @NSManaged public func addToImages(_ values: NSSet)

    @objc(removeImages:)
    @NSManaged public func removeFromImages(_ values: NSSet)

}
