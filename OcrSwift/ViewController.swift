//
//  ViewController.swift
//  OcrSwift
//
//  Created by Tomas Krejci on 1/5/17.
//  Copyright © 2017 Tomas Krejci. All rights reserved.
//

import UIKit
import CoreMotion
import AVFoundation
import SwiftOCR

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var patchView: UIImageView!
    @IBOutlet weak var licensePlateLabel: UILabel!
    @IBOutlet weak var confidenceProgressView: UIProgressView!

    let motionManager = CMMotionManager()
    let captureSession = AVCaptureSession()
    let videoQueue = DispatchQueue(label: "videoQueue")
    var rotation: Double = 0
    let ocrProcessor = OcrProcessor()
    let swiftOCRInstance   = SwiftOCR()

    override func viewDidLoad() {
        super.viewDidLoad()

        setupVideo()
        setupImu()

        captureSession.startRunning()
    }

    func setupImu() {
        motionManager.deviceMotionUpdateInterval = 1e-2
        motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { (deviceMotion: CMDeviceMotion?, error: Error?) in
            if let gravity = deviceMotion?.gravity {
                self.rotation = atan2(gravity.x, gravity.y) + M_PI
            }
        }
    }

    func setupVideo() {
        let preset = AVCaptureSessionPreset1280x720
        if captureSession.canSetSessionPreset(preset) {
            captureSession.sessionPreset = preset
        }

        let videoDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        let inputDevice = try? AVCaptureDeviceInput(device: videoDevice)
        if inputDevice != nil && captureSession.canAddInput(inputDevice) {
            captureSession.addInput(inputDevice)
        }

        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.setSampleBufferDelegate(self, queue: videoQueue)
        dataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA as UInt32)]
        dataOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(dataOutput) {
            captureSession.addOutput(dataOutput)
        }
        let connection = dataOutput.connection(withMediaType: AVMediaTypeVideo)
        if connection != nil && connection!.isVideoOrientationSupported {
            connection!.videoOrientation = .portrait
            connection!.isVideoMirrored = false
        } else {
            print("Video orientation was not set")
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, from connection: AVCaptureConnection!) {
        var image = imageFromSampleBuffer(sampleBuffer: sampleBuffer)
        image = ocrProcessor.process(image, withRotation: rotation)
        let patchImage = ocrProcessor.licensePlatePatch

        if patchImage != nil {
            swiftOCRInstance.recognize(patchImage!) {recognizedString in
                let statisticallyProcessed = self.ocrProcessor.statisticProcessor(recognizedString)
                let confidence = self.ocrProcessor.statisticConfidence
                DispatchQueue.main.async {
                    self.licensePlateLabel.text = statisticallyProcessed
                    self.confidenceProgressView.progress = confidence
                }
            }
        }



        DispatchQueue.main.async {
            self.imageView.image = image
            self.patchView.image = patchImage
        }
    }

    func imageFromSampleBuffer(sampleBuffer : CMSampleBuffer) -> UIImage
    {
        // Get a CMSampleBuffer's Core Video image buffer for the media data
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        // Lock the base address of the pixel buffer
        CVPixelBufferLockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly);


        // Get the number of bytes per row for the pixel buffer
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer!);

        // Get the number of bytes per row for the pixel buffer
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer!);
        // Get the pixel buffer width and height
        let width = CVPixelBufferGetWidth(imageBuffer!);
        let height = CVPixelBufferGetHeight(imageBuffer!);

        // Create a device-dependent RGB color space
        let colorSpace = CGColorSpaceCreateDeviceRGB();

        // Create a bitmap graphics context with the sample buffer data
        var bitmapInfo: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue
        bitmapInfo |= CGImageAlphaInfo.premultipliedFirst.rawValue & CGBitmapInfo.alphaInfoMask.rawValue
        //let bitmapInfo: UInt32 = CGBitmapInfo.alphaInfoMask.rawValue
        let context = CGContext.init(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo)
        // Create a Quartz image from the pixel data in the bitmap graphics context
        let quartzImage = context?.makeImage();
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer!, CVPixelBufferLockFlags.readOnly);
        
        // Create an image object from the Quartz image
        //let image = UIImage.init(cgImage: quartzImage!);
        let image = UIImage(cgImage: quartzImage!, scale: 1.0, orientation: .up)
        
        return (image);
    }

}

