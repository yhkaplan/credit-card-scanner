//
//  File.swift
//
//
//  Created by miyasaka on 2020/07/31.
//

import AVFoundation
import Foundation

enum ImageRatio {
    case cif352x288
    case vga640x480
    case iFrame960x540
    case iFrame1280x720
    case hd1280x720
    case hd1920x1080
    case hd4K3840x2160

    var preset: AVCaptureSession.Preset {
        switch self {
        case .cif352x288:
            return .cif352x288
        case .vga640x480:
            return .vga640x480
        case .iFrame960x540:
            return .iFrame960x540
        case .iFrame1280x720:
            return .iFrame1280x720
        case .hd1280x720:
            return .hd1280x720
        case .hd1920x1080:
            return .hd1920x1080
        case .hd4K3840x2160:
            return .hd4K3840x2160
        }
    }

    var imageHeight: CGFloat {
        switch self {
        case .cif352x288:
            return 352.0
        case .vga640x480:
            return 640.0
        case .iFrame960x540:
            return 960.0
        case .iFrame1280x720:
            return 1280.0
        case .hd1280x720:
            return 1280.0
        case .hd1920x1080:
            return 1920.0
        case .hd4K3840x2160:
            return 3840.0
        }
    }

    var imageWidth: CGFloat {
        switch self {
        case .cif352x288:
            return 288.0
        case .vga640x480:
            return 480.0
        case .iFrame960x540:
            return 540.0
        case .hd1280x720:
            return 720.0
        case .iFrame1280x720:
            return 720.0
        case .hd1920x1080:
            return 1080.0
        case .hd4K3840x2160:
            return 2160.0
        }
    }
}
