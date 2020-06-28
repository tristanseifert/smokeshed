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
    var image: Image! = nil {
        /**
         * When the image we're representing is changed, it's important that we tell AppKit to redraw us,
         * since we earlier requested to only be redrawn when we demand it.
         */
        didSet {
            self.refreshThumb()
            self.updateContents()
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

    /// Surface object containing the thumbnail image.
    private var surface: IOSurface! = nil
    /// Identifier of the image for which this surface contains the thumbnail.
    private var surfaceImageId: UUID! = nil

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

        self.layer!.addSublayer(self.imageContainer)

        // create the shadow that sits below the image
        self.imageShadow.delegate = self

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

    /**
     * Gets the action the given layer should use to process a particular event. We always return nil, as to
     * disable implicit animations.
     */
    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        // handle image layer content changes with crossfade
/*        if layer.name == "imageContainer" && event == "contents" {
            let trans = CATransition()
            trans.duration = 0.1
            trans.type = .fade

            return trans
        }
*/

        // otherwise, no animation
        return NSNull()
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
        self.nameLabel.string = self.infoString(for: self.nameType)
        
        // format subtitle string
        let first = self.infoString(for: self.detailTypeFirst)
        let second = self.infoString(for: self.detailTypeSecond)
        
        var format = ""
        
        if !first.isEmpty, !second.isEmpty {
            format = Self.localized("detail.2rows")
        } else if !first.isEmpty, second.isEmpty {
            format = Self.localized("detail.1rows")
        }
        
        self.detailLabel.string = String(format: format, first, second)
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
     * Actually performs the request for a new thumbnail image.
     */
    private func requestThumb(_ image: Image) {
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
                DDLogWarn("Received thumbnail for \(imageId) in cell for \(String(describing: self.image?.identifier!))")

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
                        self.imageContainer.contents = NSImage(named: NSImage.cautionName)
                        self.setNeedsDisplay(self.bounds)
                }
            }
        })
    }
    
    // MARK: - Layout settings
    /// KVOs for observing user defaults changes on layout keys
    private var kvos: [NSKeyValueObservation] = []
    
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
        
        // is sequence number shown?
        self.seqNumlabel.isHidden = !d.gridCellSequenceNumber
        
        // header format and header visibility
        self.nameLabel.isHidden = !d.gridCellImageDetail
        self.detailLabel.isHidden = !d.gridCellImageDetail
        
        self.nameType = d.gridCellImageDetailFormat["title"] as! Int
        self.detailTypeFirst = d.gridCellImageDetailFormat["row1"] as! Int
        self.detailTypeSecond = d.gridCellImageDetailFormat["row2"] as! Int
        
        if self.image != nil {
            self.updateImageDetail()
        }
        
        // are the ratings controls shown?
        
        // redraw cell
        self.setNeedsDisplay(self.bounds)
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
//        fmt.calendar = nil
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
    private func infoString(for detail: Int) -> String {
        // ensure the passed in detail value was allowed
        guard let type = DetailType(rawValue: detail) else {
            return String(format: "<unknown format %d>", detail)
        }
        // ensure an image was loaded
        guard let image = self.image else {
            return ""
        }
        
        // find the appropriate string
        switch type {
        case.blank:
            return ""
            
        case .caption:
            return "<TODO: caption>"
            
        case .fileName:
            return image.name ?? Self.localized("placeholder.fileName")
        case .fileType:
            let url = image.url
            guard let info = try? url?.resourceValues(forKeys: [.typeIdentifierKey]),
                  let utiStr = info.typeIdentifier,
                  let uti = UTType(utiStr),
                  let typeStr = uti.localizedDescription else {
                return Self.localized("placeholder.fileType")
            }
            return typeStr
        case .fileSize:
            let url = image.url
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
        case .exposure:
            // get aperture
            var aperture: String = ""
            
            if let apertureVal = image.metadata?.exif?.fNumber {
                let format = Self.localized("exposure.aperture")
                aperture = String(format: format, apertureVal.value)
            }
            
            // build string for exposure time
            var exposure: String = ""
            
            if let expTime = image.metadata?.exif?.exposureTime {
                let val = expTime.value
                
                // less than 1 sec? format as fraction
                if val < 1.0 {
                    let format = Self.localized("exposure.time.fraction")
                    exposure = String(format: format, expTime.numerator,
                                      expTime.denominator)
                }
                // between 1 and 60 seconds?
                else if (1.0..<60.0).contains(val) {
                    let format = Self.localized("exposure.time.seconds")
                    exposure = String(format: format, expTime.value)
                }
                // format as a string (x sec, 1.5 min, 2 hours, etc)
                else {
                    if let str = Self.exposureTimeFormatter.string(from: val) {
                        let format = Self.localized("exposure.time.formatted")
                        exposure = String(format: format, str)
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
            guard !aperture.isEmpty || !exposure.isEmpty ||
                  !sensitivity.isEmpty else {
                return Self.localized("exposure.none")
            }
            
            return String(format: Self.localized("exposure.format"), exposure,
                          aperture, sensitivity)
            
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
