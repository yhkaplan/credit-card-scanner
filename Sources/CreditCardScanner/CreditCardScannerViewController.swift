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
    /// Mask layer that covering area around camera view
    open var maskLayer = CAShapeLayer()
    /// The backgroundColor stack view that is below the camera preview view
    open var bottomStackView = UIStackView()
    open var titleLabel = UILabel()
    open var subtitleLabel = UILabel()
    open var cancelButton = UIButton()
    open var takePhotoButton = UIButton()

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

    open override var shouldAutorotate: Bool { false }

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

        layoutSubviews()
        setupLabelsAndButtons()

        // Set up preview view.
        cameraView.session = captureSession

        // Set up cutout view.
        cutoutView.backgroundColor = UIColor.gray.withAlphaComponent(0.6)
        maskLayer.backgroundColor = UIColor.clear.cgColor
        maskLayer.fillRule = .evenOdd
        cutoutView.layer.mask = maskLayer

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

    open override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        updateCutout()
    }
}

private extension CreditCardScannerViewController {

    @objc func cancel(_ sender: UIButton) {
        delegate?.creditCardScannerViewControllerDidCancel(self)
    }

    @objc func takePhoto(_ sender: UIButton) {
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

    func layoutSubviews() { // TODO: make open for customization?
        // TODO: test screen rotation cameraView, cutoutView
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)
        NSLayoutConstraint.activate([
            cameraView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        cutoutView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cutoutView)
        NSLayoutConstraint.activate([
            cutoutView.topAnchor.constraint(equalTo: view.topAnchor),
            cutoutView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            // TODO: shoudl this be right to avoid fliping w/ Semitic language?
            cutoutView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        bottomStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomStackView)
        NSLayoutConstraint.activate([
            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomStackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottomStackView.heightAnchor.constraint(equalToConstant: 360.0),

            cameraView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor),
            cutoutView.bottomAnchor.constraint(equalTo: bottomStackView.topAnchor),
        ])

        bottomStackView.axis = .vertical
        bottomStackView.spacing = 16.0
        bottomStackView.isLayoutMarginsRelativeArrangement = true
        bottomStackView.directionalLayoutMargins = .init(top: 8.0, leading: 8.0, bottom: 8.0, trailing: 8.0)
        let arrangedSubviews: [UIView] = [titleLabel, subtitleLabel, UIView(), cancelButton, takePhotoButton]
        arrangedSubviews.forEach(bottomStackView.addArrangedSubview)
    }

    func setupLabelsAndButtons() {
        titleLabel.text = "Add card"
        titleLabel.textAlignment = .center
        titleLabel.font = .preferredFont(forTextStyle: .title1)
        subtitleLabel.text = "Line up card within the lines"
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .preferredFont(forTextStyle: .title3)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        takePhotoButton.setTitle("Scan Card", for: .normal)
        takePhotoButton.addTarget(self, action: #selector(takePhoto), for: .touchUpInside)
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

            // Set aspect ratio (used in ROI calculation)
            let dimensions = videoDevice.activeFormat.highResolutionStillImageDimensions
            bufferAspectRatio = Double(dimensions.width) / Double(dimensions.height)

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
        let maxPortraitWidth = 0.9
        let desiredRatio: (height: Double, width: Double) = (height: 0.65, width: 0.7)

        let width = min(desiredRatio.width * bufferAspectRatio, maxPortraitWidth)
        let height = desiredRatio.height / bufferAspectRatio

        return CGSize(width: width, height: height)
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
    }

    func recognizeTextHandler(request: VNRequest, error: Error?) {
//        let creditCardNumber: Regex = #"^(?:4[0-9]{12}(?:[0-9]{3})?|[25][1-7][0-9]{14}|6(?:011|5[0-9][0-9])[0-9]{12}|3[47][0-9]{13}|3(?:0[0-5]|[68][0-9])[0-9]{11}|(?:2131|1800|35\d{3})\d{11})$"#
        let creditCardNumber: Regex = #"(\d{4}\h+\d{4}\h+\d{4}\h+\d{4})"#
        let twoDigits = #"(\d{2})"#
        let date = Regex(twoDigits + #"\/"# + twoDigits)
        // mrs, mr
        let wordsToSkip = ["mastercard", "jcb", "visa", "express", "bank",/* "card", */"platinum", "reward"] // TODO: add `card` back in
        // These may be contained in the date strings, so ignore them only for names
        let invalidNames = ["expiration", "valid", "since", "from", "until", "month", "year"]
        let name: Regex = #"([A-z]{2,}\h([A-z.]+\h)?[A-z]{2,})"#
        // TODO: strip these words? valid,thru,expiration

        guard let results = request.results as? [VNRecognizedTextObservation] else { return }

        var creditCard = CreditCard(number: nil, name: nil, date: nil)

        let maxCandidates = 1
        for result in results { // TODO: process text here
            guard
                let candidate = result.topCandidates(maxCandidates).first,
                candidate.confidence > 0.1
            else { continue }

            let string = candidate.string

            let containsWordToSkip = wordsToSkip.contains { string.lowercased().contains($0) }
            if containsWordToSkip { continue }

            if let cardNumber = creditCardNumber.firstMatch(in: string) {
                creditCard.number = cardNumber

            } else if string =~ date {
                let matches = Regex(twoDigits).matches(in: string)
                let month = matches.first.flatMap(Int.init)
                let year = matches.last.flatMap(Int.init)
                creditCard.date = DateComponents(year: year, month: month)

            } else if let name = name.firstMatch(in: string) {
                let containsInvalidName = invalidNames.contains { name.lowercased().contains($0)}
                if containsInvalidName { continue }
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
        request.regionOfInterest = regionOfInterest

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
