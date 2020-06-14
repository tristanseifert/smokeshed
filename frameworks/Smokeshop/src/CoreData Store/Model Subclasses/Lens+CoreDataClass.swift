//
//  Lens+CoreDataClass.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData

@objc(Lens)
public class Lens: NSManagedObject {
    // MARK: Object lifecycle
    /**
     * Sets a randomly generated identifier when the lens is first created.
     */
    public override func awakeFromInsert() {
        super.awakeFromInsert()

        self.identifier = UUID()
    }

}
