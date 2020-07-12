//
//  Library+CoreDataClass.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200621.
//
//

import Foundation
import CoreData

@objc(Library)
public class Library: NSManagedObject {
    /**
     * Generates a new identifier and sets the creation date when inserting a new library.
     */
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        
        self.created = Date()
    }
}
