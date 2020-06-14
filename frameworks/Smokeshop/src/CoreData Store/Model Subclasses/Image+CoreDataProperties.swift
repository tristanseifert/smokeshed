//
//  Image+CoreDataProperties.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200613.
//
//

import Foundation
import CoreData


extension Image {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Image> {
        return NSFetchRequest<Image>(entityName: "Image")
    }

    @NSManaged public var dateCaptured: Date?
    @NSManaged public var dateImported: Date?
    @NSManaged public var dayCaptured: Date?
    @NSManaged public var identifier: UUID?
    @NSManaged public var name: String?
    @NSManaged public var originalMetadata: NSDictionary?
    @NSManaged public var originalUrl: URL?
    @NSManaged public var pvtImageSize: NSDictionary?
    @NSManaged public var rating: Int16
    @NSManaged public var rawOrientation: Int16
    @NSManaged public var urlBookmark: Data?
    @NSManaged public var albums: NSSet?
    @NSManaged public var camera: Camera?
    @NSManaged public var keywords: NSOrderedSet?
    @NSManaged public var lens: Lens?
    @NSManaged public var location: GPSLocation?

}

// MARK: Generated accessors for albums
extension Image {

    @objc(addAlbumsObject:)
    @NSManaged public func addToAlbums(_ value: Album)

    @objc(removeAlbumsObject:)
    @NSManaged public func removeFromAlbums(_ value: Album)

    @objc(addAlbums:)
    @NSManaged public func addToAlbums(_ values: NSSet)

    @objc(removeAlbums:)
    @NSManaged public func removeFromAlbums(_ values: NSSet)

}

// MARK: Generated accessors for keywords
extension Image {

    @objc(insertObject:inKeywordsAtIndex:)
    @NSManaged public func insertIntoKeywords(_ value: Keyword, at idx: Int)

    @objc(removeObjectFromKeywordsAtIndex:)
    @NSManaged public func removeFromKeywords(at idx: Int)

    @objc(insertKeywords:atIndexes:)
    @NSManaged public func insertIntoKeywords(_ values: [Keyword], at indexes: NSIndexSet)

    @objc(removeKeywordsAtIndexes:)
    @NSManaged public func removeFromKeywords(at indexes: NSIndexSet)

    @objc(replaceObjectInKeywordsAtIndex:withObject:)
    @NSManaged public func replaceKeywords(at idx: Int, with value: Keyword)

    @objc(replaceKeywordsAtIndexes:withKeywords:)
    @NSManaged public func replaceKeywords(at indexes: NSIndexSet, with values: [Keyword])

    @objc(addKeywordsObject:)
    @NSManaged public func addToKeywords(_ value: Keyword)

    @objc(removeKeywordsObject:)
    @NSManaged public func removeFromKeywords(_ value: Keyword)

    @objc(addKeywords:)
    @NSManaged public func addToKeywords(_ values: NSOrderedSet)

    @objc(removeKeywords:)
    @NSManaged public func removeFromKeywords(_ values: NSOrderedSet)

}
