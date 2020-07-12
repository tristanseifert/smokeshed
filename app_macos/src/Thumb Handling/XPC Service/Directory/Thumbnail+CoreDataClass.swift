//
//  Thumbnail+CoreDataClass.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200621.
//
//

import Foundation
import CoreData

@objc(Thumbnail)
public class Thumbnail: NSManagedObject {
    /**
     * Generates an unique identifier for storing in chunks to reference this thumbnail.
     */
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        self.chunkEntryIdentifier = UUID()
    }
}
