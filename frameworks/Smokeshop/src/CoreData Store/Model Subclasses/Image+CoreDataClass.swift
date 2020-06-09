//
//  Image+CoreDataClass.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData

@objc(Image)
public class Image: NSManagedObject {
    /**
     * Sets a randomly generated identifier when the image is first created.
     */
    public override func awakeFromInsert() {
        self.identifier = UUID()
    }
}
