//
//  Camera+CoreDataClass.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData

@objc(Camera)
public class Camera: NSManagedObject {
    // MARK: Object lifecycle
    /**
     * Sets a randomly generated identifier when the camera is first created.
     */
    public override func awakeFromInsert() {
        super.awakeFromInsert()

        self.identifier = UUID()
    }
}
