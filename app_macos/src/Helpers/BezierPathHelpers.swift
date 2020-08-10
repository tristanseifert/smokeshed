//
//  BezierPathHelpers.swift
//  Smokeshed (macOS)
//
//  Created by Tristan Seifert on 20200809.
//

import Cocoa

extension NSBezierPath {
    /// CoreGraphics path representation of this path
    var cgPath: CGPath {
        var closed = false
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0 ..< self.elementCount {
            let type = self.element(at: i, associatedPoints: &points)
            
            switch type {
            case .moveTo:
                path.move(to: points[0])
                
            case .lineTo:
                path.addLine(to: points[0])
                
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
                
            case .closePath:
                closed = true
                path.closeSubpath()
                
            @unknown default:
                break
            }
        }
        
        if !closed {
            path.closeSubpath()
        }
        
        return path
    }
    
    /**
     * Produce a smooth, Hermite-interpolated curve between all of the provided points. This is then appended to the existing path.
     */
    func interpolateHermite(_ points: [NSPoint]) {
        guard !points.isEmpty else {
            return
        }
        
        let alpha = CGFloat(1.0 / 3.0)
        self.move(to: points.first!)
        
        for i in 0..<(points.count - 1) {
            var currentPoint = points[i]
            var nextIndex = (i + 1) % points.count
            var prevIndex = (i == 0) ? points.count - 1 : i - 1
            
            var prevPoint = points[prevIndex]
            var nextPoint = points[nextIndex]
            
            let endPoint = nextPoint
            var mx = CGFloat(0)
            var my = CGFloat(0)
            
            if i > 0 {
                mx = (nextPoint.x - prevPoint.x) / 2.0
                my = (nextPoint.y - prevPoint.y) / 2.0
            } else {
                mx = (nextPoint.x - currentPoint.x) / 2.0
                my = (nextPoint.y - currentPoint.y) / 2.0
            }
            
            let control1 = NSPoint(x: currentPoint.x + mx * alpha, y: currentPoint.y + my * alpha)
            
            // calculate second control point
            currentPoint = points[nextIndex]
            nextIndex = (nextIndex + 1) % points.count
            prevIndex = i
            
            prevPoint = points[prevIndex]
            nextPoint = points[nextIndex]
            
            if i < (points.count - 2) {
                mx = (nextPoint.x - prevPoint.x) / 2.0
                my = (nextPoint.y - prevPoint.y) / 2.0
            } else {
                mx = (currentPoint.x - prevPoint.x) / 2.0
                my = (currentPoint.y - prevPoint.y) / 2.0
            }
            
            let control2 = NSPoint(x: currentPoint.x - mx * alpha, y: currentPoint.y - my * alpha)
            
            self.curve(to: endPoint, controlPoint1: control1, controlPoint2: control2)
        }
    }
}
