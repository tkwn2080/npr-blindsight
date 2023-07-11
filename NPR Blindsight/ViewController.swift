//
//  ViewController.swift
//  NPR Blindsight
//
//  Created by bird on 3/16/23.
//

import Foundation
import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var detectionRequest: VNCoreMLRequest!
    private var detectionModel: VNCoreMLModel!
    private let detectionThreshold: Float = 0.80
    private let synthesizer = AVSpeechSynthesizer()
    private var lastDetectedDenomination: String?
    private var lastDetectedTimestamp: TimeInterval = 0
    private let announcementCooldown: TimeInterval = 3.0 // Adjust this value to control the minimum time between announcements
    private let supportedDenominations = ["5", "10", "20", "50", "100", "500", "1000"]
    private var cameraPreviewView: UIView!


    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupModel()
        setupCamera()
    }

    
    func setupCamera() {
        let captureSession = AVCaptureSession()
        captureSession.sessionPreset = .photo

        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let captureDeviceInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("Failed to set up capture device")
            return
        }
        
        captureSession.addInput(captureDeviceInput)

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        captureSession.addOutput(videoOutput)

        // Create a camera preview container view
        cameraPreviewView = UIView(frame: view.bounds)
        view.addSubview(cameraPreviewView)

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = cameraPreviewView.bounds
        cameraPreviewView.layer.addSublayer(previewLayer)

        // Set up an observer for AVCaptureSession's didStartRunning notification
        NotificationCenter.default.addObserver(forName: NSNotification.Name.AVCaptureSessionDidStartRunning, object: captureSession, queue: nil) { _ in
            DispatchQueue.main.async {
                do {
                    try captureDevice.lockForConfiguration()
                    if captureDevice.hasTorch && captureDevice.isTorchAvailable {
                        captureDevice.torchMode = .on
                    }
                    captureDevice.unlockForConfiguration()
                } catch {
                    print("Error turning on flash: \(error)")
                }
            }
        }

        captureSession.startRunning()
    }


    
    func setupModel() {
        do {
            let modelConfig = MLModelConfiguration()
            self.detectionModel = try VNCoreMLModel(for: NPRBlindsightFNv1 (configuration: modelConfig).model)
            self.detectionRequest = VNCoreMLRequest(model: detectionModel, completionHandler: handleDetection)
        } catch {
            fatalError("Failed to initialize the CoreML model: \(error)")
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let request = detectionRequest else { return }
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        do {
            try requestHandler.perform([request])
        } catch {
            print("Failed to perform detection request: \(error)")
        }
    }
    
    func drawBoundingBoxes(_ results: [VNRecognizedObjectObservation]) {
        // Remove existing bounding boxes
        for subview in view.subviews {
            if subview is BoundingBoxView {
                subview.removeFromSuperview()
            }
        }
        
        // Draw new bounding boxes
        for result in results {
            let boundingBoxView = BoundingBoxView(frame: view.bounds)
            boundingBoxView.confidence = result.confidence
            boundingBoxView.confidenceThreshold = detectionThreshold
            boundingBoxView.rect = VNImageRectForNormalizedRect(result.boundingBox, Int(view.bounds.width), Int(view.bounds.height))
            view.addSubview(boundingBoxView)
        }
    }

    
    func handleDetection(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
        
        DispatchQueue.main.async {
            self.drawBoundingBoxes(results)
        }
        
        let currentTime = Date().timeIntervalSince1970
        let mostConfidentResult = results.max(by: { $0.confidence < $1.confidence })
        
        if let result = mostConfidentResult,
           result.confidence >= detectionThreshold,
           let identifier = result.labels.first?.identifier,
           (lastDetectedDenomination != identifier || (currentTime - lastDetectedTimestamp) > announcementCooldown) {
            
            lastDetectedDenomination = identifier
            lastDetectedTimestamp = currentTime
            DispatchQueue.main.async {
                self.announceBanknoteDenomination(identifier)
            }
        }
    }

    
    func generateHapticFeedback(for denomination: String) {
        guard let index = supportedDenominations.firstIndex(of: denomination) else { return }
        
        let tapCount = index + 1
        let tapInterval = DispatchTimeInterval.milliseconds(500)
        let hapticGenerator = UIImpactFeedbackGenerator(style: .heavy)
        
        func tapRepeatedly(count: Int) {
            if count > 0 {
                hapticGenerator.impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + tapInterval) {
                    tapRepeatedly(count: count - 1)
                }
            }
        }
        
        tapRepeatedly(count: tapCount)
    }


    
    func announceBanknoteDenomination(_ denomination: String) {
        let speechUtterance = AVSpeechUtterance(string: "Detected \(denomination) rupees")
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechUtterance.rate = AVSpeechUtteranceMaximumSpeechRate * 0.5
        synthesizer.speak(speechUtterance)

        generateHapticFeedback(for: denomination)
    }

        
    }
