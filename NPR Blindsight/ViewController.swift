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
    private let detectionThreshold: Float = 0.85
    private let synthesizer = AVSpeechSynthesizer()
    private var lastDetectedDenomination: String?
    private var lastDetectedTimestamp: TimeInterval = 0
    private let supportedDenominations = ["5", "10", "20", "50", "100", "500", "1000"]
    private var cameraPreviewView: UIView!
    
    private var isInCooldownPeriod = false
    private let announcementCooldown: TimeInterval = 2.0
    
    private var isFlashlightInCooldown = false
    private let flashlightCooldown: TimeInterval = 10.0

    private var detectionBuffer: [String] = []
    private let detectionBufferSize = 10
    
    private var captureSession: AVCaptureSession?

    
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupModel()
        setupCamera()
    }
    
    
    //WELCOME MESSAGE
    override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            showFirstTimeInstructions()
        }

    private func isFirstTimeOpeningApp() -> Bool {
        return !UserDefaults.standard.bool(forKey: "hasCompletedFirstTimeInstructions")
    }

    private func showFirstTimeInstructions() {
        if isFirstTimeOpeningApp() {
            // Pause any ongoing processes like detection
            pauseDetection()

            // Delay the presentation of the alert to give the app time to load
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                // Ensure that self is still around and not nil
                guard let strongSelf = self else { return }

                // Create an alert
                let alert = UIAlertController(title: "Welcome", message: "Tap 'OK' to hear instructions.", preferredStyle: .alert)

                // Add an action for the user to dismiss the alert and hear instructions
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    strongSelf.playAudioInstructions()
                }))

                // Present the alert
                strongSelf.present(alert, animated: true, completion: nil)

                // Set the flag so this alert won't be shown a second time
                UserDefaults.standard.set(true, forKey: "hasCompletedFirstTimeInstructions")
            }
        }
    }

    private func playAudioInstructions() {
        let instructions = "Welcome to NPR Blind-sight. This app will help you identify Nepali banknotes. Point your camera at a banknote, and the app will tell you the denomination and provide haptic feedback. Tap anywhere to dismiss this message and start using the app."
        let speechUtterance = AVSpeechUtterance(string: instructions)
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(speechUtterance)
        
        // Set the synthesizer delegate to self
        synthesizer.delegate = self
    }

    
    
    private func pauseDetection() {
        captureSession?.stopRunning()
    }
    
    private func resumeDetection() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // We check if the session is not already running to avoid attempting to start it while it's running
            if let captureSession = self?.captureSession, !captureSession.isRunning {
                captureSession.startRunning()
            }
        }
    }
    
    
    
    //APP FUNCTIONALITIES
    func setupCamera() {
        captureSession = AVCaptureSession()
        guard let captureSession = captureSession else { return }
        captureSession.sessionPreset = .photo
        
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let captureDeviceInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            print("Failed to set up capture device")
            return
        }
        
        if captureSession.canAddInput(captureDeviceInput) {
            captureSession.addInput(captureDeviceInput)
        } else {
            print("Failed to add capture device input")
            return
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            print("Failed to add video output")
            return
        }
        
        cameraPreviewView = UIView(frame: view.bounds)
        view.addSubview(cameraPreviewView)
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = cameraPreviewView.bounds
        previewLayer.videoGravity = .resizeAspectFill
        cameraPreviewView.layer.addSublayer(previewLayer)
        
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
        
        // Start the capture session in the background
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
    }

    
    
    func calculateAverageBrightness(pixelBuffer: CVPixelBuffer) -> Float {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extentVector = CIVector(x: ciImage.extent.origin.x, y: ciImage.extent.origin.y, z: ciImage.extent.size.width, w: ciImage.extent.size.height)
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ciImage, kCIInputExtentKey: extentVector])!
        let outputImage = filter.outputImage!
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull!])
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        let brightness = (Float(bitmap[0]) + Float(bitmap[1]) + Float(bitmap[2])) / 3.0 / 255.0
        return brightness
    }

    func toggleFlashlight(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch, device.torchMode != (on ? .on : .off) else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            print("Flashlight could not be used: \(error)")
        }
    }
    
    func handleFlashlightState(shouldTurnOn: Bool) {
        guard !isFlashlightInCooldown else { return }

        toggleFlashlight(on: shouldTurnOn)
        isFlashlightInCooldown = true

        DispatchQueue.main.asyncAfter(deadline: .now() + flashlightCooldown) {
            self.isFlashlightInCooldown = false
        }
    }


    
    
    func setupModel() {
        do {
            let modelConfig = MLModelConfiguration()
            // Disable the experimental MLE5Engine
            modelConfig.setValue(1, forKey: "experimentalMLE5EngineUsage")

            // Use the automatically generated model class
            let model = try best(configuration: modelConfig)
            self.detectionModel = try VNCoreMLModel(for: model.model)
            self.detectionRequest = VNCoreMLRequest(model: detectionModel, completionHandler: handleDetection)
        } catch {
            fatalError("Failed to initialize the CoreML model with custom configuration: \(error)")
        }
    }


    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard !isInCooldownPeriod, let pixelBuffer: CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let request = detectionRequest else { return }

        // Calculate the average brightness of the current frame
        let averageBrightness = calculateAverageBrightness(pixelBuffer: pixelBuffer)
        let minimumBrightnessThreshold: Float = 0.2 // Set your desired threshold here

        // Check if the frame is bright enough for object detection
        guard averageBrightness >= minimumBrightnessThreshold else {
            // Frame is too dark, skip object detection
            return
        }

        // Handle flashlight state based on brightness
        let lowLightThreshold: Float = 0.4
        handleFlashlightState(shouldTurnOn: averageBrightness < lowLightThreshold)

        // Proceed with object detection
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
            boundingBoxView.confidence = VNConfidence(CGFloat(result.confidence))
            boundingBoxView.rect = VNImageRectForNormalizedRect(result.boundingBox, Int(view.bounds.width), Int(view.bounds.height))
            view.addSubview(boundingBoxView)
        }
    }
    
    
    func handleDetection(request: VNRequest, error: Error?) {
        guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
        
        DispatchQueue.main.async {
            self.drawBoundingBoxes(results)
        }
        
        let mostConfidentResult = results.max(by: { $0.confidence < $1.confidence })
        
        if let result = mostConfidentResult, result.confidence >= detectionThreshold,
           let identifier = result.labels.first?.identifier {
            
            // Calculate the size of the bounding box
            let boundingBoxSize = result.boundingBox.size
            let minBoundingBoxSize: CGFloat = 0.15 // Set your desired threshold here

            // Check if the bounding box is large enough
            guard boundingBoxSize.width >= minBoundingBoxSize && boundingBoxSize.height >= minBoundingBoxSize else {
                // Bounding box is too small, skip announcement
                return
            }
            
            // Update the detection buffer
            updateDetectionBuffer(with: identifier)
            
            // Check if the detection is stable
            if isDetectionStable() {
                DispatchQueue.main.async {
                    if self.isInCooldownPeriod == false {
                        self.startCooldownPeriod()
                        if identifier.contains("other") {
                            self.announceForeignCurrency()
                        } else {
                            self.announceBanknoteDenomination(identifier)
                        }
                    }
                }
            }
        }
    }

    
    private func updateDetectionBuffer(with detection: String) {
        detectionBuffer.append(detection)
        if detectionBuffer.count > detectionBufferSize {
            detectionBuffer.removeFirst()
        }
    }

    private func isDetectionStable() -> Bool {
        guard detectionBuffer.count == detectionBufferSize else { return false }
        let firstDetection = detectionBuffer[0]
        return detectionBuffer.allSatisfy { $0 == firstDetection }
    }


        
        
    func startCooldownPeriod() {
        isInCooldownPeriod = true
        DispatchQueue.main.asyncAfter(deadline: .now() + announcementCooldown) {
            self.isInCooldownPeriod = false
        }
    }
    
    
    func announceForeignCurrency() {
        let speechUtterance = AVSpeechUtterance(string: "Foreign currency")
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechUtterance.rate = AVSpeechUtteranceMaximumSpeechRate * 0.5
        synthesizer.speak(speechUtterance)
    }
    
    
    func announceBanknoteDenomination(_ denomination: String) {
        let speechUtterance = AVSpeechUtterance(string: "\(denomination) rupees")
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        speechUtterance.rate = AVSpeechUtteranceMaximumSpeechRate * 0.5
        synthesizer.speak(speechUtterance)
        
        generateHapticFeedback(for: denomination)
    }


    func generateHapticFeedback(for denomination: String) {
        let hapticPatterns: [String: (Int, Int)] = [
            "5": (1, 0),
            "10": (1, 1),
            "20": (2, 1),
            "50": (4, 1),
            "100": (1, 2),
            "500": (4, 2),
            "1000": (1, 3)
        ]

        guard let pattern = hapticPatterns[denomination] else { return }

        let hardTapGenerator = UIImpactFeedbackGenerator(style: .heavy)
        let softTapGenerator = UIImpactFeedbackGenerator(style: .medium)
        let setInterval = 400

        func tap(count: Int, generator: UIImpactFeedbackGenerator, interval: DispatchTimeInterval) {
            if count > 0 {
                generator.impactOccurred()

                // Delay before the next tap
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) {
                    tap(count: count - 1, generator: generator, interval: interval)
                }
            }
        }

        // Execute hard taps
        tap(count: pattern.0, generator: hardTapGenerator, interval: DispatchTimeInterval.milliseconds(setInterval))

        // Delay before starting soft taps
        DispatchQueue.main.asyncAfter(deadline: .now() + DispatchTimeInterval.milliseconds(setInterval * Int(2))) {
            // Execute soft taps
            tap(count: pattern.1, generator: softTapGenerator, interval: DispatchTimeInterval.milliseconds(setInterval))
        }
    }


        
        
    }


extension ViewController: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // When the speech synthesizer finished, resume detection
        resumeDetection()
    }
}

