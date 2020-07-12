//
//  GPSLocation+CoreDataProperties.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData
import CoreLocation


extension GPSLocation {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<GPSLocation> {
        return NSFetchRequest<GPSLocation>(entityName: "GPSLocation")
    }

    @NSManaged public var rawLocation: CLLocation?
    @NSManaged public var lat: Double
    @NSManaged public var lng: Double
    @NSManaged public var name: String?
    @NSManaged public var images: Image?

}
