//
//  CameraView.swift
//  CreditCardScannerPackageDescription
//
//  Created by josh on 2020/07/23.
//
#if canImport(UIKit)
#if canImport(AVFoundation)

import UIKit
import AVFoundation
import VideoToolbox

protocol CameraViewDelegate: AnyObject {
    func didCapture(image: CGImage)
    func didError(with: CreditCardScannerError)
}

final class CameraView: UIView {

    weak var delegate: CameraViewDelegate?
    // MARK: - Capture related
    private let captureSessionQueue = DispatchQueue(
        label: "com.yhkaplan.credit-card-scanner.captureSessionQueue"
    )

    // MARK: - Capture related
    private let sampleBufferQueue = DispatchQueue(
        label: "com.yhkaplan.credit-card-scanner.sampleBufferQueue"
    )
    init(delegate: CameraViewDelegate){
        self.delegate = delegate
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    //    /// View representing the cutout rectangle to align card with
    //    open var cutoutView = UIView()

    // MARK: - Region of interest and text orientation
    /// Region of video data output buffer that recognition should be run on.
    /// Gets recalculated once the bounds of the preview layer are known.
    private var regionOfInterest: CGRect?

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
        }
        
        return layer
    }

    var videoSession: AVCaptureSession? {
        get {
            videoPreviewLayer.session
        }
        set {
            videoPreviewLayer.session = newValue
        }
    }

    let semaphore = DispatchSemaphore(value: 1)

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    func setupCamera() {
        captureSessionQueue.async { [weak self] in
            self?._setupCamera()
        }
    }

    private func _setupCamera() {
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                        for: .video,
                                                        position: .back) else {
                                                            delegate?.didError(with: CreditCardScannerError(kind: .cameraSetup))
                                                            return
        }

        do {
            let deviceInput = try AVCaptureDeviceInput(device: videoDevice)
            session.canAddInput(deviceInput)
            session.addInput(deviceInput)
        } catch {
            delegate?.didError(with: CreditCardScannerError(kind: .cameraSetup, underlyingError: error))
        }

        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: sampleBufferQueue)

        guard session.canAddOutput(videoOutput) else {
            delegate?.didError(with: CreditCardScannerError(kind: .cameraSetup))
            return
        }

        session.addOutput(videoOutput)
        session.connections.forEach {
            $0.videoOrientation = .portrait
        }
        session.commitConfiguration()


        DispatchQueue.main.async { [weak self] in
            self?.videoSession = session
            self?.videoSession?.startRunning()
        }
    }

    func setupRegionOfInterest() {
        guard regionOfInterest == nil else { return }
        /// Mask layer that covering area around camera view
        let backLayer = CALayer()
        backLayer.frame = bounds
        backLayer.backgroundColor = UIColor.black.withAlphaComponent(0.8).cgColor

        //  くり抜き部分のframeの計算
        let cuttedWidth: CGFloat = bounds.width - 40
        // クレカの縦横は1:1618の黄金比らしい
        let cuttedHeight: CGFloat = cuttedWidth * 0.6180469716

        let centerVertical = (bounds.height / 2)
        let cuttedY: CGFloat = centerVertical - (cuttedHeight / 2)
        let cuttedX: CGFloat = 20.0

        let cuttedRect = CGRect(x: cuttedX,
                                y: cuttedY,
                                width: cuttedWidth,
                                height: cuttedHeight)

        let maskLayer = CAShapeLayer()
        let path = UIBezierPath(roundedRect: cuttedRect, cornerRadius: 10.0)

        path.append(UIBezierPath(rect: bounds))
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd

        backLayer.mask = maskLayer
        layer.addSublayer(backLayer)

        let imageHeight: CGFloat = 1920
        let imageWidth: CGFloat = 1080

        let ratioHeight = imageHeight / frame.height
        let ratioWidth =  imageWidth / frame.width

        regionOfInterest = CGRect(x: cuttedRect.origin.x * ratioWidth,
                                  y: cuttedRect.origin.y * ratioHeight,
                                  width: cuttedRect.width * ratioWidth,
                                  height: cuttedRect.height * ratioHeight)
    }

}

extension CameraView: AVCaptureVideoDataOutputSampleBufferDelegate {
    // ここにカメラ映像の情報が連続で渡される。
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection){

        // 処理を一つ一つすすめるため、排他制御
        semaphore.wait()
        defer { semaphore.signal() }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            delegate?.didError(with: CreditCardScannerError.init(kind: .capture))
            return
        }

        var cgImage: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)

        guard let fullCameraImage = cgImage,
            let regionOfInterest = regionOfInterest,
            let croppedImage = fullCameraImage.cropping(to: regionOfInterest) else {
                delegate?.didError(with: CreditCardScannerError.init(kind: .capture))
                return
        }

        delegate?.didCapture(image: croppedImage)
    }
}
#endif
#endif
