//
//  Keyword+CoreDataProperties.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData


extension Keyword {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Keyword> {
        return NSFetchRequest<Keyword>(entityName: "Keyword")
    }

    @NSManaged public var name: String?
    @NSManaged public var synonyms: NSSet?
    @NSManaged public var parent: Keyword?
    @NSManaged public var images: NSSet?

}

// MARK: Generated accessors for synonyms
extension Keyword {

    @objc(addSynonymsObject:)
    @NSManaged public func addToSynonyms(_ value: Keyword)

    @objc(removeSynonymsObject:)
    @NSManaged public func removeFromSynonyms(_ value: Keyword)

    @objc(addSynonyms:)
    @NSManaged public func addToSynonyms(_ values: NSSet)

    @objc(removeSynonyms:)
    @NSManaged public func removeFromSynonyms(_ values: NSSet)

}

// MARK: Generated accessors for images
extension Keyword {

    @objc(addImagesObject:)
    @NSManaged public func addToImages(_ value: Image)

    @objc(removeImagesObject:)
    @NSManaged public func removeFromImages(_ value: Image)

    @objc(addImages:)
    @NSManaged public func addToImages(_ values: NSSet)

    @objc(removeImages:)
    @NSManaged public func removeFromImages(_ values: NSSet)

}
