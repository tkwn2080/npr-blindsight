//
//  BoundingBoxView.swift
//  NPR Blindsight
//
//  Created by bird on 3/16/23.
//

import Foundation
import UIKit
import Vision

class BoundingBoxView: UIView {
    var rect: CGRect = .zero {
        didSet {
            setNeedsDisplay()
        }
    }
    
    var confidence: VNConfidence = 0.0 {
        didSet {
            setNeedsDisplay()
        }
    }
    var confidenceThreshold: VNConfidence = 0.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        // Use a gradient color based on confidence value
        let color = colorForConfidence(confidence: CGFloat(confidence))
        color.setStroke()

        context.setLineWidth(2.0)
        context.stroke(self.rect)
    }

    private func colorForConfidence(confidence: CGFloat) -> UIColor {
        // Gradient from red (0.0) to green (1.0)
        let redValue = 1.0 - confidence
        let greenValue = confidence
        let blueValue: CGFloat = 0.0

        return UIColor(red: redValue, green: greenValue, blue: blueValue, alpha: 1.0)
    }
}

