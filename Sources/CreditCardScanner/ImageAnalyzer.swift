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

class ImageAnalyzer {

    typealias PredictedCount = Int
    private var predictedCardNumberDictionary: [String: PredictedCount] = [:]
    private var selectedCardNumber: String?
    private var predictedNameDictionary: [String: PredictedCount] = [:]
    private var selectedName: String?
    private var predictedExpireDateDictionary: [DateComponents: PredictedCount] = [:]
    private var selectedExpireDate: DateComponents?

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
            delegate?.didFinishAnalyzation(with: .failure(CreditCardScannerError(kind: .photoProcessing,
                                                                                      underlyingError: error)))
        }
    }

    lazy var requestHandler: ((VNRequest, Error?) -> ())? = { [weak self] request, _ in
        guard let strongSelf = self else { return }

        let creditCardNumber: Regex = #"(\d{4}\h+\d{4}\h+\d{4}\h+\d{4})"#
        let twoDigits = #"(\d{2})"#
        let date = Regex(twoDigits + #"\/"# + twoDigits)
        // mrs, mr
        let wordsToSkip = ["mastercard", "jcb", "visa", "express", "bank",/* "card", */"platinum", "reward"] // TODO: add `card` back in
        // These may be contained in the date strings, so ignore them only for names
        let invalidNames = ["expiration", "valid", "since", "from", "until", "month", "year"]
        let name: Regex = #"([A-z]{2,}\h([A-z.]+\h)?[A-z]{2,})"#

        guard let results = request.results as? [VNRecognizedTextObservation] else { return }

        var creditCard = CreditCard(number: nil, name: nil, date: nil)

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

        // Name
        if let name = creditCard.name {
            let count = strongSelf.predictedNameDictionary[name] ?? 0
            strongSelf.predictedNameDictionary[name] = count + 1
            if count > 2 {
                strongSelf.selectedName = name
            }
        }
        // ExpireDate
        if let date = creditCard.date {
            let count = strongSelf.predictedExpireDateDictionary[date] ?? 0
            strongSelf.predictedExpireDateDictionary[date] = count + 1
            if count > 2 {
                strongSelf.selectedExpireDate = date
            }
        }

        // Number
        if let number = creditCard.number {
            let count = strongSelf.predictedCardNumberDictionary[number] ?? 0
            strongSelf.predictedCardNumberDictionary[number] = count + 1
            if count > 2 {
                strongSelf.selectedCardNumber = number
            }
        }

        guard strongSelf.selectedCardNumber != nil else {
            return
        }
        strongSelf.completeAnalyzation()
    }

    func completeAnalyzation() {
        let selected = CreditCard(number: selectedCardNumber, name: selectedName, date: selectedExpireDate)
        delegate?.didFinishAnalyzation(with: .success(selected))
    }

}
