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
    /// Analyzes text data for credit card info
    lazy var analyzer = ImageAnalyzer(delegate: self)

    private weak var delegate: CreditCardScannerViewControllerDelegate?
    private let customModel: CreditCardScannerCustomModel

    /// The backgroundColor stack view that is below the camera preview view
    open var bottomStackView = UIStackView()
    open var titleLabel = UILabel()
    open var subtitleLabel = UILabel()
    open var cancelButton = UIButton()

    // MARK: - Vision-related
    public init(delegate: CreditCardScannerViewControllerDelegate,
                customModel: CreditCardScannerCustomModel = .init()) {
        self.delegate = delegate
        self.customModel = customModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        layoutSubviews()
        setupLabelsAndButtons()
        AVCaptureDevice.authorize { [weak self] authoriazed in
            // This is on the main thread.
            guard let strongSelf = self else {
                return
            }
            guard authoriazed else {
                strongSelf.delegate?.creditCardScannerViewController(strongSelf, didErrorWith: CreditCardScannerError.init(kind: .authorizationDenied, underlyingError: nil))
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

private extension CreditCardScannerViewController {

    @objc func cancel(_ sender: UIButton) {
        delegate?.creditCardScannerViewControllerDidCancel(self)
    }

    func layoutSubviews() {
        view.backgroundColor = customModel.backgroundColor
        // TODO: test screen rotation cameraView, cutoutView
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cameraView)
        NSLayoutConstraint.activate([
            cameraView.topAnchor.constraint(equalTo: view.topAnchor),
            cameraView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cameraView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cameraView.heightAnchor.constraint(equalTo: cameraView.widthAnchor, multiplier:  CreditCard.heightRatioAgainstWidth, constant: 100)
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
            cancelButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor,constant: -20)
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
        titleLabel.text = customModel.title
        titleLabel.textAlignment = .center
        titleLabel.textColor = customModel.textColor
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)
        subtitleLabel.text = customModel.subText
        subtitleLabel.textAlignment = .center
        subtitleLabel.font = .preferredFont(forTextStyle: .title3)
        subtitleLabel.textColor = customModel.textColor
        subtitleLabel.numberOfLines = 0
        cancelButton.setTitle(customModel.cancelButtonText, for: .normal)
        cancelButton.setTitleColor(customModel.cancelButtonTextColor, for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
    }
}

extension CreditCardScannerViewController: CameraViewDelegate {
    internal func didCapture(image: CGImage) {
        analyzer.analyze(image: image)
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

public struct CreditCardScannerCustomModel {
    let title: String
    let subText: String
    let cancelButtonText: String
    let cancelButtonTextColor: UIColor
    let textColor: UIColor
    let backgroundColor: UIColor


    public init(title: String = "Add card",
                subText: String = "Line up card within the lines",
                cancelButtonText: String = "Cancel",
                cancelButtonTextColor: UIColor = .gray,
                textColor: UIColor = .white,
                backgroundColor: UIColor = .black) {
        self.title = title
        self.subText = subText
        self.cancelButtonText = cancelButtonText
        self.cancelButtonTextColor = cancelButtonTextColor
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }
}

#endif
#endif
#endif

