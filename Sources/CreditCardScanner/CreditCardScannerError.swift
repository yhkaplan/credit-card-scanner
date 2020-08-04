//
//  CreditCardScannerError.swift
//
//
//  Created by josh on 2020/07/26.
//

import Foundation

public struct CreditCardScannerError: LocalizedError {
    public enum Kind { case cameraSetup, photoProcessing, authorizationDenied, capture }
    public var kind: Kind
    public var underlyingError: Error?
    public var errorDescription: String? { (underlyingError as? LocalizedError)?.errorDescription }
}
