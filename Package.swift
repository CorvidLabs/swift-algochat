// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-algochat",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "AlgoChat",
            targets: ["AlgoChat"]
        ),
        .executable(
            name: "algochat",
            targets: ["AlgoChatCLI"]
        ),
        .executable(
            name: "AlgoChatApp",
            targets: ["AlgoChatApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/CorvidLabs/swift-algokit.git", from: "0.0.2"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/CorvidLabs/swift-cli.git", from: "0.1.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0")
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
            name: "AlgoChatCLI",
            dependencies: [
                "AlgoChat",
                .product(name: "CLI", package: "swift-cli")
            ]
        ),
        .testTarget(
            name: "AlgoChatTests",
            dependencies: ["AlgoChat"]
        ),
        .executableTarget(
            name: "AlgoChatApp",
            dependencies: ["AlgoChat"]
        )
    ]
)
