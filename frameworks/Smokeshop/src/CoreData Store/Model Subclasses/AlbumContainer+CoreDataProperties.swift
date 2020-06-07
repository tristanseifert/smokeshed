//
//  AlbumContainer+CoreDataProperties.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData


extension AlbumContainer {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<AlbumContainer> {
        return NSFetchRequest<AlbumContainer>(entityName: "AlbumContainer")
    }

    @NSManaged public var name: String?
    @NSManaged public var detail: NSAttributedString?
    @NSManaged public var albums: NSOrderedSet?

}

// MARK: Generated accessors for albums
extension AlbumContainer {

    @objc(insertObject:inAlbumsAtIndex:)
    @NSManaged public func insertIntoAlbums(_ value: Album, at idx: Int)

    @objc(removeObjectFromAlbumsAtIndex:)
    @NSManaged public func removeFromAlbums(at idx: Int)

    @objc(insertAlbums:atIndexes:)
    @NSManaged public func insertIntoAlbums(_ values: [Album], at indexes: NSIndexSet)

    @objc(removeAlbumsAtIndexes:)
    @NSManaged public func removeFromAlbums(at indexes: NSIndexSet)

    @objc(replaceObjectInAlbumsAtIndex:withObject:)
    @NSManaged public func replaceAlbums(at idx: Int, with value: Album)

    @objc(replaceAlbumsAtIndexes:withAlbums:)
    @NSManaged public func replaceAlbums(at indexes: NSIndexSet, with values: [Album])

    @objc(addAlbumsObject:)
    @NSManaged public func addToAlbums(_ value: Album)

    @objc(removeAlbumsObject:)
    @NSManaged public func removeFromAlbums(_ value: Album)

    @objc(addAlbums:)
    @NSManaged public func addToAlbums(_ values: NSOrderedSet)

    @objc(removeAlbums:)
    @NSManaged public func removeFromAlbums(_ values: NSOrderedSet)

}
