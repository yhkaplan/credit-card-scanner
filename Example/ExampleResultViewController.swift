//
//  ExampleResultViewController.swift
//  Example
//
//  Created by miyasaka on 2020/07/30.
//

import UIKit
import CreditCardScanner

class ExampleResultViewController: UIViewController{

    @IBOutlet weak var resultLabel: UILabel!

    @IBAction func startButton(_ sender: UIButton) {
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
        print(error.errorDescription)
        resultLabel.text = error.errorDescription
        viewController.dismiss(animated: true, completion: nil)
    }

    func creditCardScannerViewController(_ viewController: CreditCardScannerViewController, didFinishWith card: CreditCard) {
        viewController.dismiss(animated: true, completion: nil)
        resultLabel.text = ["\(card.number)","\(card.date)", "\(card.name)"].joined(separator: "\n")
        print("\(card)")
    }
}
