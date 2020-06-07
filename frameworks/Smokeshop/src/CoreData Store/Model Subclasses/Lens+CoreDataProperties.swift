//
//  Lens+CoreDataProperties.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData


extension Lens {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Lens> {
        return NSFetchRequest<Lens>(entityName: "Lens")
    }

    @NSManaged public var name: String?
    @NSManaged public var detail: NSAttributedString?
    @NSManaged public var identifier: UUID?
    @NSManaged public var mount: String?
    @NSManaged public var model: String?
    @NSManaged public var make: String?
    @NSManaged public var images: NSSet?

}

// MARK: Generated accessors for images
extension Lens {

    @objc(addImagesObject:)
    @NSManaged public func addToImages(_ value: Image)

    @objc(removeImagesObject:)
    @NSManaged public func removeFromImages(_ value: Image)

    @objc(addImages:)
    @NSManaged public func addToImages(_ values: NSSet)

    @objc(removeImages:)
    @NSManaged public func removeFromImages(_ values: NSSet)

}
