//
//  UserDefaults+GridCell.swift
//  Smokeshed
//
//  Created by Tristan Seifert on 20200627.
//

import Foundation

extension UserDefaults {
    /// Do image grid cells show the sequence number?
    @objc dynamic var gridCellSequenceNumber: Bool {
        get {
            return self.bool(forKey: "gridCellSequenceNumber")
        }
        set {
            set(newValue, forKey: "gridCellSequenceNumber")
        }
    }
    /// Do image grid cells show image detail information?
    @objc dynamic var gridCellImageDetail: Bool {
        get {
            return self.bool(forKey: "gridCellImageDetail")
        }
        set {
            set(newValue, forKey: "gridCellImageDetail")
        }
    }
    /// Do image grid cells show ratings?
    @objc dynamic var gridCellImageRatings: Bool {
        get {
            return self.bool(forKey: "gridCellImageRatings")
        }
        set {
            set(newValue, forKey: "gridCellImageRatings")
        }
    }
    /// Do image cells have a hovered appearance?
    @objc dynamic var gridCellHoverStyle: Bool {
        get {
            return self.bool(forKey: "gridCellHoverStyle")
        }
        set {
            set(newValue, forKey: "gridCellHoverStyle")
        }
    }
    
    /// Format for the grid cell image detail header
    @objc dynamic var gridCellImageDetailFormat: [String: Any] {
        get {
            return self.object(forKey: "gridCellImageDetailFormat") as! [String: Any]
        }
        set {
            set(newValue, forKey: "gridCellImageDetailFormat")
        }
    }
}

