// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MoneiPaySDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "MoneiPaySDK",
            targets: ["MoneiPaySDK"]
        )
    ],
    targets: [
        .target(
            name: "MoneiPaySDK",
            path: "Sources/MoneiPaySDK"
        ),
        .testTarget(
            name: "MoneiPaySDKTests",
            dependencies: ["MoneiPaySDK"],
            path: "Tests/MoneiPaySDKTests"
        )
    ]
)
