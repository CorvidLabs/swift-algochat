// swift-tools-version: 6.0

import PackageDescription

let targets: [Target] = [
    .target(
        name: "AlgoChat",
        dependencies: [
            .product(name: "AlgoKit", package: "swift-algokit"),
            .product(name: "Algorand", package: "swift-algorand"),
            .product(name: "Crypto", package: "swift-crypto")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),
    .executableTarget(
        name: "AlgoChatCLI",
        dependencies: [
            "AlgoChat",
            .product(name: "CLI", package: "swift-cli")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),
    .testTarget(
        name: "AlgoChatTests",
        dependencies: ["AlgoChat"],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    )
]

let products: [Product] = [
    .library(
        name: "AlgoChat",
        targets: ["AlgoChat"]
    ),
    .executable(
        name: "algochat",
        targets: ["AlgoChatCLI"]
    )
]

let package = Package(
    name: "swift-algochat",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
        .visionOS(.v1)
    ],
    products: products,
    dependencies: [
        .package(url: "https://github.com/CorvidLabs/swift-algokit.git", from: "0.0.2"),
        // swift-algorand 0.4.0 made AlgorandConfiguration factories throwing, which does not
        // compile against swift-algokit 0.0.2. Hold the transitive pin below 0.4.0 until AlgoKit updates.
        .package(url: "https://github.com/CorvidLabs/swift-algorand.git", "0.2.0" ..< "0.4.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/CorvidLabs/swift-cli.git", from: "0.1.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0")
    ],
    targets: targets
)
