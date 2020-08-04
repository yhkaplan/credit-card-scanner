# 💳 CreditCardScanner

CreditCardScanner is a library for taking a photo and scanning credit cards to make adding credit card details to user account more easy. It uses Apple's Vision API for **secure, on-device machine learning** to read following info from a credit card: number, name, and date.

[Example of CreditCardScanner running](example.gif)

## Installing

### Requirements

- iOS 13.0+ (due to Vision APIs first appearing in iOS 13.0)
    - Even if your minimum deployment target is iOS 12 or lower, you can make this an iOS 13.0+ only feature using `canImport` and `@available`

```swift
#if canImport(CreditCardScanner)
import CreditCardScanner
#endif

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 13, *) {
            let creditCardScannerViewController = CreditCardScannerViewController(delegate: self)
            present(creditCardScannerViewController, animated: true)
        } else {
            print("Oh well...")
        }
    }
}

@available(iOS 13, *)
extension ViewController: CreditCardScannerViewControllerDelegate {
```

### Swift Package Manager

- In Xcode, add as Swift package with this URL: `https://github.com/yhkaplan/credit-card-scanner.git`

### Carthage (Experimental)

- Add this to Cartfile: `github "yhkaplan/credit-card-scanner"`
- Follow instructions on [Carthage README](https://github.com/Carthage/Carthage#if-youre-building-for-ios-tvos-or-watchos) for integration **without adding to copy files script**
- This framework is build as a static one for Carthage, that's why it has the settings above
- To build with Carthage yourself, run `swift package generate-xcodeproj` then run

### Cocoapods

- Support coming soon

## Usage

1. Add description to Info.plist `Privacy - Camera Usage Description`
    - Ex: `$(PRODUCT_NAME) uses the camera to add credit card`
1. `import CreditCardScanner`
1. Conform to `CreditCardScannerViewControllerDelegate`
1. Present `CreditCardScannerViewController` and set its delegate

```swift
import CreditCardScanner

class ViewController: UIViewController, CreditCardScannerViewControllerDelegate {

    override func viewDidLoad() {
        super.viewDidLoad()

        let creditCardScannerViewController = CreditCardScannerViewController(delegate: self)
        present(creditCardScannerViewController, animated: true)
    }

    func creditCardScannerViewController(_ viewController: CreditCardScannerViewController, didErrorWith error: CreditCardScannerError) {
        viewController.dismiss(animated: true)
        print(error.errorDescription ?? "Unknown error")
    }

    func creditCardScannerViewController(_ viewController: CreditCardScannerViewController, didFinishWith card: CreditCard) {
        // Do something with credit card info
        print("\(card)")
    }

}
```

## Trying out the Example app

```sh
# Install xcodegen if not present
$ brew install xcodegen
# Generate project
$ xcodegen
```

## Alternatives

### Card.io

- [Card.io](https://github.com/card-io/card.io-iOS-SDK)
- This was a good solution, but it has been unmaintained for a long time and is not fully open-source

### CardScan

- [CardScan](https://github.com/getbouncer/cardscan-ios)
- Open-source and looks well made, but it costs money to use

## Credits/Inspiration

This was a two person project by [@po-miyasaka](https://github.com/po-miyasaka) and [@yhkaplan](https://github.com/yhkaplan).

This project would not have been possible without Apple's [example project](https://developer.apple.com/documentation/vision/reading_phone_numbers_in_real_time) (used with permission under an MIT license) demonstrating Vision and AVFoundation and Apple's [other example project](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/avcam_building_a_camera_app) demonstrating a fully-featured photo app (also used with permission under an MIT license)

## License

Licensed under MIT license. See [LICENSE](LICENSE) for more info.
