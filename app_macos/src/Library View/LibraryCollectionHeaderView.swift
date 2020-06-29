//
//  LibraryCollectionHeaderView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200610.
//

import Cocoa

import CocoaLumberjackSwift

/**
 * These views are used to render the section headers in the library view. They display a date
 */
class LibraryCollectionHeaderView: NSVisualEffectView, NSCollectionViewSectionHeaderView {
    /// Reference to the collection view; used to determine how to interpret header value
    internal weak var owner: LibraryBrowserBase! = nil

    /// Date formatter used to present capture dates
    private static let captureDayFormatter: DateFormatter = {
        let fmt = DateFormatter()

        fmt.dateStyle = .long
        fmt.timeStyle = .none
        fmt.timeZone = TimeZone(secondsFromGMT: 0)!

        return fmt
    }()
    /// Date formatter used to present import dates
    private static let importDateFormatter: DateFormatter = {
        let fmt = DateFormatter()

        fmt.dateStyle = .long
        fmt.timeStyle = .medium

        return fmt
    }()
    /// Date formatter for parsing the stringified section header dates
    private static let inFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(secondsFromGMT: 0)!
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss ZZ"

        return fmt
    }()

    /// Section info
    @objc dynamic public var section: NSFetchedResultsSectionInfo! = nil {
        didSet {
            // we got some sekshun
            if let sec = self.section {
                // Section name may be empty string (null group value)
                if sec.name.isEmpty {
                    self.nameLabel.stringValue = Bundle.main.localizedString(forKey: "title.nullPlaceholder", value: nil, table: "LibraryCollectionHeaderView")
                    return
                }

                // handle ratings
                if self.owner.groupBy == .rating {
                    guard let number = Int(sec.name, radix: 10) else {
                        DDLogVerbose("Failed to parse number from sec name '\(sec.name)'")
                        return
                    }

                    if number == -1 {
                        self.nameLabel.stringValue = Bundle.main.localizedString(forKey: "title.unrated", value: nil, table: "LibraryCollectionHeaderView")
                    } else {
                        // yeah this is kind of a hack
                        self.nameLabel.stringValue = Bundle.main.localizedString(forKey: "title.rating.\(number)", value: nil, table: "LibraryCollectionItems")

                    }
                } else {
                    // convert the name into a date
                    guard let date = LibraryCollectionHeaderView.inFormatter.date(from: sec.name) else {
                        DDLogVerbose("Failed to parse date from sec name '\(sec.name)'")
                        return
                    }

                    if self.owner.groupBy == .dateCaptured {
                        self.nameLabel.stringValue = LibraryCollectionHeaderView.captureDayFormatter.string(from: date)
                    } else if self.owner.groupBy == .dateImported {
                        self.nameLabel.stringValue = LibraryCollectionHeaderView.importDateFormatter.string(from: date)
                    }
                }
            }
        }
    }
    /// Collection view we're being displayed on
    var collection: NSCollectionView! = nil {
        didSet {
            if let button = self.collapse {
                // connect it to the collapse action
                if let c = self.collection {
                    button.target = c
                    button.action = #selector(NSCollectionView.toggleSectionCollapse(_:))
                }
                // remove collapse action if set to nil
                else {
                    button.target = nil
                }
            }
        }
    }

    /// Section name label
    private var nameLabel: NSTextField! = nil
    /// Section collapse button
    private var collapse: NSButton! = nil

    // MARK: - Initialization
    /**
     * Initializes a new header view. All subviews are added programatically.
     */
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.material = .headerView
        self.blendingMode = .withinWindow

        self.setUpBorderView()
        self.setUpSectionNameLabel()
//        self.setUpCollapseButton()
    }
    /// We do not support unarchiving this view.
    required init?(coder: NSCoder) {
        return nil
    }

    /**
     * Initializes the label view.
     */
    private func setUpSectionNameLabel() {
        // create the field
        self.nameLabel = NSTextField(labelWithString: "<section title>")
        self.nameLabel.translatesAutoresizingMaskIntoConstraints = false
        self.nameLabel.controlSize = .regular

        let size = NSFont.systemFontSize(for: .regular)
        self.nameLabel.font = NSFont.systemFont(ofSize: size, weight: .medium)

        self.nameLabel.textColor = NSColor.labelColor

        self.addSubview(self.nameLabel)
        
        // set its constraints
        NSLayoutConstraint.activate([
            // spacing from leading side of view
            self.nameLabel.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
            // center vertically
            self.nameLabel.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }
    /**
     * Creates the "collapse section" button.
     */
    private func setUpCollapseButton() {
        self.collapse = NSButton(frame: .zero)
        self.collapse.translatesAutoresizingMaskIntoConstraints = false
        self.collapse.controlSize = .regular

        self.collapse.title = Bundle.main.localizedString(forKey: "collapse.less", value: nil, table: "LibraryCollectionHeaderView")
        self.collapse.alternateTitle = Bundle.main.localizedString(forKey: "collapse.more", value: nil, table: "LibraryCollectionHeaderView")

        self.collapse.setButtonType(.pushOnPushOff)
        self.collapse.bezelStyle = .recessed
        self.collapse.state = .on
        self.collapse.isBordered = false

        let size = NSFont.systemFontSize(for: .small)
        self.collapse.font = NSFont.systemFont(ofSize: size, weight: .bold)

        self.collapse.isHidden = true

        self.addSubview(self.collapse)

        // make sure it can collapse the section
        self.sectionCollapseButton = self.collapse
        self.collapse.action = #selector(NSCollectionView.toggleSectionCollapse(_:))

        // set its constraints
        NSLayoutConstraint.activate([
            // spacing from trailing side of view
            self.collapse.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -6),
            // center vertically
            self.collapse.centerYAnchor.constraint(equalTo: self.centerYAnchor)
        ])
    }

    // MARK: - Border View
    /**
     * Sets up the border view.
     */
    private func setUpBorderView() {
        // set up the top border
        let top = BorderView(frame: .zero)
        top.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(top)

        NSLayoutConstraint.activate([
            // match the trailing/leading edges of superview
            top.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            top.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            // match the top edge of superview
            top.topAnchor.constraint(equalTo: self.topAnchor),

            // height is one pixel
            top.heightAnchor.constraint(equalToConstant: 1)
        ])

        // set up the bottom border
        let bottom = BorderView(frame: .zero)
        bottom.translatesAutoresizingMaskIntoConstraints = false

        self.addSubview(bottom)

        NSLayoutConstraint.activate([
            // match the trailing/leading edges of superview
            bottom.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bottom.leadingAnchor.constraint(equalTo: self.leadingAnchor),

            // match the bottom edge of superview
            bottom.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -1),

            // height is one pixel
            bottom.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    /**
     * Simple view that draws the top/bottom borders of the header.
     */
    private class BorderView: NSView {
        /**
         * Draws the separator lines.
         */
        override func draw(_ dirtyRect: NSRect) {
            let borderColor = NSColor.tertiaryLabelColor

            borderColor.setFill()
            dirtyRect.fill(using: .copy)
        }
    }

    // MARK: - Collection header protocol
    /// This is set to the collapse button later.
    var sectionCollapseButton: NSButton?
}

extension NSUserInterfaceItemIdentifier {
    /// Image collection view section header
    static let libraryCollectionHeader = NSUserInterfaceItemIdentifier("libraryCollectionHeader")
}
