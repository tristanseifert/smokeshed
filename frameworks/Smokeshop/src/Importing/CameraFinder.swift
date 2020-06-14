//
//  CameraFinder.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation


import CocoaLumberjackSwift

/**
 * Given some image metadata, this class will try to find a matching camera in the library's data store, or
 * create one if needed.
 */
internal class CameraFinder {
    /// Context for data store operations; you must set this
    internal var context: NSManagedObjectContext! = nil


    /**
     * Tries to find a camera that best matches what is laid out in the given metadata. If we could identify the
     * camera but none exists in the library, it's created.
     */
    internal func find(_ meta: [String: AnyObject]) throws -> Camera? {
        var fetchRes: Result<[Camera], Error>? = nil

        // get the tiff dictionary (contains maker and model)
        guard let tiff = meta[kCGImagePropertyTIFFDictionary as String] else {
            return nil
        }

        // read the make and model strings
        guard let make = tiff[kCGImagePropertyTIFFMake as String] as? String,
            let model = tiff[kCGImagePropertyTIFFModel as String] as? String else {
            return nil
        }

        // try to find an existing lens matching BOTH criteria
        let req = NSFetchRequest<Camera>(entityName: "Camera")

        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "exifModel == %@", model),
            NSPredicate(format: "exifMake == %@", make)
        ])

        self.context.performAndWait {
            do {
                let res = try self.context.fetch(req)
                fetchRes = .success(res)
            } catch {
                fetchRes = .failure(error)
            }
        }

        let results = try fetchRes!.get()
        if !results.isEmpty {
            return results.first
        }

        // we need to create a camera
        return try self.create(meta, make, model)
    }

    /**
     * Creates a lens object for the given metadata.
     */
    private func create(_ meta: [String: AnyObject], _ make: String, _ model: String) throws -> Camera? {
        var res: Result<Camera, Error>? = nil

        // run a block to create it
        self.context.performAndWait {
            let cam = Camera(context: self.context)

            cam.exifMake = make
            cam.exifModel = model

            cam.name = model

            // DNG info may have a localized name
            if let dng = meta[kCGImagePropertyDNGDictionary as String],
                let loc = dng[kCGImagePropertyDNGLocalizedCameraModel as String] as? String {
                cam.localizedModel = loc
            }

            // try to save it
            do {
                try self.context.save()
                res = .success(cam)
            } catch {
                res = .failure(error)
            }
        }

        // return the lens or throw error
        return try res!.get()
    }
}
