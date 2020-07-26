//
//  CameraView.swift
//  CreditCardScannerPackageDescription
//
//  Created by josh on 2020/07/23.
//
#if canImport(UIKit)
#if canImport(AVFoundation)

import UIKit
import AVFoundation

final class CameraView: UIView {
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Expected `AVCaptureVideoPreviewLayer` type for layer. Check PreviewView.layerClass implementation.")
        }
        
        return layer
    }

    var session: AVCaptureSession? {
        get { videoPreviewLayer.session }
        set { videoPreviewLayer.session = newValue }
    }

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }
}
#endif
#endif
