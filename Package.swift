// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-algo-chat",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),  // Required by swift-cli
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "AlgoChat",
            targets: ["AlgoChat"]
        ),
        .executable(
            name: "algochat-demo",
            targets: ["AlgoChatDemo"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/CorvidLabs/swift-algokit.git", from: "0.0.1"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/CorvidLabs/swift-cli.git", from: "0.1.0")
    ],
    targets: [
        .target(
            name: "AlgoChat",
            dependencies: [
                .product(name: "AlgoKit", package: "swift-algokit"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .executableTarget(
            name: "AlgoChatDemo",
            dependencies: [
                "AlgoChat",
                .product(name: "CLI", package: "swift-cli")
            ]
        ),
        .testTarget(
            name: "AlgoChatTests",
            dependencies: ["AlgoChat"]
        )
    ]
)
