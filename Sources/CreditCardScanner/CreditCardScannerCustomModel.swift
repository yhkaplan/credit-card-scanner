//
//  File.swift
//  
//
//  Created by miyasaka on 2020/08/03.
//

import UIKit

public struct CreditCardScannerCustomModel {
    let title: String
    let subText: String
    let cancelButtonText: String
    let cancelButtonTextColor: UIColor
    let textColor: UIColor
    let strokeColor: UIColor
    let imageMaskColor: UIColor
    let imageMaskAlpha: CGFloat
    let textBackgroundColor: UIColor

    public init(title: String = "Add card",
                subText: String = "Line up card within the lines",
                cancelButtonText: String = "Cancel",
                cancelButtonTextColor: UIColor = .gray,
                textColor: UIColor = .white,
                strokeColor: UIColor = .white,
                imageMaskColor: UIColor = .black,
                imageMaskAlpha: CGFloat = 0.7,
                textBackgroundColor: UIColor = .black) {

        self.title = title
        self.subText = subText
        self.cancelButtonText = cancelButtonText
        self.cancelButtonTextColor = cancelButtonTextColor
        self.textColor = textColor
        self.strokeColor = strokeColor
        self.imageMaskColor = imageMaskColor
        self.imageMaskAlpha = imageMaskAlpha
        self.textBackgroundColor = textBackgroundColor
    }
}
