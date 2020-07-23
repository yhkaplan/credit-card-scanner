//  Created by josh on 2020/07/23.

#if canImport(UIKit)
#if canImport(AVFoundation)
#if canImport(Vision)
import UIKit
import AVFoundation
import Vision

///
open class CreditCardScannerViewController: UIViewController {

    // MARK: - Subviews and layers
    /// View representing live camera
    public let cameraView = CameraView()
    /// View representing the cutout rectangle to align card with
    open var cutoutView = UIView()
    /// View that appears when matching data is found
    open var dataView = UILabel() // TODO: rename to dataLabel?
    /// Mask layer that covering area around camera view
    open var maskLayer = CAShapeLayer()
    /// Green boxes that appear when data matching that necessary appears
    private var boxLayers: [CAShapeLayer] = []

    // MARK: - Vision-related
    public var request: VNRecognizeTextRequest!//(completionHandler: recognizeTextHandler)

    // MARK: - Capture related
    private var captureDevice: AVCaptureDevice?
    private let captureSession = AVCaptureSession()
    private let captureSessionQueue = DispatchQueue(
        label: "com.yhkaplan.credit-card-scanner.captureSessionQueue"
    )

    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(
        label: "com.yhkaplan.credit-card-scanner.videoDataOutputSessionQueue"
    )

    // MARK: - Region of interest and text orientation
    /// Region of video data output buffer that recognition should be run on.
    /// Gets recalculated once the bounds of the preview layer are known.
    private var regionOfInterest = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0)
    /// Orientation of text to search for in the region of interest.
    private var textOrientation: CGImagePropertyOrientation = .up

    // MARK: - Coordinate transforms
    // Device orientation. Updated whenever the orientation changes to a
    // different supported orientation.
    private var currentOrientation: UIDeviceOrientation = .portrait
    private var bufferAspectRatio: Double = 0.0
    /// Transform from UI orientation to buffer orientation.
    private var uiRotationTransform = CGAffineTransform.identity
    /// Transform bottom-left coordinates to top-left.
    private var bottomToTopTransform = CGAffineTransform(scaleX: 1.0, y: -1.0)
        .translatedBy(x: 0.0, y: -1.0)
    /// Transform coordinates in ROI to global coordinates (still normalized).
    private var roiToGlobalTransform = CGAffineTransform.identity
    /// Vision -> AVF coordinate transform.
    private var visionToAVFTransform = CGAffineTransform.identity

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        // Set up vision request before letting ViewController set up the camera
        // so that it exists when the first buffer is received.
        request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)

        dataView.font = .monospacedSystemFont(ofSize: 30.0, weight: .regular)
        dataView.textAlignment = .center

        layoutSubviews()

        // Set up preview view.
        cameraView.session = captureSession

        // Set up cutout view.
        cutoutView.backgroundColor = UIColor.gray.withAlphaComponent(0.6)
        maskLayer.backgroundColor = UIColor.clear.cgColor
        maskLayer.fillRule = .evenOdd
        cutoutView.layer.mask = maskLayer

        // Starting the capture session is a blocking call. Perform setup using
        // a dedicated serial dispatch queue to prevent blocking the main thread.
        captureSessionQueue.async { [weak self] in
            self?.setupCamera()

            // Calculate region of interest now that the camera is setup.
            DispatchQueue.main.async { [weak self] in
                // Figure out initial ROI.
                self?.calculateRegionOfInterest()
            }
        }
    }

    // TODO: solve jitter during screen rotation
    open override func viewWillTransition(
        to size: CGSize,
        with coordinator: UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)

        // Only change the current orientation if the new one is landscape or
        // portrait. You can't really do anything about flat or unknown.
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isPortrait || deviceOrientation.isLandscape {
            currentOrientation = deviceOrientation
        }

        // Handle device orientation in the preview layer.
        if let videoPreviewLayerConnection = cameraView.videoPreviewLayer.connection,
            let newVideoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
            videoPreviewLayerConnection.videoOrientation = newVideoOrientation
        }

        // Orientation changed: figure out new region of interest (ROI).
        calculateRegionOfInterest()
    }

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateCutout()
    }
}

private extension CreditCardScannerViewController {
    func layoutSubviews() {
        // TODO: test screen rotation cameraView, cutoutView, dataView
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)
        NSLayoutConstraint.activate([
            cameraView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cameraView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            // TODO: shoudl this be right to avoid fliping w/ Semitic language?
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        cutoutView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cutoutView)
        NSLayoutConstraint.activate([
            cutoutView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cutoutView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            // TODO: shoudl this be right to avoid fliping w/ Semitic language?
            cutoutView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cutoutView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        dataView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dataView)
        NSLayoutConstraint.activate([
            dataView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dataView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func setupCamera() {
        guard let captureDevice = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
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
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
    }

    func calculateRegionOfInterest() {
        let size = calculateRegionOfInterestSize()

        // Center ROI
        let x = (1.0 - size.width) / 2.0
        let y = (1.0 - size.height) / 2.0
        regionOfInterest.origin = CGPoint(x: x, y: y)
        regionOfInterest.size = size

        // ROI changed, update transform.
        setupOrientationAndTransform()

        // Update the cutout to match the new ROI.
        DispatchQueue.main.async { [weak self] in
            // Wait for the next run cycle before updating the cutout. This
            // ensures that the preview layer already has its new orientation.
            self?.updateCutout()
        }
    }

    func calculateRegionOfInterestSize() -> CGSize {
        // In landscape orientation the desired ROI is specified as the ratio of
        // buffer width to height. When the UI is rotated to portrait, keep the
        // vertical size the same (in buffer pixels). Also try to keep the
        // horizontal size the same up to a maximum ratio.

        let maxPortraitWidth = 0.9
        let desiredRatio: (height: Double, width: Double) = currentOrientation.isPortrait
            ? (height: 0.55, width: 0.7)
            : (height: 0.75, width: 0.7)

        switch currentOrientation {
        case .portrait, .portraitUpsideDown, .unknown: // TODO: is portraitUpsideDown correct?
            let width = min(desiredRatio.width * bufferAspectRatio, maxPortraitWidth)
            let height = desiredRatio.height / bufferAspectRatio
            return CGSize(width: width, height: height)

        default:
            return CGSize(width: desiredRatio.width, height: desiredRatio.height)
        }
    }

    /// Recalculate the affine transform between Vision coordinates and AVF coordinates.
    func setupOrientationAndTransform() {
        // Compensate for region of interest.
        let roi = regionOfInterest
        roiToGlobalTransform = CGAffineTransform(translationX: roi.origin.x, y: roi.origin.y)
            .translatedBy(x: roi.width, y: roi.height)

        // Compensate for orientation (buffers always come in the same orientation).
        switch currentOrientation {
        case .landscapeLeft:
            textOrientation = .up
            uiRotationTransform = .identity
        case .landscapeRight:
            textOrientation = .down
            uiRotationTransform = CGAffineTransform(translationX: 1.0, y: 1.0).rotated(by: .pi)
        case .portraitUpsideDown:
            textOrientation = .left
            uiRotationTransform = CGAffineTransform(translationX: 1.0, y: 0.0).rotated(by: .pi / 2.0)
        default: // Default everything else to .portraitUp
            textOrientation = .right
            uiRotationTransform = CGAffineTransform(translationX: 0.0, y: 1.0).rotated(by: -.pi / 2.0)
        }

        // Full Vision ROI to AVF transform.
        visionToAVFTransform = roiToGlobalTransform
            .concatenating(bottomToTopTransform)
            .concatenating(uiRotationTransform)
    }

    func updateCutout() {
        // Figure out where the cutout ends up in layer coordinates
        let roiRectTransform = bottomToTopTransform.concatenating(uiRotationTransform)
        let metadataOutputRect = regionOfInterest.applying(roiRectTransform)
        let cutout = cameraView.videoPreviewLayer.layerRectConverted(fromMetadataOutputRect: metadataOutputRect)

        // Create the mask
        let path = UIBezierPath(rect: cutoutView.frame)
        path.append(.init(rect: cutout))
        maskLayer.path = path.cgPath

        // Move the number view down below the cutout
        var numFrame = cutout
        numFrame.origin.y += numFrame.size.height
        dataView.frame = numFrame
    }

    func recognizeTextHandler(request: VNRequest, error: Error?) {
        var data: [String] = []
        var greenBoxes: [CGRect] = [] // Shows words that might be serials

        guard let results = request.results as? [VNRecognizedTextObservation] else { return }

        let maxCandidates = 1
        for result in results { // TODO: process text here
            guard let candidate = result.topCandidates(maxCandidates).first else { continue }

            print(candidate.string)
            let range = candidate.string.range(of: candidate.string)!
            if let box = try? candidate.boundingBox(for: range)?.boundingBox {
                greenBoxes.append(box)
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.show(boxes: greenBoxes, color: UIColor.green.cgColor)
        }
    }

    func show(boxes: [CGRect], color: CGColor) {
        let layer = cameraView.videoPreviewLayer
        removeBoxes()
        boxes.forEach { box in
            let metadataOutputRect = box.applying(visionToAVFTransform)
            let rect = layer.layerRectConverted(fromMetadataOutputRect: metadataOutputRect)
            draw(rect: rect, color: color)
        }
    }

    func draw(rect: CGRect, color: CGColor) {
        let layer = CAShapeLayer()
        layer.opacity = 0.5
        layer.borderColor = color
        layer.borderWidth = 1.0
        layer.frame = rect
        boxLayers.append(layer)
        cameraView.videoPreviewLayer.insertSublayer(layer, at: 1)
    }

    func removeBoxes() {
        boxLayers.forEach { $0.removeFromSuperlayer() }
        boxLayers.removeAll()
    }
}

extension CreditCardScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // Configure for running in real-time.
        request.recognitionLevel = .fast
        // Language correction won't help recognizing credit card info. It also
        // makes recognition slower.
        request.usesLanguageCorrection = false
        // Only run on the region of interest for maximum speed.
        request.regionOfInterest = regionOfInterest

        let requestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: textOrientation,
            options: [:]
        )

        do {
            try requestHandler.perform([request])
        } catch {
            // TODO: error handling
        }
    }
}

// MARK: - Utility extensions

fileprivate extension AVCaptureVideoOrientation {
    init?(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeRight
        case .landscapeRight: self = .landscapeLeft
        default: return nil
        }
    }
}

#endif
#endif
#endif
