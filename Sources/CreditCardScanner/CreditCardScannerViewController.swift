//  Created by josh on 2020/07/23.

#if canImport(UIKit)
#if canImport(AVFoundation)
#if canImport(Vision)
import UIKit
import AVFoundation

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

open class CreditCardScannerViewController: UIViewController {

    // MARK: - Subviews and layers
    /// View representing live camera
    private lazy var cameraView: CameraView = CameraView(delegate: self)
    /// Analizer
    lazy var analyzationManager = ImageAnalyzer(delegate: self)

    private weak var delegate: CreditCardScannerViewControllerDelegate?

    /// The backgroundColor stack view that is below the camera preview view
    open var bottomStackView = UIStackView()
    open var titleLabel = UILabel()
    open var subtitleLabel = UILabel()
    open var cancelButton = UIButton()

    // MARK: - Vision-related
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
        view.backgroundColor = .black
        AVCaptureDevice.authorize { [weak self] authoriazed in
            guard let strongSelf = self else {
                return
            }
            guard authoriazed else {
                strongSelf.delegate?.creditCardScannerViewController(strongSelf, didErrorWith: CreditCardScannerError.init(kind: .authorizationDenied, underlyingError: nil))
                return
            }

            strongSelf.setupLabelsAndButtons()
            strongSelf.layoutSubviews()
            strongSelf.cameraView.setupCamera()
        }
    }

    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        cameraView.setupRegionOfInterest()
        cameraView.startSession()
    }
}

private extension CreditCardScannerViewController {

    @objc func cancel(_ sender: UIButton) {
        delegate?.creditCardScannerViewControllerDidCancel(self)
    }

    func layoutSubviews() { // TODO: make open for customization?
        // TODO: test screen rotation cameraView, cutoutView
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)
        NSLayoutConstraint.activate([
            cameraView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.heightAnchor.constraint(equalTo: cameraView.widthAnchor, multiplier: 1.8, constant: 0)
        ])

        bottomStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomStackView)
        NSLayoutConstraint.activate([
            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            bottomStackView.topAnchor.constraint(equalTo: cameraView.bottomAnchor),
        ])

        bottomStackView.axis = .vertical
        bottomStackView.spacing = 16.0
        bottomStackView.isLayoutMarginsRelativeArrangement = true
        bottomStackView.directionalLayoutMargins = .init(top: 0, leading: 8.0, bottom: 8.0, trailing: 8.0)
        let arrangedSubviews: [UIView] = [cancelButton]
        arrangedSubviews.forEach(bottomStackView.addArrangedSubview)
    }

    func setupLabelsAndButtons() {
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
    }
}

extension CreditCardScannerViewController: CameraViewDelegate {
    internal func didCapture(image: CGImage) {
        analyzationManager.analyze(image: image)
    }

    internal func didError(with error: CreditCardScannerError) {
        DispatchQueue.main.async {[weak self] in
            guard let strongSelf = self else { return }
            strongSelf.delegate?.creditCardScannerViewController(strongSelf, didErrorWith: error)
            strongSelf.cameraView.stopSession()
        }
    }
}

extension CreditCardScannerViewController: ImageAnalyzerProtocol {
    internal func didFinishAnalyzation(with result: Result<CreditCard, CreditCardScannerError>) {

        switch result {
        case .success(let creditCard):
            DispatchQueue.main.async {[weak self] in
                guard let strongSelf = self else { return }
                strongSelf.cameraView.stopSession()
                strongSelf.delegate?.creditCardScannerViewController(strongSelf, didFinishWith: creditCard)
            }


        case .failure(let error):
            DispatchQueue.main.async {[weak self] in
                guard let strongSelf = self else { return }
                strongSelf.cameraView.stopSession()
                strongSelf.delegate?.creditCardScannerViewController(strongSelf, didErrorWith: error)
            }
        }
    }
}

extension AVCaptureDevice {
    static func authorize(authorizedHandler: @escaping ((Bool) -> Void) ) {

        let mainThreadHandler: ((Bool) -> Void) = { isAuthorized in
            DispatchQueue.main.async {
                authorizedHandler(isAuthorized)
            }
        }

        switch authorizationStatus(for: .video) {
        case .authorized:
            mainThreadHandler(true)
        case .notDetermined:
            requestAccess(for: .video, completionHandler: { granted in
                mainThreadHandler(granted)
            })
        default:
            mainThreadHandler(false)
        }
    }
}

#endif
#endif
#endif



