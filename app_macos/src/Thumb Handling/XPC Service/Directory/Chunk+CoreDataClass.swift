//
//  Chunk+CoreDataClass.swift
//  ThumbHandler
//
//  Created by Tristan Seifert on 20200621.
//
//

import Foundation
import CoreData

@objc(Chunk)
public class Chunk: NSManagedObject {
    /**
     * Generates an unique identifier when inserting a new chunk object.
     */
    public override func awakeFromInsert() {
         super.awakeFromInsert()
         
         self.identifier = UUID()
     }
}
