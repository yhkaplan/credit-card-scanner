//
//  ImageAnalyzer.swift
//  
//
//  Created by miyasaka on 2020/07/30.
//

import Foundation
import Vision
import Reg

protocol ImageAnalyzerProtocol: AnyObject {
    func didFinishAnalyzation(with result: Result<CreditCard, CreditCardScannerError>)
}

final class ImageAnalyzer {
    enum Candidate: Hashable {
        case number(String), name(String)
        case expireDate(DateComponents)
    }

    typealias PredictedCount = Int

    private var selectedCard = CreditCard()
    private var predictedCardInfo: [Candidate: PredictedCount] = [:]

    private weak var delegate: ImageAnalyzerProtocol?
    init(delegate: ImageAnalyzerProtocol) {
        self.delegate = delegate
    }

    // MARK: - Vision-related
    public lazy var request = VNRecognizeTextRequest(completionHandler: requestHandler)
    func analyze(image: CGImage) {
        let requestHandler = VNImageRequestHandler(
            cgImage: image,
            orientation: .up,
            options: [:]
        )

        do {
            try requestHandler.perform([request])
        } catch {
            let e = CreditCardScannerError(kind: .photoProcessing, underlyingError: error)
            delegate?.didFinishAnalyzation(with: .failure(e))
        }
    }

    lazy var requestHandler: ((VNRequest, Error?) -> ())? = { [weak self] request, _ in
        guard let strongSelf = self else { return }

        let creditCardNumber: Regex = #"(\d{4}\h+\d{4}\h+\d{4}\h+\d{4})"#
        let month: Regex = #"(\d{2})\/\d{2}"#
        let year: Regex = #"\d{2}\/(\d{2})"#
        let wordsToSkip = ["mastercard", "jcb", "visa", "express", "bank", "card", "platinum", "reward"]
        // These may be contained in the date strings, so ignore them only for names
        let invalidNames = ["expiration", "valid", "since", "from", "until", "month", "year"]
        let name: Regex = #"([A-z]{2,}\h([A-z.]+\h)?[A-z]{2,})"#

        guard let results = request.results as? [VNRecognizedTextObservation] else { return }

        var creditCard = CreditCard(number: nil, name: nil, expireDate: nil)

        let maxCandidates = 1
        for result in results {
            guard
                let candidate = result.topCandidates(maxCandidates).first,
                candidate.confidence > 0.1
            else { continue }

            let string = candidate.string
            let containsWordToSkip = wordsToSkip.contains { string.lowercased().contains($0) }
            if containsWordToSkip { continue }

            if let cardNumber = creditCardNumber.firstMatch(in: string) {
                creditCard.number = cardNumber

            // the first capture is the entire regex match, so using the last
            } else if let month = month.captures(in: string).last.flatMap(Int.init),
                let year = year.captures(in: string).last.flatMap(Int.init) {
                creditCard.expireDate = DateComponents(year: year, month: month)

            } else if let name = name.firstMatch(in: string) {
                let containsInvalidName = invalidNames.contains { name.lowercased().contains($0)}
                if containsInvalidName { continue }
                creditCard.name = name

            } else {
                continue
            }
        }

        // Name
        if let name = creditCard.name {
            let count = strongSelf.predictedCardInfo[.name(name), default: 0]
            strongSelf.predictedCardInfo[.name(name)] = count + 1
            if count > 2 {
                strongSelf.selectedCard.name = name
            }
        }
        // ExpireDate
        if let date = creditCard.expireDate {
            let count = strongSelf.predictedCardInfo[.expireDate(date), default: 0]
            strongSelf.predictedCardInfo[.expireDate(date)] = count + 1
            if count > 2 {
                strongSelf.selectedCard.expireDate = date
            }
        }

        // Number
        if let number = creditCard.number {
            let count = strongSelf.predictedCardInfo[.number(number), default: 0]
            strongSelf.predictedCardInfo[.number(number)] = count + 1
            if count > 2 {
                strongSelf.selectedCard.number = number
            }
        }

        if strongSelf.selectedCard.number != nil {
            strongSelf.delegate?.didFinishAnalyzation(with: .success(strongSelf.selectedCard))
        }
    }

}
