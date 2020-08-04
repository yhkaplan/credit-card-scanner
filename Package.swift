// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "CreditCardScanner",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "CreditCardScanner",
            targets: ["CreditCardScanner"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/yhkaplan/Reg.git", from: "0.3.0"),
        .package(url: "https://github.com/yhkaplan/Sukar.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "CreditCardScanner",
            dependencies: ["Reg", "Sukar"]
        ),
        .testTarget(
            name: "CreditCardScannerTests",
            dependencies: ["CreditCardScanner"]
        ),
    ]
)
