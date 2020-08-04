//
//  ExampleResultViewController.swift
//  Example
//
//  Created by miyasaka on 2020/07/30.
//

import CreditCardScanner
import UIKit

class ExampleResultViewController: UIViewController {
    @IBOutlet var resultLabel: UILabel!

    @IBAction func startButton(_ sender: UIButton) {
//        You can change only neccessary parameters.
//        let vc = CreditCardScannerViewController(delegate: self)
//        vc.titleLabelText = "カードを追加"
//        vc.subtitleLabelText = "枠線にカードを合わせてください"
//        vc.cancelButtonTitleText = "キャンセル"
//        vc.cancelButtonTitleTextColor = .orange
//        vc.labelTextColor = .black
//        vc.cameraViewCreditCardFrameStrokeColor = .gray
//        vc.cameraViewMaskLayerColor = .white
//        vc.cameraViewMaskAlpha = 0.7
//        vc.textBackgroundColor = .white

        let vc = CreditCardScannerViewController(delegate: self)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true, completion: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension ExampleResultViewController: CreditCardScannerViewControllerDelegate {
    func creditCardScannerViewControllerDidCancel(_ viewController: CreditCardScannerViewController) {
        viewController.dismiss(animated: true, completion: nil)
        print("cancel")
    }

    func creditCardScannerViewController(_ viewController: CreditCardScannerViewController, didErrorWith error: CreditCardScannerError) {
        print(error.errorDescription ?? "")
        resultLabel.text = error.errorDescription
        viewController.dismiss(animated: true, completion: nil)
    }

    func creditCardScannerViewController(_ viewController: CreditCardScannerViewController, didFinishWith card: CreditCard) {
        viewController.dismiss(animated: true, completion: nil)

        var dateComponents = card.expireDate
        dateComponents?.calendar = Calendar.current
        let dateFormater = DateFormatter()
        dateFormater.dateStyle = .short
        let date = dateComponents?.date.flatMap(dateFormater.string)

        let text = [card.number, date, card.name]
            .compactMap { $0 }
            .joined(separator: "\n")
        resultLabel.text = text
        print("\(card)")
    }
}
