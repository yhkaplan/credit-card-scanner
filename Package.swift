// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CreditCardScanner",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "CreditCardScanner",
            targets: ["CreditCardScanner"]),
    ],
    dependencies: [
        .package(url: "https://github.com/yhkaplan/Reg.git", from: "0.2.5"),
    ],
    targets: [
        .target(
            name: "CreditCardScanner",
            dependencies: ["Reg"]),
        .testTarget(
            name: "CreditCardScannerTests",
            dependencies: ["CreditCardScanner"]),
    ]
)
