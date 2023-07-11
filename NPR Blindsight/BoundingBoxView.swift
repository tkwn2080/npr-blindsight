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
    
    var confidence: VNConfidence = 0.0
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
        
        // Set the color of the bounding box based on the confidence threshold
        let color: UIColor = confidence >= confidenceThreshold ? .green : .red
        color.setStroke()
        
        context.setLineWidth(2.0)
        context.stroke(self.rect)
    }
}
