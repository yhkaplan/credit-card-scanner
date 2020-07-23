//
//  CreditCardScannerViewController.swift
//  CreditCardScannerPackageDescription
//
//  Created by josh on 2020/07/23.
//

#if canImport(UIKit)
#if canImport(AVFoundation)
import UIKit
import AVFoundation

///
open class CreditCardScannerViewController: UIViewController {

    /// View representing live camera
    public let cameraView = CameraView()
    /// View representing the cutout rectangle to align card with
    open var cutoutView = UIView()
    /// View that appears when matching data is found
    open var dataView = UIView()

    private var captureDevice: AVCaptureDevice?
    private let captureSession = AVCaptureSession()
    private let captureSessionQueue = DispatchQueue(label: "com.yhkaplan.credit-card-scanner.captureSessionQueue")

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "com.yhkaplan.credit-card-scanner.videoDataOutputSessionQueue")

    private var bufferAspectRatio: Double = 0.0

    open override func viewDidLoad() {
        super.viewDidLoad()

        view = cameraView // TODO: test screen rotation

        cameraView.session = captureSession

        // Starting the capture session is a blocking call. Perform setup using
        // a dedicated serial dispatch queue to prevent blocking the main thread.
        captureSessionQueue.async { [weak self] in
            self?.setupCamera()
            
            DispatchQueue.main.async {
                // calc region of interest
            }
        }
    }
}

private extension CreditCardScannerViewController {
    func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            // TODO: call some error delegate or completion handler here
            return
        }

        self.captureDevice = captureDevice

        if captureDevice.supportsSessionPreset(.hd4K3840x2160) {
            captureSession.sessionPreset = .hd4K3840x2160
            bufferAspectRatio = 3840.0 / 2160.0
        } else {
            captureSession.sessionPreset = .hd1920x1080
            bufferAspectRatio = 1920.0 / 1080.0
        }

        do {
            let deviceInput = try AVCaptureDeviceInput(device: captureDevice)
            guard captureSession.canAddInput(deviceInput) else {
                // TODO: call some error delegate or completion handler here?
                return
            }

            captureSession.addInput(deviceInput)
            setupVideoDataOutput()

            guard captureSession.canAddOutput(videoDataOutput) else {
                // TODO: call some error delegate or completion handler here?
                return
            }

            captureSession.addOutput(videoDataOutput)

            // NOTE:
            // There is a trade-off to be made here. Enabling stabilization will
            // give temporally more stable results and should help the recognizer
            // converge. But if it's enabled the VideoDataOutput buffers don't
            // match what's displayed on screen, which makes drawing bounding
            // boxes very hard. Disable it in this app to allow drawing detected
            // bounding boxes on screen.
            let videoOutputConnection = videoDataOutput.connection(with: .video)
            videoOutputConnection?.preferredVideoStabilizationMode = .off

            try captureDevice.lockForConfiguration()
            captureDevice.videoZoomFactor = 2
            captureDevice.autoFocusRangeRestriction = .near
            captureDevice.unlockForConfiguration()

            captureSession.startRunning()

        } catch {
            // TODO: call some error delegate or completion handler here
        }
    }

    func setupVideoDataOutput() {
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
    }

}

extension CreditCardScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Implemented in x // TODO:
    }
}


#endif
#endif
