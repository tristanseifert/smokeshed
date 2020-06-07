//
//  ActivityViewController.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200607.
//

import Cocoa

import CocoaLumberjackSwift

class ActivityViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
    }

    /**
     * Before the view appears, update our preferred size with the size required to fit all activities.
     */
    override func viewWillAppear() {
        self.updatePreferredSize()
    }

    /**
     * Recalculates the preferred size of the activities view. When displayed in a popover, it will resize to
     * this new size.
     */
    private func updatePreferredSize() {
        let requiredSize = self.activitiesTable.fittingSize

        var height = max(154, requiredSize.height)
        height = min(616, requiredSize.height)

        self.preferredContentSize = CGSize(width: self.view.bounds.width,
                                           height: height)
        DDLogVerbose("New activity list size: \(self.preferredContentSize)")
    }

    // MARK: - Activity Array Controller
    /**
     * Each activity currently ongoing is represented by one of these structs, which are in turn then
     * displayed in the user interface,
     */
    @objc class Activity: NSObject {
        /// Title of the activity
        @objc dynamic var title: String = "Activity Title"
        /// Detailed info about the activity
        @objc dynamic var detail: String = "Detailed info about this activity"

        /// Is it cancelable?
        @objc dynamic var isCancelable: Bool = true

        /// Progress object for tracking the activity
        @objc dynamic var progress: Progress = Progress()
        /// Is the activity active? This is used for the progress indicator
        @objc dynamic var isActive: Bool = true

    }

    /// Table view to show the activities
    @IBOutlet private var activitiesTable: NSTableView! = nil
    /// Display activities
    @objc dynamic var activities = [Activity]()
}
