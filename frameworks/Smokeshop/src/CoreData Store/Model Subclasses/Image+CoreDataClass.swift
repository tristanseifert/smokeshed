//
//  Image+CoreDataClass.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200606.
//
//

import Foundation
import CoreData

import Bowl
import Paper
import CocoaLumberjackSwift

@objc(Image)
public class Image: NSManagedObject {
    // MARK: Object lifecycle
    /**
     * Sets a randomly generated identifier when the image is first created, and sets up default values for
     * transient properties.
     */
    public override func awakeFromInsert() {
        super.awakeFromInsert()

        self.identifier = UUID()
        self.updateTransients()
    }

    /**
     * Calculates transient properties when the object is loaded.
     */
    public override func awakeFromFetch() {
        super.awakeFromFetch()

        self.updateTransients()
    }

    /**
     * Updates computed properties as needed.
     */
    public override func didChangeValue(forKey key: String) {
        super.didChangeValue(forKey: key)

        // update the day captured
        if key == #keyPath(Image.dateCaptured) {
            self.dayCaptured = self.dateCaptured?.withoutTime()
        }
        // raw metadata
        if key == #keyPath(Image.rawMetadata) {
            guard self.encodeMetadataOnChange == true else { return }
            self.decodeMetadata()
        }
    }
    
    // MARK: Metadata
    /// Whether metadata will be encoded for this change
    private var encodeMetadataOnChange = true
    
    /// Image metadata
    public var metadata: ImageMeta? = nil {
        didSet {
            self.encodeMetadataOnChange = false
            
            if let meta = self.metadata {
                let encoder = PropertyListEncoder()
                encoder.outputFormat = .binary
                
                do {
                    self.rawMetadata = try encoder.encode(meta)
                } catch {
                    DDLogError("Failed to encode metadata for \(self.objectID): \(error)")
                }
            } else {
                self.rawMetadata = nil
            }
            
            self.encodeMetadataOnChange = true
        }
    }

    // MARK: URL bookmark support
    /**
     * Decodes the url bookmark for the image.
     */
    public func getUrl(relativeTo base: URL?) -> URL? {
        // have we got a bookmark?
        if let bookmark = self.urlBookmark {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmark,
                                  options: [.withSecurityScope, .withoutUI],
                                  relativeTo: base, bookmarkDataIsStale: &isStale)

                // update bookmark if stale
                if isStale {
                    DDLogWarn("TODO: implement updating stale bookmark (url \(url), base \(String(describing: base))")
                }

                // return the url
                return url
            } catch {
                DDLogError("Failed to decode bookmark data (\(bookmark), base \(String(describing: base))) for image \(self.objectID): \(error)")
            }
        }

        // fall back to the original url
        if let url = self.originalUrl {
            return url
        }

        // failed to get an url
        return nil
    }

    /**
     * Generates and sets the bookmark data field with the given URL.
     */
    func setUrlBookmark(_ url: URL, relativeTo base: URL) throws {
        self.urlBookmark = try url.bookmarkData(options: [.withSecurityScope],
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: base)
    }

    // MARK: Transient variables
    /**
     * Updates all transient variables.
     */
    private func updateTransients() {
        // decode metadata
        self.decodeMetadata()
    }
    
    /**
     * Decodes the metadata object.
     */
    private func decodeMetadata() {
        if let data = self.rawMetadata {
            let decoder = PropertyListDecoder()
            
            do {
                self.metadata = try decoder.decode(ImageMeta.self, from: data)
            } catch {
                DDLogError("Failed to decode metadata for \(self.objectID): \(error)")
            }
        }
    }

    // MARK: Image size, orientation
    /**
     * Image size
     */
    @objc dynamic public var imageSize: CGSize {
        get {
            guard let w = self.pvtImageSize?["w"] as? Double,
                  let h = self.pvtImageSize?["h"] as? Double else {
                DDLogError("Failed to decode stored image size '\(String(describing: self.pvtImageSize))'")
                return CGSize(width: -1, height: -1)
            }

            return CGSize(width: w, height: h)
        }
        set(newValue) {
            self.pvtImageSize = [
                "w": newValue.width,
                "h": newValue.height
            ]
        }
    }

    /**
     * Rotated image size
     */
    @objc dynamic public var rotatedImageSize: CGSize {
        get {
            let orientation = ImageOrientation(rawValue: self.rawOrientation)

            if orientation == .ccw90 || orientation == .cw90 {
                let size = self.imageSize
                return CGSize(width: size.height, height: size.width)
            } else {
                return self.imageSize
            }
        }
    }

    @objc dynamic public var orientation: ImageOrientation {
        get {
            guard let o = ImageOrientation(rawValue: self.rawOrientation) else {
                return .unknown
            }
            return o
        }
    }

    @objc public enum ImageOrientation: Int16 {
        case unknown = -1
        case normal = 0
        case cw90 = 1
        case ccw90 = 2
        case cw180 = 3
    }

    // MARK: - KVO Support
    /**
     * Allow calculated properties to be properly dependent on the private backing storage property.
     */
    class override public func keyPathsForValuesAffectingValue(forKey key: String) -> Set<String> {
        var keyPaths = super.keyPathsForValuesAffectingValue(forKey: key)

        // handle image size
        if key == "imageSize" {
            keyPaths = keyPaths.union(["pvtImageSize"])
        }
        else if key == "rotatedImageSize" {
            keyPaths = keyPaths.union(["imageSize", "orientation"])
        }
        // irl url
        else if key == "url" {
            keyPaths = keyPaths.union(["originalUrl", "urlBookmark"])
        }
        // orientation
        else if key == "orientation" {
            keyPaths = keyPaths.union(["rawOrientation"])
        }

        return keyPaths
    }
}
