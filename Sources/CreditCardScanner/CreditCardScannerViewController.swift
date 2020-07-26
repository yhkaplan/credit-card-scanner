//  Created by josh on 2020/07/23.

#if canImport(UIKit)
#if canImport(AVFoundation)
#if canImport(Vision)
import UIKit
import AVFoundation
import Vision
import Reg

/// Conform to this delegate to get notified of key events
public protocol CreditCardScannerViewControllerDelegate: AnyObject {
    /// Called user taps the cancel button. Comes with a default implementation for UIViewControllers.
    /// - Warning: The viewController does not auto-dismiss. You must dismiss the viewController
    func creditCardScannerViewControllerDidCancel(_ viewController: CreditCardScannerViewController)
    /// Called when an error is encountered
    func creditCardScannerViewController(_ viewController: CreditCardScannerViewController, didErrorWith error: CreditCardScannerError)
    /// Called when finished successfully
    /// - Note: successful finish does not guarentee that all credit card info can be extracted
    func creditCardScannerViewController(_ viewController: CreditCardScannerViewController, didFinishWith card: CreditCard)
}

public extension CreditCardScannerViewControllerDelegate where Self: UIViewController {
    func creditCardScannerViewControllerDidCancel(_ viewController: CreditCardScannerViewController) {
        viewController.dismiss(animated: true)
    }
}

///
open class CreditCardScannerViewController: UIViewController {

    // MARK: - Subviews and layers
    /// View representing live camera
    private let cameraView = CameraView()
    /// View representing the cutout rectangle to align card with
    open var cutoutView = UIView()
    /// View that appears when matching data is found
//    open var dataView = UILabel() // TODO: rename to dataLabel?
    /// Mask layer that covering area around camera view
    open var maskLayer = CAShapeLayer()
    /// Green boxes that appear when data matching that necessary appears
    private var boxLayers: [CAShapeLayer] = []

    // MARK: - Vision-related
    public lazy var request = VNRecognizeTextRequest(completionHandler: recognizeTextHandler)

    private weak var delegate: CreditCardScannerViewControllerDelegate? // TODO: pass in initializer

    // MARK: - Capture related
    private var captureDevice: AVCaptureDevice?
    private let captureSession = AVCaptureSession()
    private let captureSessionQueue = DispatchQueue(
        label: "com.yhkaplan.credit-card-scanner.captureSessionQueue"
    )

    @objc private dynamic var deviceInput: AVCaptureDeviceInput!
    private let photoOutput = AVCapturePhotoOutput()

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

    public init(delegate: CreditCardScannerViewControllerDelegate) {
        self.delegate = delegate

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
        _ = request

        let gesture = UITapGestureRecognizer(target: self, action: #selector(takePhoto))
        cutoutView.addGestureRecognizer(gesture)

//        dataView.font = .monospacedSystemFont(ofSize: 30.0, weight: .regular)
//        dataView.backgroundColor = .white
//        dataView.textColor = .black
//        dataView.isHidden = true
//        dataView.textAlignment = .center
//        dataView.numberOfLines = 0

        layoutSubviews()

        // Set up preview view.
        cameraView.session = captureSession

        // Set up cutout view.
//        cutoutView.backgroundColor = UIColor.gray.withAlphaComponent(0.6)
//        maskLayer.backgroundColor = UIColor.clear.cgColor
//        maskLayer.fillRule = .evenOdd
//        cutoutView.layer.mask = maskLayer

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        default: fatalError()
        }

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

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        captureSessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
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


    @objc func takePhoto() {
        let photoSettings = AVCapturePhotoSettings()
        photoSettings.isHighResolutionPhotoEnabled = true
//        videoDataOutput

        captureSessionQueue.async { [weak self] in
            guard let strongSelf = self else { return }
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            settings.photoQualityPrioritization = .quality
            self?.photoOutput.capturePhoto(with: settings, delegate: strongSelf) // TODO: does this work?
        }

    }

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

//        dataView.translatesAutoresizingMaskIntoConstraints = false
//        view.addSubview(dataView)
//        NSLayoutConstraint.activate([
//            dataView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//            dataView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//        ])
    }

    func callErrorDelegate(kind: CreditCardScannerError.Kind, underlyingError: Error? = nil) {
        delegate?.creditCardScannerViewController(self, didErrorWith: .init(kind: .cameraSetup, underlyingError: underlyingError))
    }

    func setupCamera() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        do {
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                DispatchQueue.main.async { [weak self] in self?.callErrorDelegate(kind: .cameraSetup )}
                return
            }

            let deviceInput = try AVCaptureDeviceInput(device: videoDevice)
            guard captureSession.canAddInput(deviceInput) else {
                // TODO: call some error delegate or completion handler here?
                DispatchQueue.main.async { [weak self] in self?.callErrorDelegate(kind: .cameraSetup )}
                return
            }

            captureSession.addInput(deviceInput)
            self.deviceInput = deviceInput

            DispatchQueue.main.async { [weak self] in
                var initialVideoOrientation: AVCaptureVideoOrientation = .portrait
                if let deviceOrientation = self?.currentOrientation,
                    deviceOrientation != .unknown,
                    let videoOrientation = AVCaptureVideoOrientation(deviceOrientation: deviceOrientation) {
                    initialVideoOrientation = videoOrientation
                }

                self?.cameraView.videoPreviewLayer.connection?.videoOrientation = initialVideoOrientation
            }


            guard captureSession.canAddOutput(photoOutput) else {
                DispatchQueue.main.async { [weak self] in self?.callErrorDelegate(kind: .cameraSetup )}
                return
            }

            captureSession.addOutput(photoOutput)

            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality

            captureSession.commitConfiguration()

        } catch {
            DispatchQueue.main.async { [weak self] in self?.callErrorDelegate(kind: .cameraSetup, underlyingError: error) }
            // TODO: cleanup here
        }
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
//        var numFrame = cutout
//        numFrame.origin.y += numFrame.size.height
//        dataView.frame = numFrame
    }

    func recognizeTextHandler(request: VNRequest, error: Error?) {
        var data: [String] = []
        var greenBoxes: [CGRect] = [] // Shows words that might be serials

        // too narrow (more spaces???)
//        let creditCardNumber: Regex = #"^(?:4[0-9]{12}(?:[0-9]{3})?|[25][1-7][0-9]{14}|6(?:011|5[0-9][0-9])[0-9]{12}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|(?:2131|1800|35\d{3})\d{11})$"#
        let creditCardNumber = #"(\d{4}\h+\d{4}\h+\d{4}\h+\d{4})"#
        let twoDigits = #"(\d{2})"#
        let date = twoDigits + #"\/"# + twoDigits
        // mrs, mr
        let wordsToSkip = ["mastercard", "jcb", "visa", "express", "bank",/* "card", */"platinum", "reward"] // TODO: add `card` back in
        // These may be contained in the date strings, so ignore them only for names
        let invalidNames = ["expiration", "valid", "since", "from", "until", "month", "year"]
        let name = #"([A-z]{2,}\h([A-z.]+\h)?[A-z]{2,})"#
        // TODO: strip these words? valid,thru,expiration

        guard let results = request.results as? [VNRecognizedTextObservation] else { return }

        var creditCard = CreditCard(number: nil, name: nil, date: nil)

        let maxCandidates = 1
        for result in results { // TODO: process text here
            guard
                let candidate = result.topCandidates(maxCandidates).first,
                candidate.confidence > 0.1
            else { continue }

            // TODO: grab entire candidate string, then search inside it for matching regexes
            // the reason being that cards have prefixes like `Valid Through` etc
            let string = candidate.string
            print(string)

            let containsWordToSkip = wordsToSkip.contains { string.lowercased().contains($0) }
            if containsWordToSkip { print(string + " was skipped"); continue }

            if string == "12/20" {
                print("here")
            }

            if let cardNumber = Regex(creditCardNumber).firstMatch(in: string) {
                print("cardNumber: " + cardNumber)
                creditCard.number = cardNumber

            } else if string =~ Regex(date) {
                let matches = Regex(twoDigits).matches(in: string)
                let month = matches.first.flatMap(Int.init)
                let year = matches.last.flatMap(Int.init)
                print("Date: " + DateComponents(year: year, month: month).description)
                creditCard.date = DateComponents(year: year, month: month)

            } else if let name = Regex(name).firstMatch(in: string) {
                let containsInvalidName = invalidNames.contains { name.lowercased().contains($0)}
                if containsInvalidName { print("Invalid name" + name); continue }
                print("Name: " + name)
                creditCard.name = name

            } else {
                continue
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            self?.delegate?.creditCardScannerViewController(strongSelf, didFinishWith: creditCard)
        }
    }

    func showMatches(string: String) {
        // Found a definite match.
        // Stop the camera synchronously to ensure that no further buffers are
        // received. Then update the number view asynchronously.
        captureSessionQueue.sync { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async { [weak self] in
//                self?.dataView.text = string
//                self?.dataView.isHidden = false
            }
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

extension CreditCardScannerViewController: AVCapturePhotoCaptureDelegate {
    public func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async { [weak self] in self?.callErrorDelegate(kind: .photoProcessing, underlyingError: error) }
            return
        }

        guard let photoData = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { [weak self] in self?.callErrorDelegate(kind: .photoProcessing) }
            return
        }

        // Configure for running in real-time.
        request.recognitionLevel = .accurate // TODO: use photo or another thread?

        // Language correction won't help recognizing credit card info. It also
        // makes recognition slower.
        request.usesLanguageCorrection = false
        // Only run on the region of interest for maximum speed.
        // request.regionOfInterest = regionOfInterest // TODO: incorrect

        let requestHandler = VNImageRequestHandler(
            data: photoData,
            orientation: textOrientation,
            options: [:]
        )

        do {
            try requestHandler.perform([request])
        } catch {
            DispatchQueue.main.async { [weak self] in self?.callErrorDelegate(kind: .photoProcessing, underlyingError: error) }
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
