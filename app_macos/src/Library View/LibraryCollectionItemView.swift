//
//  LibraryCollectionItemView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200609.
//

import Cocoa
import UniformTypeIdentifiers

import Smokeshop
import CocoaLumberjackSwift

/**
 * Renders a single image in the library view collection. For performance reasons, this is done entirely using
 * CALayers rather than views.
 */
class LibraryCollectionItemView: NSView, CALayerDelegate, NSViewLayerContentScaleDelegate {
    /// Image to display info about
    @objc dynamic var image: Image! = nil {
        /**
         * When the image we're representing is changed, it's important that we tell AppKit to redraw us,
         * since we earlier requested to only be redrawn when we demand it.
         */
        didSet {
            self.refreshThumb()
            self.updateContents()
            self.updateBindings()
            self.setNeedsDisplay(self.bounds)
        }
    }
    /// Sequence number of the image
    var sequenceNumber: Int = 0 {
        /**
         * When sequence number is set, mark the view as dirty.
         */
        didSet {
            self.setNeedsDisplay(self.bounds)
        }
    }
    
    /// Are controls in the cell allowed to modify the image object?
    var isEditable: Bool = true {
        didSet {
            self.ratings.isEditable = self.isEditable
        }
    }

    /// Surface object containing the thumbnail image.
    private var surface: IOSurface! = nil
    /// Identifier of the image for which this surface contains the thumbnail.
    private var surfaceImageId: UUID! = nil
    
    /// URL to the library that contains images being displayed
    internal var libraryUrl: URL? = nil

    // MARK: View render behaviors
    /// Ensure the layer is drawn as opaque so we get font smoothing.
    override var isOpaque: Bool {
        return true
    }

    /// Request AppKit uses layers exclusively.
    override var wantsUpdateLayer: Bool {
        return true
    }

    /**
     * Initializes the view's properties for layer rendering.
     */
    private func optimizeForLayer() {
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    // MARK: - Initialization
    /**
     * Initializes a new library collection item view. This prepares the view for layer-based rendering and
     * also sets up these layers.
     */
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.optimizeForLayer()
        self.setUpLayers()
        self.setUpTrackingArea()
        
        self.installDefaultsObservers()
    }
    /// Decoding this view is not supported
    required init?(coder: NSCoder) {
        return nil
    }
    
    /**
     * Remove observers on deinit.
     */
    deinit {
        // remove old thumb observer
        self.removeThumbObserver()
    }

    // MARK: - Layer setup
    /**
     * Create the view's backing layer.
     */
    override func makeBackingLayer() -> CALayer {
        let layer = CALayer()

        layer.delegate = self
        layer.layoutManager = CAConstraintLayoutManager()
        layer.backgroundColor = NSColor(named: "LibraryItemBackground")?.cgColor

        return layer
    }

    /**
     * Sets up the layers that make up the cell view.
     */
    private func setUpLayers() {
        // create the borders
        self.createDarkBorders()
        self.createLightBorders()

        // set up the top info area and the image area
        self.setUpTopInfoBox()
        self.setUpImageContainer()
        
        // lastly, the bottom info area
        self.setUpBottomInfoBox()
    }

    // MARK: Borders
    /**
     * Creates the dark (right and bottom) borders.
     */
    private func createDarkBorders() {
        let color = NSColor(named: "LibraryItemDarkBorder")?.cgColor

        // right border
        let right = CALayer()
        right.delegate = self
        right.backgroundColor = color
        right.constraints = [
            // fill height of superlayer, 1 point wide
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height),
            CAConstraint(attribute: .width, relativeTo: "superlayer",
                         attribute: .width, scale: 0, offset: 1),
            // align with top with superlayer
            CAConstraint(attribute: .maxY, relativeTo: "superlayer",
                         attribute: .maxY),
            // align right edge
            CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                         attribute: .maxX)
        ]
        right.actions = self.layer!.actions
        self.layer!.addSublayer(right)

        // bottom border
        let bottom = CALayer()
        bottom.delegate = self
        bottom.name = "bottomBorder"
        bottom.backgroundColor = color
        bottom.constraints = [
            // fill height of 1, width of superlayer
            CAConstraint(attribute: .width, relativeTo: "superlayer",
                         attribute: .width),
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height, scale: 0, offset: 1),
            // align bottom edge to superlayer
            CAConstraint(attribute: .minY, relativeTo: "superlayer",
                         attribute: .minY),
            // align right edge to superlayer
            CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                         attribute: .maxX)
        ]
        bottom.actions = self.layer!.actions
        self.layer!.addSublayer(bottom)
    }
    /**
     * Creates the light (left and top) borders
     */
    private func createLightBorders() {
        let color = NSColor(named: "LibraryItemLightBorder")?.cgColor

        // left border
        let left = CALayer()
        left.delegate = self
        left.backgroundColor = color
        left.constraints = [
            // fill height of superlayer, 1 point wide
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height),
            CAConstraint(attribute: .width, relativeTo: "superlayer",
                         attribute: .width, scale: 0, offset: 1),
            // align top edge to superlayer
            CAConstraint(attribute: .maxY, relativeTo: "superlayer",
                         attribute: .maxY),
            // align left edge to superlayer
            CAConstraint(attribute: .minX, relativeTo: "superlayer",
                         attribute: .minX)
        ]
        left.actions = self.layer!.actions
        self.layer!.addSublayer(left)

        // top border
        let top = CALayer()
        top.delegate = self
        top.backgroundColor = color
        top.constraints = [
            // fill height of 1, width of superlayer
            CAConstraint(attribute: .width, relativeTo: "superlayer",
                         attribute: .width),
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height, scale: 0, offset: 1),
            // align top edge to superlayer
            CAConstraint(attribute: .maxY, relativeTo: "superlayer",
                         attribute: .maxY),
            // align right edge to superlayer
            CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                         attribute: .maxX)
        ]
        top.actions = self.layer!.actions
        self.layer!.addSublayer(top)
    }

    // MARK: Top info area
    /// Top filename label
    private var nameLabel: CATextLayer = CATextLayer()
    /// Top subtitle label
    private var detailLabel: CATextLayer = CATextLayer()
    /// Image sequencen number label
    private var seqNumlabel: CATextLayer = CATextLayer()

    /// Height of the top information area
    private static let topInfoHeight: CGFloat = 64.0

    /// Spacing between the left and right edges of the cell, and text labels
    private static let labelHSpacing: CGFloat = 3.0
    /// Spacing between top and bottom edge of the info area and text labels
    private static let labelVSpacing: CGFloat = 0.0

    /// Font for the name text
    private static let nameFont: NSFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    /// Font for the details (subtitle) text
    private static let detailFont: NSFont = {
        let fnt = NSFont.systemFont(ofSize: 13, weight: .medium)
        return fnt
    }()
    /// Font for the sequence number
    private static let seqNoFont: NSFont = {
        let fnt = NSFont.monospacedDigitSystemFont(ofSize: 46, weight: .semibold)
        var desc = fnt.fontDescriptor
        
        // add some spicy attributes to the font
        let features = [
            // alternative 6/9
            [
                NSFontDescriptor.FeatureKey.typeIdentifier: kStylisticAlternativesType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kStylisticAltOneOnSelector,
            ],
            // alternative 4
            [
                NSFontDescriptor.FeatureKey.typeIdentifier: kStylisticAlternativesType,
                NSFontDescriptor.FeatureKey.selectorIdentifier: kStylisticAltTwoOnSelector,
            ]
        ]
        
        desc = desc.addingAttributes([
            .featureSettings: features
        ])
        
        // create a font from the updated descriptor
        return NSFont(descriptor: desc, size: fnt.pointSize) ?? fnt
    }()
    
    /// Attributes for the name label
    private static let nameAttributes: [NSAttributedString.Key: Any] = {
        // text shadow
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 2.0
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor(named: "LibraryItemNameShadow")!
        
        // attributes
        return [
            .shadow: shadow,
            .foregroundColor: NSColor(named: "LibraryItemName")!
        ]
    }()
    
    /// Attributes for the detail label
    private static let detailAttributes: [NSAttributedString.Key: Any] = {
        return [
            .foregroundColor: NSColor(named: "LibraryItemInfo")!
        ]
    }()

    /**
     * Creates the top info box.
     */
    private func setUpTopInfoBox() {
        // create a container for the top info stuff
        let topBox = CALayer()
        topBox.delegate = self
        topBox.name = "topInfoBox"
        topBox.layoutManager = CAConstraintLayoutManager()

        // set the background color on the top layer
        topBox.backgroundColor = NSColor(named: "LibraryItemTopInfoBackground")?.cgColor

        topBox.constraints = [
            // fill height of 64, width of superlayer
            CAConstraint(attribute: .width, relativeTo: "superlayer",
                         attribute: .width, offset: -2),
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height, scale: 0,
                         offset: Self.topInfoHeight),
            // align top edge to superlayer (minus one for border)
            CAConstraint(attribute: .maxY, relativeTo: "superlayer",
                         attribute: .maxY, offset: -1),
            // align left edge to superlayer (plus one to fit cell border)
            CAConstraint(attribute: .minX, relativeTo: "superlayer",
                         attribute: .minX, offset: 1)
        ]

        self.layer!.addSublayer(topBox)

        // border at the bottom of the box
        let border = CALayer()
        border.delegate = self
        border.name = "border"
        border.backgroundColor = NSColor(named: "LibraryItemTopInfoBorder")?.cgColor
        border.constraints = [
            // fill height of 1, width of superlayer
            CAConstraint(attribute: .width, relativeTo: "superlayer",
                         attribute: .width),
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height, scale: 0, offset: 1),
            // align bottom edge to superlayer
            CAConstraint(attribute: .minY, relativeTo: "superlayer",
                         attribute: .minY),
            // align right edge to superlayer
            CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                         attribute: .maxX)
        ]

        topBox.addSublayer(border)

        // sequence number label
        self.seqNumlabel.delegate = self
        self.seqNumlabel.name = "sequenceNumber"

        self.seqNumlabel.font = Self.seqNoFont
        self.seqNumlabel.fontSize = Self.seqNoFont.pointSize
        self.seqNumlabel.foregroundColor = NSColor(named: "LibraryItemSequence")?.cgColor

        self.seqNumlabel.alignmentMode = .right

        self.seqNumlabel.constraints = [
            // for 46pt font, use 50pt height
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height, scale: 0, offset: 50),
            // align bottom edge to superlayer (with some offset)
            CAConstraint(attribute: .minY, relativeTo: "superlayer",
                         attribute: .minY,
                         offset: Self.labelHSpacing),
            // align right edge to superlayer
            CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                         attribute: .maxX,
                         offset: -Self.labelHSpacing)
        ]

        topBox.addSublayer(self.seqNumlabel)

        // File name label
        self.nameLabel.delegate = self
        self.nameLabel.name = "nameLabel"
        self.nameLabel.alignmentMode = .left
        self.nameLabel.truncationMode = .end

        self.nameLabel.constraints = [
            // for 15pt font, use 20pt height
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height, scale: 0, offset: 20),
            // align top edge to superlayer (with some offset)
            CAConstraint(attribute: .maxY, relativeTo: "superlayer",
                         attribute: .maxY,
                         offset: -2),
            // align right and left edges to superlayer
            CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                         attribute: .maxX,
                         offset: -Self.labelHSpacing),
            CAConstraint(attribute: .minX, relativeTo: "superlayer",
                         attribute: .minX,
                         offset: Self.labelHSpacing)
        ]

        topBox.addSublayer(self.nameLabel)

        // Subtitle (aux info for image)
        self.detailLabel.delegate = self
        self.detailLabel.name = "detailLabel"
        self.detailLabel.alignmentMode = .left
        self.detailLabel.truncationMode = .end
        self.detailLabel.isWrapped = true

        self.detailLabel.constraints = [
            // align top edge to name, and bottom to superlayer
            CAConstraint(attribute: .maxY, relativeTo: "nameLabel",
                         attribute: .minY,
                         offset: -Self.labelVSpacing),
            CAConstraint(attribute: .minY, relativeTo: "border",
                         attribute: .maxY,
                         offset: Self.labelVSpacing),
            // align left edge to superlayer
            CAConstraint(attribute: .minX, relativeTo: "superlayer",
                         attribute: .minX,
                         offset: Self.labelHSpacing),
            // align right edge to sequence number (with some spacing)
            CAConstraint(attribute: .maxX, relativeTo: "sequenceNumber",
                         attribute: .minX,
                         offset: Self.labelHSpacing)
        ]

        topBox.addSublayer(self.detailLabel)
        
        /**
         * Even though we set an attributed string as the contents, we still have to set the font on these
         * labels or they won't draw properly. The truncation seems to be broken otherwise.
         *
         * Likewise, we need to duplicate any shadow and text colors or the elipses used for truncation
         * won't show up right, either. shrug
         */
        self.nameLabel.font = Self.nameFont
        self.nameLabel.fontSize = Self.nameFont.pointSize
        self.nameLabel.foregroundColor = NSColor(named: "LibraryItemName")!.cgColor
        self.nameLabel.shadowRadius = 2.0
        self.nameLabel.shadowOffset = CGSize(width: 0, height: -1)
        self.nameLabel.shadowColor = NSColor(named: "LibraryItemNameShadow")!.cgColor
        
        self.detailLabel.font = Self.detailFont
        self.detailLabel.fontSize = Self.detailFont.pointSize
        self.detailLabel.foregroundColor = NSColor(named: "LibraryItemInfo")!.cgColor
    }
    
    // MARK: - Bottom info area
    /// Is the bottom info area being shown?
    private var showBottomInfo: Bool = true {
        didSet {
            self.botBox.isHidden = !self.showBottomInfo
        }
    }
    
    /// Bottom info box layer
    private var botBox: CALayer!
    
    /// Ratings control
    private var ratings: NSLevelIndicator!
    /// Spacing between bottom of view and ratings control
    private static let ratingsBottomSpace: CGFloat = -10
    /// Height of ratings area
    private static let ratingsAreaHeight: CGFloat = 32
        
    private func setUpBottomInfoBox() {
        // create a container for the bottom info stuff
        let botBox = CALayer()
        botBox.delegate = self
        botBox.name = "bottomInfoBox"
        botBox.layoutManager = CAConstraintLayoutManager()

        // set the background color on the bottom layer
        botBox.backgroundColor = NSColor(named: "LibraryItemTopInfoBackground")?.cgColor

        botBox.constraints = [
            // fill height of 32, width of superlayer
            CAConstraint(attribute: .width, relativeTo: "superlayer",
                         attribute: .width, offset: -2),
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height, scale: 0,
                         offset: Self.ratingsAreaHeight),
            // align top bottom to superlayer (minus one for border)
            CAConstraint(attribute: .minY, relativeTo: "superlayer",
                         attribute: .minY, offset: 1),
            // align left edge to superlayer (plus one to fit cell border)
            CAConstraint(attribute: .minX, relativeTo: "superlayer",
                         attribute: .minX, offset: 1)
        ]

        self.layer!.addSublayer(botBox)
        self.botBox = botBox

        // border at the top of the box
        let border = CALayer()
        border.delegate = self
        border.name = "border"
        border.backgroundColor = NSColor(named: "LibraryItemTopInfoBorder")?.cgColor
        border.constraints = [
            // fill height of 1, width of superlayer
            CAConstraint(attribute: .width, relativeTo: "superlayer",
                         attribute: .width),
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height, scale: 0, offset: 1),
            // align top edge to superlayer
            CAConstraint(attribute: .maxY, relativeTo: "superlayer",
                         attribute: .maxY),
            // align right edge to superlayer
            CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                         attribute: .maxX)
        ]

        botBox.addSublayer(border)
        
        // ratings control
        self.ratings = NSLevelIndicator()
        self.ratings.isEditable = true
        self.ratings.levelIndicatorStyle = .rating
        self.ratings.minValue = 0
        self.ratings.maxValue = 5
        self.ratings.placeholderVisibility = .always
        self.ratings.ratingPlaceholderImage = NSImage(systemSymbolName: "star",
                                                      accessibilityDescription: Self.localized("rating.unfilled.axdesc"))
        self.ratings.ratingImage = NSImage(systemSymbolName: "star.fill",
                                           accessibilityDescription: Self.localized("rating.filled.axdesc"))
        self.ratings.fillColor = NSColor(named: "LibraryItemRatingFill")
        
        self.ratings.isContinuous = false
        self.ratings.target = self
        self.ratings.action = #selector(LibraryCollectionItemView.setRating(_:))
        
        self.addSubview(self.ratings)
        
        self.ratings.translatesAutoresizingMaskIntoConstraints = false
        self.ratings.controlSize = .regular
        
        self.ratings.heightAnchor.constraint(equalToConstant: 12).isActive = true
        self.ratings.bottomAnchor.constraint(equalTo: self.bottomAnchor,
                                             constant: Self.ratingsBottomSpace).isActive = true
        self.ratings.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
    }

    // MARK: - Image layer
    /// Image container
    private var imageContainer: CALayer = CALayer()
    /// Image shadow
    private var imageShadow: CALayer = CALayer()

    /// Width of the image border
    private static let imageBorderWidth: CGFloat = 1.0
    /// Spacing between edges of the cell and the thumbnail
    private static let edgeImageSpacing: CGFloat = 6.0
    /// Radius of the image shadow
    private static let imageShadowRadius: CGFloat = 4.0
    /// Opacity of the image shadow
    private static let imageShadowOpacity: Float = 0.2
    /// Image shadow offset
    private static let imageShadowOffset: CGSize = CGSize(width: 4, height: -4)

    /**
     * Sets up the image container.
     *
     * Note that the image container has no constraints; we set these later.
     */
    private func setUpImageContainer() {
        // prepare the container itself
        self.imageContainer.delegate = self
        self.imageContainer.name = "imageContainer"

        self.imageContainer.borderWidth = Self.imageBorderWidth
        self.imageContainer.borderColor = NSColor(named: "LibraryItemImageFrame")?.cgColor

        self.imageContainer.masksToBounds = true
        self.imageContainer.contentsGravity = .resizeAspectFill

        self.layer!.addSublayer(self.imageContainer)

        // create the shadow that sits below the image
        self.imageShadow.delegate = self

        self.imageShadow.shadowColor = NSColor(named: "LibraryItemImageShadow")?.cgColor
        self.imageShadow.shadowRadius = Self.imageShadowRadius
        self.imageShadow.shadowOffset = Self.imageShadowOffset
        self.imageShadow.shadowOpacity = Self.imageShadowOpacity

        self.imageShadow.backgroundColor = NSColor(named: "LibraryItemImageBackground")?.cgColor

        self.imageShadow.constraints = [
            // align horizontally to the image container
            CAConstraint(attribute: .minX, relativeTo: "imageContainer",
                         attribute: .minX),
            CAConstraint(attribute: .maxX, relativeTo: "imageContainer",
                         attribute: .maxX),

            // align vertically to the image container
            CAConstraint(attribute: .minY, relativeTo: "imageContainer",
                         attribute: .minY),
            CAConstraint(attribute: .maxY, relativeTo: "imageContainer",
                         attribute: .maxY)
        ]

        self.layer!.insertSublayer(self.imageShadow, below: self.imageContainer)
    }

    /**
     * Determines the orientation of the image container to use (landscape/portrait) and updates its
     * constraints accordingly.
     */
    private func resizeImageContainer() {
        guard let size = self.image?.rotatedImageSize else {
            return
        }

        // should we use the portrait mode calculations?
        if size.height >= size.width {
            let ratio = size.width / size.height

            self.imageContainer.constraints = [
                // align to the exact center of the container
                CAConstraint(attribute: .midX, relativeTo: "superlayer",
                             attribute: .midX),

                // spacing to top container
                CAConstraint(attribute: .maxY, relativeTo: "topInfoBox",
                             attribute: .minY,
                             offset: -Self.edgeImageSpacing),
                // spacing to bottom of cell
                CAConstraint(attribute: .minY,
                             relativeTo: self.showBottomInfo ? "bottomInfoBox" : "superlayer",
                             attribute: .maxY,
                             offset: Self.edgeImageSpacing),

                // image width ratio
                CAConstraint(attribute: .width, relativeTo: "imageContainer",
                             attribute: .height, scale: ratio, offset: 0)
            ]
        }
        // otherwise, use landscape mode calculation
        else {
            let ratio = size.height / size.width
            
            var yOffset: CGFloat = 0
            
            if self.showBottomInfo {
                yOffset = -((Self.topInfoHeight - Self.ratingsAreaHeight)/2) + ((Self.edgeImageSpacing) / 2)
            } else {
                yOffset = -((Self.topInfoHeight)/2) + (Self.edgeImageSpacing / 2)
            }

            self.imageContainer.constraints = [
                // align to the exact center of the container
                CAConstraint(attribute: .midY, relativeTo: "superlayer",
                             attribute: .midY, offset: yOffset),

                // spacing to left side of cell
                CAConstraint(attribute: .minX, relativeTo: "superlayer",
                             attribute: .minX, offset: Self.edgeImageSpacing),
                // spacing to right side of cell
                CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                             attribute: .maxX, offset: -Self.edgeImageSpacing),

                // image height ratio
                CAConstraint(attribute: .height, relativeTo: "imageContainer",
                             attribute: .width, scale: ratio, offset: 0)
            ]
        }
    }

    // MARK: - Layer Delegate
    /**
     * Allows layers to inherit the content scale from our parent window. This means text will be the right
     * size, for example.
     */
    func layer(_ layer: CALayer, shouldInheritContentsScale newScale: CGFloat, from window: NSWindow) -> Bool {
        return true
    }

    /**
     * Gets the action the given layer should use to process a particular event. We always return nil, as to
     * disable implicit animations.
     */
    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        guard self.defaultsChanged else {
            return NSNull()
        }
        
        // default animation
        return nil
    }

    // MARK: - Selection
    /// Is the cell selected? Set by collection view item.
    var isSelected: Bool = false {
        didSet {
            self.updateColors()
        }
    }

    /**
     * Updates the colors used by the UI. This handles both the selection and mouseover (hover) states.
     */
    private func updateColors(_ display: Bool = true) {
        // gate hover style on user's preference
        let isHovering = (self.isHovering && UserDefaults.standard.gridCellHoverStyle)
        
        // handle the selected cell state
        if self.isSelected {
            // selected and hovering over cell
            if isHovering {
                self.layer?.backgroundColor = NSColor(named: "LibraryItemHoverSelectedBackground")?.cgColor
                self.seqNumlabel.foregroundColor = NSColor(named: "LibraryItemHoverSelectedSequence")?.cgColor
            }
            // selected, but not hovering over
            else {
                self.layer?.backgroundColor = NSColor(named: "LibraryItemSelectedBackground")?.cgColor
                self.seqNumlabel.foregroundColor = NSColor(named: "LibraryItemSelectedSequence")?.cgColor
            }
        }
        // handle the non-selected case
        else {
            // hovering over cell
            if isHovering {
                self.layer?.backgroundColor = NSColor(named: "LibraryItemHoverBackground")?.cgColor
                self.seqNumlabel.foregroundColor = NSColor(named: "LibraryItemHoverSequence")?.cgColor
            }
            // not selected nor hovering over
            else {
                self.layer?.backgroundColor = NSColor(named: "LibraryItemBackground")?.cgColor
                self.seqNumlabel.foregroundColor = NSColor(named: "LibraryItemSequence")?.cgColor
            }
        }

        // force redisplay if needed
        if display {
            self.setNeedsDisplay(self.bounds)
        }
    }

    // MARK: - Context menu
    /// Whether the context menu outline should be shown
    var drawContextOutline: Bool = false {
        didSet {
            self.updateContextOutline()
        }
    }

    /**
     * Updates whether the context menu outline is drawn.
     */
    private func updateContextOutline() {
        if self.drawContextOutline {
            self.layer?.borderColor = NSColor.selectedControlColor.cgColor
            self.layer?.borderWidth = 4
        } else {
            self.layer?.borderWidth = 0
        }

        // force redraw
        self.setNeedsDisplay(self.bounds)
    }

    // MARK: - Mouse Interaction
    /// Mouseover tracking area
    private var trackingArea: NSTrackingArea! = nil
    /// Indicates whether the mouse is currently above this view. Only set on UI thread
    private var isHovering: Bool = false {
        didSet {
            self.updateColors()
            self.updateHoverControls()
        }
    }

    /**
     * Sets up the tracking area for this view. It's used to get notified whenever we have the mouse enter or
     * leave the view so we can highlight ourselves.
     */
    private func setUpTrackingArea() {
        self.trackingArea = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
              owner: self, userInfo: nil)

        self.addTrackingArea(self.trackingArea)
    }

    /**
     * Mouse entered the view.
     */
    override func mouseEntered(with event: NSEvent) {
        self.isHovering = true
    }
    /**
     * Mouse exited the view.
     */
    override func mouseExited(with event: NSEvent) {
        self.isHovering = false
    }
    
    /**
     * Updates the visibility of controls that are gated on mouse-over.
     */
    private func updateHoverControls() {
        let d = UserDefaults.standard
        
        // ratings control
        if d.gridCellRatingsOnHoverOnly {
            self.ratings.isHidden = !self.isHovering
        }
    }


    // MARK: - State updating
    /// Token for the thumbnail observer
    private var thumbObserverToken: UUID? = nil
    
    /**
     * View is about to appear; finalize the UI prior to display.
     */
    func prepareForDisplay() {
        // reset hover state
        self.isHovering = false
    }
    /**
     * View has disappeared.
     */
    func didDisappear() {

    }

    /**
     * Clears UI state and cancels any outstanding thumb requests.
     */
    override func prepareForReuse() {
        if let image = self.image {
            ThumbHandler.shared.cancel(image)
        }
        self.image = nil

        self.removeThumbObserver()
        self.refreshThumb()
    }

    /**
     * Updates the information displayed on the layer.
     */
    func updateContents() {
        // Populate with information from the image
        if self.image != nil {
            let format = Self.localized("seqnum.format")
            self.seqNumlabel.string = String(format: format,
                                             self.sequenceNumber)
            
            self.updateImageDetail()

            // update the image
            self.resizeImageContainer()
        }
        // Otherwise, clear info
        else {
            self.nameLabel.string = ""
            self.detailLabel.string = ""
            self.seqNumlabel.string = "?"

            self.imageContainer.contents = nil
        }
    }
    
    // MARK: Image Detail
    /// What's shown in the name field?
    private var nameType: Int = 0
    
    /// Raw format type for the first row of detail info
    private var detailTypeFirst: Int = 0
    /// Raw format type for the second row of detail info
    private var detailTypeSecond: Int = 0
    
    /**
     * Updates the name and detail labels based on the user's configuration.
     */
    private func updateImageDetail() {
        // what should be displayed in the name field?
        self.nameLabel.string = self.infoString(for: self.nameType,
                                                font: Self.nameFont,
                                                Self.nameAttributes)
        
        // format subtitle string
        let first = self.infoString(for: self.detailTypeFirst,
                                    font: Self.detailFont,
                                    Self.detailAttributes)
        let second = self.infoString(for: self.detailTypeSecond,
                                     font: Self.detailFont,
                                     Self.detailAttributes)
        
        if first.length > 0, second.length > 0 {
            let line = NSMutableAttributedString(attributedString: first)
            line.append(NSAttributedString(string: "\n"))
            line.append(second)
            
            self.detailLabel.string = line
        } else if first.length > 0, (second.length == 0) {
            self.detailLabel.string = first
        }
    }
    
    // MARK: Ratings
    /// KVO observer on image's rating
    private var ratingsObserver: NSKeyValueObservation?
    
    /**
     * Ensures the ratings control stays in sync with the image by means of a KVO observer.
     */
    private func updateBindings() {
        // remove old observer
        self.ratingsObserver = nil
        
        guard let image = self.image else {
            return
        }
        
        // observe ratings
        self.ratingsObserver = image.observe(\.rating, options: .initial)
        { image, _ in
            guard self.image == image else {
                return
            }
            
            self.ratings.intValue = Int32(image.rating)
        }
    }
    
    /**
     * Updates the rating of the current image.
     */
    @IBAction private func setRating(_ sender: Any) {
        guard let image = self.image,
              let indicator = sender as? NSLevelIndicator else {
            DDLogWarn("Invalid image (\(String(describing: self.image))) or sender (\(sender)): \(self)")
            return
        }
        
        let newRating = Int16(min(5, max(0, indicator.intValue)))
        
        if image.rating != newRating {
            image.rating = newRating
        }
    }

    // MARK: - Thumbnail support
    /**
     * Updates the thumbnail displayed in the cell. This tries to avoid thumbnail requests at all costs with
     * some pretty simple logic:
     *
     * 1. If we already have a thumbnail surface, AND it is for the current image, exit.
     * 2. If the existing thumbnail surface is larger, or up to 20% smaller, than the currently required thumb
     * size, exit.
     * 3. If no image is set, clear any existing surface.
     */
    private func refreshThumb() {
        // release surface if image is nil
        guard let image = self.image else {
            if let surface = self.surface {
                surface.decrementUseCount()

                self.surfaceImageId = nil
                self.surface = nil
            }

            self.removeThumbObserver()
            
            return
        }
        
        // if no surface, request a thumb
        if self.surface == nil {
            return self.requestThumb(image)
        }

        // request a new thumb if image id changed
        if let imageId = self.image.identifier, let surfaceId = self.surfaceImageId, imageId != surfaceId {
            return self.requestThumb(image)
        }
    }

    /**
     * Removes an existing thumb observer.
     */
    private func removeThumbObserver() {
        if let token = self.thumbObserverToken {
            ThumbHandler.shared.removeThumbObserver(token)
            self.thumbObserverToken = nil
        }
    }
    
    /**
     * Adds a thumb observer for the given image.
     */
    private func addThumbObserver(_ image: Image) {
        self.thumbObserverToken = ThumbHandler.shared.addThumbObserver(imageId: image.identifier!)
        { [weak self, weak image] (libId, imageId) in
            DDLogVerbose("Thumb updated for \(imageId)")
            
            if let image = image, let cell = self {
                DispatchQueue.main.async {
                    cell.requestThumb(image)
                }
            }
        }
    }
    
    /**
     * Actually performs the request for a new thumbnail image.
     */
    private func requestThumb(_ image: Image) {
        // set up an observer
        self.removeThumbObserver()
        self.addThumbObserver(image)
        
        // calculate the pixel size needed
        var thumbSize = self.imageContainer.bounds.size
        thumbSize.width = thumbSize.width * self.imageContainer.contentsScale
        thumbSize.height = thumbSize.height * self.imageContainer.contentsScale
        
        // fake a size for initial load when view isn't yet visible
        if thumbSize == .zero {
            thumbSize = CGSize(width: 300, height: 300)
        }

        // request the image id
        ThumbHandler.shared.get(image, thumbSize, { (imageId, result) in
            // bail if image id doesn't match or the image was clared out
            if imageId != image.identifier! || self.image == nil || self.image?.identifier != imageId {
                // release the surface
                do {
                    let surface = try result.get()
                    surface.decrementUseCount()
                } catch {
                    DDLogError("Failed to get thumbnail for \(imageId): \(error)")
                }

                return
            }

            // handle the result
            switch result {
                // success! set the image
                case .success(let surface):
                    DispatchQueue.main.async {
                        // release the old surface if we have one
                        if let surface = self.surface {
                            surface.decrementUseCount()
                            self.surface = nil
                        }

                        // set our new surface
                        self.surfaceImageId = imageId
                        self.surface = surface
                        self.surface.incrementUseCount()

                        // lastly, actually display it
                        self.imageContainer.contents = surface
                        self.setNeedsDisplay(self.bounds)
                    }

                // something went wrong getting the thumbnail
                case .failure(let error):
                    DDLogError("Failed to get thumbnail for \(imageId): \(error)")

                    // set a… caution icon ig
                    DispatchQueue.main.async {
                        self.imageContainer.contents = nil
                        self.setNeedsDisplay(self.bounds)
                }
            }
        })
    }
    
    // MARK: - Layout settings
    /// KVOs for observing user defaults changes on layout keys
    private var kvos: [NSKeyValueObservation] = []
    
    /// Are we currently updating the UI because of user defaults changes?
    private var defaultsChanged: Bool = false
    
    /**
     * Registers user defaults observers to track changes.
     */
    private func installDefaultsObservers() {
        let d = UserDefaults.standard
        
        // grid sequence number display
        kvos.append(d.observe(\.gridCellSequenceNumber) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateFromDefaults()
            }
        })
        
        // image detail display and format
        kvos.append(d.observe(\.gridCellImageDetail) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateFromDefaults()
            }
        })
        kvos.append(d.observe(\.gridCellImageDetailFormat) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateFromDefaults()
            }
        })
        
        // ratings
        kvos.append(d.observe(\.gridCellImageRatings) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateFromDefaults()
            }
        })
        kvos.append(d.observe(\.gridCellRatingsOnHoverOnly) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateFromDefaults()
            }
        })
        
        // set up the initial state
        self.updateFromDefaults()
    }
    
    /**
     * Updates the cell's layout based on the current defaults.
     *
     * - Note: This should be executed on the main thread ONLY
     */
    private func updateFromDefaults() {
        let d = UserDefaults.standard
        
        self.defaultsChanged = true
        
        // is sequence number shown?
        self.seqNumlabel.isHidden = !d.gridCellSequenceNumber
        
        // header format and header visibility
        self.nameLabel.isHidden = !d.gridCellImageDetail
        self.detailLabel.isHidden = !d.gridCellImageDetail
        
        self.nameLabel.superlayer!.isHidden = (!d.gridCellImageDetail &&
                                               !d.gridCellSequenceNumber)
        
        self.nameType = d.gridCellImageDetailFormat["title"] as! Int
        self.detailTypeFirst = d.gridCellImageDetailFormat["row1"] as! Int
        self.detailTypeSecond = d.gridCellImageDetailFormat["row2"] as! Int
        
        // are the ratings controls shown?
        if d.gridCellImageRatings && d.gridCellRatingsOnHoverOnly {
            self.showBottomInfo = true
            self.ratings.isHidden = !self.isHovering
        } else {
            self.showBottomInfo = d.gridCellImageRatings
            self.ratings.isHidden = !d.gridCellImageRatings
        }
        
        // update frames and image details
        if self.image != nil {
            self.resizeImageContainer()
            self.updateImageDetail()
        }
        
        // redraw cell
        self.setNeedsDisplay(self.bounds)
        
        self.defaultsChanged = false
    }
    
    // MARK: Format types
    /**
     * Date formatter used to render the capture/import date.
     */
    private static var dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .medium
        return fmt
    }()
    
    /**
     * Size formatter used for file size
     */
    private static var sizeFormatter: ByteCountFormatter = {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt
    }()
    
    /**
     * Date component formatter used to display exposure times
     */
    private static var exposureTimeFormatter: DateComponentsFormatter = {
        let fmt = DateComponentsFormatter()
        fmt.allowsFractionalUnits = true
        fmt.collapsesLargestUnit = true
        fmt.unitsStyle = .brief
        fmt.formattingContext = .standalone
        fmt.allowedUnits = [.second, .minute, .hour]
        return fmt
    }()
    
    /**
     * Various pieces of information that may be displayed in stringified form in the cell.
     */
    private enum DetailType: Int {
        /// Blank (empty string)
        case blank = 0
        
        /// Image caption
        case caption = 1
        
        /// Original file name
        case fileName = 2
        /// Original file type
        case fileType = 3
        /// Original file size (bytes)
        case fileSize = 5
        
        /// Image dimensions (pixels)
        case dimensions = 12
        
        /// Lens information
        case lensInfo = 6
        /// Camera
        case cameraInfo = 7
        /// Exposure settings
        case exposure = 8
        
        /// Capture date
        case captureDate = 9
        /// Import date
        case importDate = 10
        
        /// Geotagged location
        case location = 11
    }
    
    /**
     * Returns a stringified version of the image detail item with the given raw value.
     *
     * If a `DetailType` case could not be constructed, an error string is shown.
     */
    private func infoString(for detail: Int, font: NSFont, _ defaultAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        // default attributes
        let attributes: [NSAttributedString.Key: Any] = defaultAttributes.merging([
            .font: font,
        ]) { $1 }
        
        // ensure the passed in detail value was allowed
        guard let type = DetailType(rawValue: detail) else {
            return NSAttributedString(string: String(format: "<unknown format %d>", detail),
                                      attributes: attributes)
        }
        // ensure an image was loaded
        guard let image = self.image else {
            return NSAttributedString()
        }
        
        // can it be handled with a plain string
        if let plain = self.infoString(for: type, image) {
            return NSAttributedString(string: plain, attributes: attributes)
        }
        
        // these are the attributed return values
        switch type {
        case .exposure:
            // get aperture
            var aperture: String = ""
            
            if let apertureVal = image.metadata?.exif?.fNumber {
                let format = Self.localized("exposure.aperture")
                aperture = String(format: format, apertureVal.value)
            }
            
            // build string for exposure time
            var exposure = NSAttributedString()
            
            if let expTime = image.metadata?.exif?.exposureTime {
                let val = expTime.value
                
                // less than 1 sec? format as fraction
                if val < 1.0 {
                    // get a font that creates fractions
                    let features = [
                        // create fractions automatically
                        [
                            NSFontDescriptor.FeatureKey.typeIdentifier: kFractionsType,
                            NSFontDescriptor.FeatureKey.selectorIdentifier: kDiagonalFractionsSelector,
                        ],
                    ]
                    
                    var desc = font.fontDescriptor
                    desc = desc.addingAttributes([
                        .featureSettings: features
                    ])
                    let newFont = NSFont(descriptor: desc, size: font.pointSize) ?? font
                    
                    let attribs = defaultAttributes.merging([
                        .font: newFont
                    ]) { $1 }
                    
                    // format the string
                    let format = Self.localized("exposure.time.fraction")
                    let plain = String(format: format, expTime.numerator,
                                       expTime.denominator)
                    
                    exposure = NSAttributedString(string: plain,
                                                  attributes: attribs)
                }
                // between 1 and 60 seconds?
                else if (1.0..<60.0).contains(val) {
                    let format = Self.localized("exposure.time.seconds")
                    let plain = String(format: format, expTime.value)
                    
                    exposure = NSAttributedString(string: plain, attributes: attributes)
                }
                // format as a string (x sec, 1.5 min, 2 hours, etc)
                else {
                    if let str = Self.exposureTimeFormatter.string(from: val) {
                        let format = Self.localized("exposure.time.formatted")
                        let plain = String(format: format, str)
                        
                        exposure = NSAttributedString(string: plain, attributes: attributes)
                    }
                }
            }
            
            // get sensitivity/ISO (TODO: proper name) string
            var sensitivity: String = ""
            
            if let sensitivityArr = image.metadata?.exif?.iso,
               let value = sensitivityArr.first {
                let format = Self.localized("exposure.sensitivity")
                sensitivity = String(format: format, Double(value), "ISO")
            }
            
            // ensure we've got at least some info and format
            guard !aperture.isEmpty || exposure.length > 0 ||
                  !sensitivity.isEmpty else {
                return NSAttributedString(string: Self.localized("exposure.none"),
                                          attributes: attributes)
            }
            
            // build teh final string
            let out = NSMutableAttributedString()
            
            out.append(exposure)
            out.append(NSAttributedString(string: aperture,
                                          attributes: attributes))
            out.append(NSAttributedString(string: sensitivity,
                                          attributes: attributes))
            
            return out
            
        // shouldn't get here
        default:
            return NSAttributedString(string: String(format: "Unhandled type %d", type.rawValue))
        }
    }
    
    /**
     * Returns a plain info string. Most infos do not require attributes so they're implemented here with a
     * plain string.
     */
    private func infoString(for type: DetailType, _ image: Image) -> String? {
        switch type {
        case .blank:
            return ""
            
        case .caption:
            return "<TODO: caption>"
            
        case .fileName:
            return image.name ?? Self.localized("placeholder.fileName")
        case .fileType:
            let url = image.getUrl(relativeTo: self.libraryUrl)
            guard let info = try? url?.resourceValues(forKeys: [.typeIdentifierKey]),
                  let utiStr = info.typeIdentifier,
                  let uti = UTType(utiStr),
                  let typeStr = uti.localizedDescription else {
                return Self.localized("placeholder.fileType")
            }
            return typeStr
        case .fileSize:
            let url = image.getUrl(relativeTo: self.libraryUrl)
            guard let info = try? url?.resourceValues(forKeys: [.fileSizeKey]),
                  let size = info.fileSize else {
                return Self.localized("placeholder.fileSize")
            }
            
            return Self.sizeFormatter.string(fromByteCount: Int64(size))
            
        case .dimensions:
            let size = image.rotatedImageSize
            return String(format: Self.localized("dimensions.format"),
                          size.width, size.height)
            
        case .lensInfo:
            // try to get the lens name
            var lensName = ""
    
            if let lens = image.lens, let name = lens.name {
                lensName = name
            } else {
                lensName = Self.localized("placeholder.lensInfo.noLens")
            }
            
            // TODO: extract focal length
            let focalLength: Double? = nil
            
            // format the string
            if let focalLength = focalLength {
                let format = Self.localized("lens.format.full")
                return String(format: format, lensName, focalLength)
            } else {
                let format = Self.localized("lens.format.nameOnly")
                return String(format: format, lensName)
            }
        case .cameraInfo:
            // try to get the camera name
            if let camera = image.camera, let name = camera.name {
                return name
            } else {
                return Self.localized("placeholder.cameraInfo")
            }
            
        case .captureDate:
            guard let date = image.dateCaptured else {
                return Self.localized("placeholder.captureDate")
            }
            return Self.dateFormatter.string(from: date)
        case .importDate:
            guard let date = image.dateImported else {
                return Self.localized("placeholder.importDate")
            }
            return Self.dateFormatter.string(from: date)
            
        case .location:
            return "<TODO: location>"
            
        default:
            return nil
        }
    }
    
    /**
     * Returns a localized string with the given identifier.
     */
    private static func localized(_ identifier: String) -> String {
        return NSLocalizedString(identifier,
                                 tableName: "LibraryCollectionItemView",
                                 bundle: Bundle.main,
                                 value: "",
                                 comment: "")
    }
}
