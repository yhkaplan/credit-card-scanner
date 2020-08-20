//  Created by josh on 2020/07/23.

#if canImport(UIKit)
#if canImport(AVFoundation)
import AVFoundation
import UIKit

/// Conform to this delegate to get notified of key events
@available(iOS 13, *)
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

@available(iOS 13, *)
public extension CreditCardScannerViewControllerDelegate where Self: UIViewController {
    func creditCardScannerViewControllerDidCancel(_ viewController: CreditCardScannerViewController) {
        viewController.dismiss(animated: true)
    }
}

@available(iOS 13, *)
open class CreditCardScannerViewController: UIViewController {
    /// public propaties
    public var titleLabelText: String = "Add card"
    public var subtitleLabelText: String = "Line up card within the lines"
    public var cancelButtonTitleText: String = "Cancel"
    public var cancelButtonTitleTextColor: UIColor = .gray
    public var labelTextColor: UIColor = .white
    public var textBackgroundColor: UIColor = .black
    public var cameraViewCreditCardFrameStrokeColor: UIColor = .white
    public var cameraViewMaskLayerColor: UIColor = .black
    public var cameraViewMaskAlpha: CGFloat = 0.7

    // MARK: - Subviews and layers

    /// View representing live camera
    private lazy var cameraView: CameraView = CameraView(
        delegate: self,
        creditCardFrameStrokeColor: self.cameraViewCreditCardFrameStrokeColor,
        maskLayerColor: self.cameraViewMaskLayerColor,
        maskLayerAlpha: self.cameraViewMaskAlpha
    )

    /// Analyzes text data for credit card info
    private lazy var analyzer = ImageAnalyzer(delegate: self)

    private weak var delegate: CreditCardScannerViewControllerDelegate?

    /// The backgroundColor stack view that is below the camera preview view
    private var bottomStackView = UIStackView()
    private var titleLabel = UILabel()
    private var subtitleLabel = UILabel()
    private var cancelButton = UIButton(type: .system)

    // MARK: - Vision-related

    public init(delegate: CreditCardScannerViewControllerDelegate) {
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        layoutSubviews()
        setupLabelsAndButtons()
        AVCaptureDevice.authorize { [weak self] authoriazed in
            // This is on the main thread.
            guard let strongSelf = self else {
                return
            }
            guard authoriazed else {
                strongSelf.delegate?.creditCardScannerViewController(strongSelf, didErrorWith: CreditCardScannerError(kind: .authorizationDenied, underlyingError: nil))
                return
            }
            strongSelf.cameraView.setupCamera()
        }
    }

    override open func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        cameraView.setupRegionOfInterest()
    }
}

@available(iOS 13, *)
private extension CreditCardScannerViewController {
    @objc func cancel(_ sender: UIButton) {
        delegate?.creditCardScannerViewControllerDidCancel(self)
    }

    func layoutSubviews() {
        view.backgroundColor = textBackgroundColor
        // TODO: test screen rotation cameraView, cutoutView
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)
        NSLayoutConstraint.activate([
            cameraView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.heightAnchor.constraint(equalTo: cameraView.widthAnchor, multiplier: CreditCard.heightRatioAgainstWidth, constant: 100),
        ])

        bottomStackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomStackView)
        NSLayoutConstraint.activate([
            bottomStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomStackView.topAnchor.constraint(equalTo: cameraView.bottomAnchor),
        ])

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
        ])

        bottomStackView.axis = .vertical
        bottomStackView.spacing = 16.0
        bottomStackView.isLayoutMarginsRelativeArrangement = true
        bottomStackView.distribution = .equalSpacing
        bottomStackView.directionalLayoutMargins = .init(top: 8.0, leading: 8.0, bottom: 8.0, trailing: 8.0)
        let arrangedSubviews: [UIView] = [titleLabel, subtitleLabel]
        arrangedSubviews.forEach(bottomStackView.addArrangedSubview)
    }

    func setupLabelsAndButtons() {
        titleLabel.text = titleLabelText
        titleLabel.textAlignment = .center
        titleLabel.textColor = labelTextColor
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        subtitleLabel.text = subtitleLabelText
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .preferredFont(forTextStyle: .title3)
        subtitleLabel.textColor = labelTextColor
        subtitleLabel.numberOfLines = 0
        cancelButton.setTitle(cancelButtonTitleText, for: .normal)
        cancelButton.setTitleColor(cancelButtonTitleTextColor, for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
    }
}

@available(iOS 13, *)
extension CreditCardScannerViewController: CameraViewDelegate {
    internal func didCapture(image: CGImage) {
        analyzer.analyze(image: image)
    }

    internal func didError(with error: CreditCardScannerError) {
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.delegate?.creditCardScannerViewController(strongSelf, didErrorWith: error)
            strongSelf.cameraView.stopSession()
        }
    }
}

@available(iOS 13, *)
extension CreditCardScannerViewController: ImageAnalyzerProtocol {
    internal func didFinishAnalyzation(with result: Result<CreditCard, CreditCardScannerError>) {
        switch result {
        case let .success(creditCard):
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.cameraView.stopSession()
                strongSelf.delegate?.creditCardScannerViewController(strongSelf, didFinishWith: creditCard)
            }

        case let .failure(error):
            DispatchQueue.main.async { [weak self] in
                guard let strongSelf = self else { return }
                strongSelf.cameraView.stopSession()
                strongSelf.delegate?.creditCardScannerViewController(strongSelf, didErrorWith: error)
            }
        }
    }
}

@available(iOS 13, *)
extension AVCaptureDevice {
    static func authorize(authorizedHandler: @escaping ((Bool) -> Void)) {
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
