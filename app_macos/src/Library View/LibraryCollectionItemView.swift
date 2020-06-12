//
//  LibraryCollectionItemView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200609.
//

import Cocoa

import Smokeshop

import Smokeshop
import CocoaLumberjackSwift

/**
 * Renders a single image in the library view collection. For performance reasons, this is done entirely using
 * CALayers rather than views.
 */
class LibraryCollectionItemView: NSView, CALayerDelegate, NSViewLayerContentScaleDelegate {
    /// Image to display info about
    var image: Image! = nil {
        /**
         * When the image we're representing is changed, it's important that we tell AppKit to redraw us,
         * since we earlier requested to only be redrawn when we demand it.
         */
        didSet {
            self.updateLayer()
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
     * Date formatter used to render the capture date.
     */
    private static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()

        formatter.dateStyle = .long
        formatter.timeStyle = .medium

        return formatter
    }()

    /**
     * Initializes a new library collection item view. This prepares the view for layer-based rendering and
     * also sets up these layers.
     */
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        self.optimizeForLayer()
        self.setUpLayers()
        self.setUpTrackingArea()
    }
    /// Decoding this view is not supported
    required init?(coder: NSCoder) {
        return nil
    }

    // MARK: - Layer setup
    /// New and spicy™ content layer
    private lazy var content: CALayer = {
        let layer = CALayer()

        layer.delegate = self
        layer.layoutManager = CAConstraintLayoutManager()
        layer.backgroundColor = NSColor(named: "LibraryItemBackground")?.cgColor

        // disable implicit animations for bounds and position
        layer.actions = [
            "onLayout": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "contents": NSNull(),
        ]

        return layer
    }()

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

        // replace the previous NSView layer
        self.layer = self.content
    }

    // MARK: Borders
    /**
     * Creates the dark (right and bottom) borders.
     */
    private func createDarkBorders() {
        let color = NSColor(named: "LibraryItemDarkBorder")?.cgColor

        // right border
        let right = CALayer()
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
        right.actions = self.content.actions
        self.content.addSublayer(right)

        // bottom border
        let bottom = CALayer()
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
        bottom.actions = self.content.actions
        self.content.addSublayer(bottom)
    }
    /**
     * Creates the light (left and top) borders
     */
    private func createLightBorders() {
        let color = NSColor(named: "LibraryItemLightBorder")?.cgColor

        // left border
        let left = CALayer()
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
        left.actions = self.content.actions
        self.content.addSublayer(left)

        // top border
        let top = CALayer()
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
        top.actions = self.content.actions
        self.content.addSublayer(top)
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
    private static let labelVSpacing: CGFloat = 2.0

    /// Font for the name text
    private static let nameFont: NSFont = NSFont.systemFont(ofSize: 15, weight: .medium)
    /// Font for the details (subtitle) text
    private static let detailFont: NSFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    /// Font for the sequence number
    private static let seqNoFont: NSFont = NSFont.monospacedDigitSystemFont(ofSize: 46, weight: .semibold)

    /// Shadow radius of the name label
    private static let nameShadowRadius: CGFloat = 2
    /// Shadow opacity for the name label
    private static let nameShadowOpacity: Float = 0.15

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
                         offset: LibraryCollectionItemView.topInfoHeight),
            // align top edge to superlayer (minus one for border)
            CAConstraint(attribute: .maxY, relativeTo: "superlayer",
                         attribute: .maxY, offset: -1),
            // align left edge to superlayer (plus one to fit cell border)
            CAConstraint(attribute: .minX, relativeTo: "superlayer",
                         attribute: .minX, offset: 1)
        ]

        self.content.addSublayer(topBox)

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

        self.seqNumlabel.font = LibraryCollectionItemView.seqNoFont
        self.seqNumlabel.fontSize = LibraryCollectionItemView.seqNoFont.pointSize
        self.seqNumlabel.foregroundColor = NSColor(named: "LibraryItemSequence")?.cgColor

        self.seqNumlabel.alignmentMode = .right

        self.seqNumlabel.constraints = [
            // for 46pt font, use 50pt height
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height, scale: 0, offset: 50),
            // align bottom edge to superlayer (with some offset)
            CAConstraint(attribute: .minY, relativeTo: "superlayer",
                         attribute: .minY,
                         offset: LibraryCollectionItemView.labelHSpacing),
            // align right edge to superlayer
            CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                         attribute: .maxX,
                         offset: -LibraryCollectionItemView.labelHSpacing)
        ]

        topBox.addSublayer(self.seqNumlabel)

        // File name label
        self.nameLabel.delegate = self
        self.nameLabel.name = "nameLabel"

        self.nameLabel.font = LibraryCollectionItemView.nameFont
        self.nameLabel.fontSize = LibraryCollectionItemView.nameFont.pointSize
        self.nameLabel.foregroundColor = NSColor(named: "LibraryItemName")?.cgColor

        self.nameLabel.alignmentMode = .left
        self.nameLabel.truncationMode = .end

        self.nameLabel.shadowColor = NSColor(named: "LibraryItemNameShadow")?.cgColor
        self.nameLabel.shadowRadius = LibraryCollectionItemView.nameShadowRadius
        self.nameLabel.shadowOpacity = LibraryCollectionItemView.nameShadowOpacity

        self.nameLabel.constraints = [
            // for 15pt font, use 18pt height
            CAConstraint(attribute: .height, relativeTo: "superlayer",
                         attribute: .height, scale: 0, offset: 18),
            // align top edge to superlayer (with some offset)
            CAConstraint(attribute: .maxY, relativeTo: "superlayer",
                         attribute: .maxY,
                         offset: -LibraryCollectionItemView.labelVSpacing),
            // align right and left edges to superlayer
            CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                         attribute: .maxX,
                         offset: -LibraryCollectionItemView.labelHSpacing),
            CAConstraint(attribute: .minX, relativeTo: "superlayer",
                         attribute: .minX,
                         offset: LibraryCollectionItemView.labelHSpacing)
        ]

        topBox.addSublayer(self.nameLabel)

        // Subtitle (aux info for image)
        self.detailLabel.delegate = self
        self.detailLabel.name = "detailLabel"

        self.detailLabel.font = LibraryCollectionItemView.detailFont
        self.detailLabel.fontSize = LibraryCollectionItemView.detailFont.pointSize
        self.detailLabel.foregroundColor = NSColor(named: "LibraryItemInfo")?.cgColor

        self.detailLabel.alignmentMode = .left
        self.detailLabel.truncationMode = .end

        self.detailLabel.constraints = [
            // align top edge to name, and bottom to superlayer
            CAConstraint(attribute: .maxY, relativeTo: "nameLabel",
                         attribute: .minY,
                         offset: -LibraryCollectionItemView.labelVSpacing),
            CAConstraint(attribute: .minY, relativeTo: "border",
                         attribute: .maxY,
                         offset: LibraryCollectionItemView.labelVSpacing),
            // align left edge to superlayer
            CAConstraint(attribute: .minX, relativeTo: "superlayer",
                         attribute: .minX,
                         offset: LibraryCollectionItemView.labelHSpacing),
            // align right edge to sequence number (with some spacing)
            CAConstraint(attribute: .maxX, relativeTo: "sequenceNumber",
                         attribute: .minX,
                         offset: LibraryCollectionItemView.labelHSpacing)
        ]

        topBox.addSublayer(self.detailLabel)
    }

    // MARK: - Image layer
    /// Image container
    private var imageContainer: CALayer = CALayer()
    /// Image shadow
    private var imageShadow: CALayer = CALayer()

    /// Whether we need to update the image the next time we're displayed
    private var needsImageUpdate: Bool = false

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

        self.imageContainer.borderWidth = LibraryCollectionItemView.imageBorderWidth
        self.imageContainer.borderColor = NSColor(named: "LibraryItemImageFrame")?.cgColor

        self.imageContainer.masksToBounds = true
        self.imageContainer.contentsGravity = .resizeAspectFill

        self.content.addSublayer(self.imageContainer)

        // create the shadow that sits below the image
        self.imageShadow.shadowColor = NSColor(named: "LibraryItemImageShadow")?.cgColor
        self.imageShadow.shadowRadius = LibraryCollectionItemView.imageShadowRadius
        self.imageShadow.shadowOffset = LibraryCollectionItemView.imageShadowOffset
        self.imageShadow.shadowOpacity = LibraryCollectionItemView.imageShadowOpacity

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

        self.content.insertSublayer(self.imageShadow, below: self.imageContainer)
    }

    /**
     * Prepares the image container for rendering of the given image.
     */
    private func updateImageContainer() {
        guard let size = self.image?.imageSize else {
            return
        }

        // should we use the portrait mode calculations?
        if size.height > size.width {
            let ratio = size.width / size.height

            self.imageContainer.constraints = [
                // align to the exact center of the container
                CAConstraint(attribute: .midX, relativeTo: "superlayer",
                             attribute: .midX),

                // spacing to top container
                CAConstraint(attribute: .maxY, relativeTo: "topInfoBox",
                             attribute: .minY,
                             offset: -LibraryCollectionItemView.edgeImageSpacing),
                // spacing to bottom of cell
                CAConstraint(attribute: .minY, relativeTo: "bottomBorder",
                             attribute: .maxY,
                             offset: LibraryCollectionItemView.edgeImageSpacing),

                // image width ratio
                CAConstraint(attribute: .width, relativeTo: "imageContainer",
                             attribute: .height, scale: ratio, offset: 0)
            ]
        }
        // otherwise, use landscape mode calculation
        else {
            let ratio = size.height / size.width

            self.imageContainer.constraints = [
                // align to the exact center of the container
                CAConstraint(attribute: .midY, relativeTo: "superlayer",
                             attribute: .midY,
                             offset: -(LibraryCollectionItemView.topInfoHeight/2)),

                // spacing to left side of cell
                CAConstraint(attribute: .minX, relativeTo: "superlayer",
                             attribute: .minX, offset: LibraryCollectionItemView.edgeImageSpacing),
                // spacing to right side of cell
                CAConstraint(attribute: .maxX, relativeTo: "superlayer",
                             attribute: .maxX, offset: -LibraryCollectionItemView.edgeImageSpacing),

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
        // handle the selected cell state
        if self.isSelected {
            // selected and hovering over cell
            if self.isHovering {
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
            if self.isHovering {
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

    // MARK: - Mouse Interaction
    /// Mouseover tracking area
    private var trackingArea: NSTrackingArea! = nil
    /// Indicates whether the mouse is currently above this view. Only set on UI thread
    private var isHovering: Bool = false {
        didSet {
            self.updateColors()
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


    // MARK: - State updating
    /**
     * View is about to appear; finalize the UI prior to display.
     */
    func prepareForDisplay() {
        // update image if requested
        if self.needsImageUpdate {
            self.updateImageContainer()
            self.needsImageUpdate = false
        }

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
        ThumbHandler.shared.cancel(self.image)

        self.image = nil
    }

    /**
     * Updates the information displayed on the layer.
     */
    override func updateLayer() {
        // Populate with information from the image
        if let image = self.image {
            self.nameLabel.string = image.name

            self.seqNumlabel.string = String(format: "%u", self.sequenceNumber)

            // format subtitle string
            if let date = image.dateCaptured {
                let format = NSLocalizedString("%.0f × %.0f\n%@", comment: "Library collection view item subtitle format (1 = width, 2 = height, 3 = date)")

                let size = image.imageSize
                let dateStr = LibraryCollectionItemView.dateFormatter.string(from: date)

                self.detailLabel.string = String(format: format, size.width, size.height, dateStr)
            }
            // no information about date
            else {
                let format = NSLocalizedString("%.0f × %.0f", comment: "Library collection view item subtitle format without date (1 = width, 2 = height)")

                let size = image.imageSize

                self.detailLabel.string = String(format: format, size.width, size.height)
            }

            // update the image
            self.updateImageContainer()

            var thumbSize = self.imageContainer.bounds.size
            thumbSize.width = thumbSize.width * self.imageContainer.contentsScale
            thumbSize.height = thumbSize.height * self.imageContainer.contentsScale

            ThumbHandler.shared.get(image, thumbSize, { (imageId, result) in
                // bail if image id doesn't match
                if imageId != image.identifier! {
                    DDLogWarn("Received thumbnail for \(imageId) in cell for \(image.identifier!)")
                    return
                }

                // handle the result
                switch result {
                    // success! set the image
                    case .success(let surface):
                        DispatchQueue.main.async {
                            self.imageContainer.contents = surface
                            self.setNeedsDisplay(self.bounds)
                    }

                    // something went wrong getting the thumbnail
                    case .failure(let error):
                        DDLogError("Failed to get thumbnail for \(imageId): \(error)")

                        DispatchQueue.main.async {
                            self.imageContainer.contents = NSImage(named: NSImage.cautionName)
                            self.setNeedsDisplay(self.bounds)
                        }
                }
            })
        }
        // Otherwise, clear info
        else {
            self.nameLabel.string = "<name>"
            self.detailLabel.string = "<size>\n<date captured>"
            self.seqNumlabel.string = "?"

            self.imageContainer.contents = nil
        }
    }
}
