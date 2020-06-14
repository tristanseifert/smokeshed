//
//  LensFinder.swift
//  Smokeshop (macOS)
//
//  Created by Tristan Seifert on 20200614.
//

import Foundation

import CocoaLumberjackSwift

/**
 * Given some image metadata, this class will try to find a matching lens in the library's data store, or create
 * one if needed.
 */
internal class LensFinder {
    /// Context for data store operations; you must set this
    internal var context: NSManagedObjectContext! = nil

    /**
     * Tries to find a lens that best matches what is laid out in the given metadata. If we could identify the
     * lens but none exists in the library, it's created.
     */
    internal func find(_ meta: [String: AnyObject]) throws -> Lens? {
        var fetchRes: Result<[Lens], Error>? = nil

        // read the model string and lens id
        guard let exif = meta[kCGImagePropertyExifDictionary as String],
            let model = exif[kCGImagePropertyExifLensModel] as? String else {
                DDLogWarn("Failed to get lens model from metadata: \(meta)")
                return nil
        }

        var lensId: Int? = nil
        if let aux = meta[kCGImagePropertyExifAuxDictionary as String],
            let id = aux[kCGImagePropertyExifAuxLensID] as? NSNumber {
            lensId = id.intValue
        }

        // try to find an existing lens matching BOTH criteria
        let req = NSFetchRequest<Lens>(entityName: "Lens")

        var predicates = [
            NSPredicate(format: "exifLensModel == %@", model)
        ]
        if let id = lensId {
            predicates.append(NSPredicate(format: "exifLensId == %i", id))
        }

        req.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

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

        // we need to create a lens
        return try self.create(meta, model, lensId)
    }

    /**
     * Creates a lens object for the given metadata.
     *
     * The context is not saved after creation; the assumption is that pretty much immediately after this call,
     * an image is imported, where we'll save the context anyhow.
     */
    private func create(_ meta: [String: AnyObject], _ model: String, _ id: Int?) throws -> Lens? {
        var res: Result<Lens, Error>? = nil

        // run a block to create it
        self.context.performAndWait {
            let lens = Lens(context: self.context)

            lens.exifLensModel = model
            lens.name = model

            lens.exifLensId = Int32(id ?? -1)

            // try to save it
            do {
                try self.context.save()
                res = .success(lens)
            } catch {
                res = .failure(error)
            }
        }

        // return the lens or throw error
        return try res!.get()
    }
}