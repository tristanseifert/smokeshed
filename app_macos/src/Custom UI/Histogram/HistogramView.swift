//
//  HistogramView.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

import Cocoa
import CocoaLumberjackSwift
import Waterpipe

/**
 * Also known as Mr. Histogram Sr, this view renders a histogram from an image.
 */
class HistogramView: NSView, CALayerDelegate {
    override var isFlipped: Bool {
        return true
    }
    
    /// Notification observers to be removed on dealloc
    private var noteObs: [NSObjectProtocol] = []
    
    // MARK: - Initialization
    /// Container for the shape layers
    private var curveContainer: CALayer!
    /// Curve layer for the red channel
    private var rLayer: CAShapeLayer!
    /// Curve layer for the green channel
    private var gLayer: CAShapeLayer!
    /// Curve layer for the blue channel
    private var bLayer: CAShapeLayer!
    /// Curve layer for the luminance channel
    private var yLayer: CAShapeLayer!
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.commonInit()
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.commonInit()
    }
    
    /**
     * Cleans up any observers we added.
     */
    deinit {
        self.noteObs.forEach(NotificationCenter.default.removeObserver)
    }
    
    /**
     * Sets up all layers and the initial paths.
     */
    private func commonInit() {
        let c = NotificationCenter.default
        
        // observe bounds changes so we can update the paths
        self.postsFrameChangedNotifications = true
        self.noteObs.append(c.addObserver(forName: NSView.frameDidChangeNotification, object: self,
                                          queue: nil, using: self.updatePaths(_:)))
        
        // set up layers (stacked in B -> G -> R -> Y) order
        self.wantsLayer = true
        self.layer?.delegate = self
        
        self.curveContainer = CALayer()
        self.curveContainer.delegate = self
        self.curveContainer.masksToBounds = true
        self.curveContainer.frame = self.bounds
        
        self.rLayer = self.shapeLayer(for: .r)
        self.gLayer = self.shapeLayer(for: .g)
        self.bLayer = self.shapeLayer(for: .b)
        self.yLayer = self.shapeLayer(for: .y)
        
        self.curveContainer?.addSublayer(self.yLayer)
        self.curveContainer?.insertSublayer(self.rLayer, above: self.yLayer)
        self.curveContainer?.insertSublayer(self.gLayer, above: self.rLayer)
        self.curveContainer?.insertSublayer(self.bLayer, above: self.gLayer)
        
        self.layer?.addSublayer(self.curveContainer)
        
        self.layOutSublayers()
    }
    
    /**
     * Creates a shape layer for the given color.
     */
    private func shapeLayer(for component: Component) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.delegate = self
        
        layer.lineJoin = .round
        layer.lineWidth = 1
        layer.masksToBounds = true
        
        layer.strokeColor = Self.componentStrokeMap[component]!.cgColor
        layer.fillColor = Self.componentFillMap[component]!.cgColor
        
        layer.path = self.makeZeroPath()

        return layer
    }
    
    /**
     * Updates the bounds of the sublayers.
     */
    private func layOutSublayers() {
        let frame = self.bounds
        let curveFrame = frame.insetBy(dx: 1, dy: 1)
    
        DDLogInfo("Frame for curves: \(curveFrame)")
        
        DispatchQueue.main.async {
            self.curveContainer.frame = frame
            self.rLayer.frame = curveFrame
            self.gLayer.frame = curveFrame
            self.bLayer.frame = curveFrame
            self.yLayer.frame = curveFrame
        }
    }
    
    // MARK: - Layer Delegate
    /**
     * Allows layers to inherit the content scale from our parent window.
     */
    func layer(_ layer: CALayer, shouldInheritContentsScale newScale: CGFloat, from window: NSWindow) -> Bool {
        return true
    }

    /**
     * Gets the action the given layer should use to process a particular event.  Always return nil to disable animations.
     */
    func action(for layer: CALayer, forKey event: String) -> CAAction? {
        return NSNull()
    }

    // MARK: - Drawing
    /**
     * Draws the border around the view.
     */
    override func draw(_ dirtyRect: NSRect) {
        // fill content area
        let content = self.bounds.insetBy(dx: 1, dy: 1)
        
        NSColor(named: "HistogramViewBackground")?.setFill()
        content.fill()
        
        // stroke border
        NSColor(named: "HistogramViewBorder")?.setStroke()
        
        let border = self.bounds.insetBy(dx: 0.5, dy: 0.5)
        let borderPath = NSBezierPath(rect: border)
        
        borderPath.lineWidth = 1
        borderPath.stroke()
    }
    
    /// Enable support for vibrancy in the histogram view.
    override var allowsVibrancy: Bool {
        return true
    }
    
    // MARK: - Paths
    /**
     * Updates the histogram paths when the frame changes.
     */
    private func updatePaths(_ note: Notification?) {
        self.layOutSublayers()
        
        // clear paths if no data
        guard let _ = self.data else {
            self.rLayer.path = self.makeZeroPath()
            self.gLayer.path = self.makeZeroPath()
            self.bLayer.path = self.makeZeroPath()
            self.yLayer.path = self.makeZeroPath()
            return
        }
        
        // otherwise, recalculate paths for data
        DispatchQueue.main.async {
            self.rLayer.path = self.pathForComponent(.r)
            self.gLayer.path = self.pathForComponent(.g)
            self.bLayer.path = self.pathForComponent(.b)
            self.yLayer.path = self.pathForComponent(.y)
        }
    }
    
    /**
     * Creates a "zero" path for a channel.
     */
    private func makeZeroPath() -> CGPath {
        let curveSz = self.bounds.size
        
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: curveSz.height))
        
        for i in 0..<Self.histogramBuckets {
            let x = CGFloat(i) * (curveSz.width / CGFloat(Self.histogramBuckets))
            let pt = NSPoint(x: x, y: curveSz.height)
            
            path.move(to: pt)
        }
        
        path.move(to: NSPoint(x: curveSz.width, y: curveSz.height))
        path.move(to: NSPoint(x: 0, y: curveSz.height))
        
        return path.cgPath
    }
    
    /**
     * Gets a path for the given color channel.
     */
    private func pathForComponent(_ component: Component) -> CGPath {
        let curveSz = self.bounds.insetBy(dx: 1, dy: 1).size
        let data = self.relativeData![component]!
        
        // interpolate the histogram points
        var points: [NSPoint] = [
            NSPoint(x: 0, y: curveSz.height)
        ]
        
        for i in 0..<data.count {
//            let x = CGFloat(i) * (curveSz.width / CGFloat(data.count))
            let x = CGFloat(i) * (curveSz.width / CGFloat(Self.histogramBuckets - 1))
            let y = curveSz.height - ((curveSz.height - 5) * CGFloat(data[i]))

            points.append(NSPoint(x: x, y: y))
        }

        points.append(NSPoint(x: curveSz.width, y: curveSz.height))

        let curve = NSBezierPath()
        curve.interpolateHermite(points)
        return curve.cgPath
    }
    
    // MARK: - Setters
    /// Histogram data currently being displayed
    private var data: HistogramCalculator.HistogramData? = nil
    /// Relative histogram cache
    private var relativeData: [Component: [Double]]? = nil
    
    /**
     * Sets the content of the histogram view to the given histogram data.
     *
     * - Note: This may be called from any queue; all UI altering operations are automagically executed on the main queue.
     */
    func setHistogramData(_ hist: HistogramCalculator.HistogramData?) {
        // handle the "no selection" case
        guard let hist = hist else {
            self.data = nil
            self.relativeData = nil
            
            return DispatchQueue.main.async {
                self.showNoSelection()
            }
        }
        
        // otherwise, calculate a new relative histogram
        self.data = hist
        self.calculateRelativeHistogram(hist)
        
        // then create and set the paths (using animation)
        DispatchQueue.main.async {
            self.rLayer.path = self.pathForComponent(.r)
            self.gLayer.path = self.pathForComponent(.g)
            self.bLayer.path = self.pathForComponent(.b)
            self.yLayer.path = self.pathForComponent(.y)
        }
        
        // TODO: hide 'no selection' UI
    }
    
    /**
     * Calculates the relative (scaled) histogram values for use in generating paths
     */
    private func calculateRelativeHistogram(_ data: HistogramCalculator.HistogramData) {
        // get max value for each of the RGB components
        let rgbMax = [data.redData.max()!, data.greenData.max()!, data.blueData.max()!].max()!
        let lumaMax = data.lumaData.max()!
        
        // create the scaled data
        self.relativeData = [
            .r: data.redData.map({ Double($0) / Double(rgbMax) }),
            .g: data.greenData.map({ Double($0) / Double(rgbMax) }),
            .b: data.blueData.map({ Double($0) / Double(rgbMax) }),
            .y: data.lumaData.map({ Double($0) / Double(lumaMax) }),
        ]
    }
    
    /**
     * Shows the "no selection" UI state.
     *
     * The current histogram is animated to blank, and a "no selection" indicator is displayed.
     */
    private func showNoSelection() {
        DDLogVerbose("Histogram: show no selection UI")
    }
    
    // MARK: - Types
    /// Color components
    enum Component {
        /// Red image channel
        case r
        /// Green image channel
        case g
        /// Blue image channel
        case b
        /// Computed luminance
        case y
    }
    
    // MARK: - Constants
    /// Duration of the interpolation animation between histogram curves
    static let pathAnimationDuration = CGFloat(0.33)
    /// The number of histogram buckets the view expects to display.
    static let histogramBuckets = 256
    
    /// Map of component names to histogram curve fill colors
    private static let componentFillMap: [Component: NSColor] = [
        .r: NSColor(named: "HistogramCurveRedFill")!,
        .g: NSColor(named: "HistogramCurveGreenFill")!,
        .b: NSColor(named: "HistogramCurveBlueFill")!,
        .y: NSColor(named: "HistogramCurveLumaFill")!,
    ]
    
    /// Map of component names to histogram curve strokes
    private static let componentStrokeMap: [Component: NSColor] = [
        .r: NSColor(named: "HistogramCurveRedStroke")!,
        .g: NSColor(named: "HistogramCurveGreenStroke")!,
        .b: NSColor(named: "HistogramCurveBlueStroke")!,
        .y: NSColor(named: "HistogramCurveLumaStroke")!,
    ]
}
