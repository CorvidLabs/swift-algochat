// swift-tools-version: 6.0

import PackageDescription

var targets: [Target] = [
    .target(
        name: "AlgoChat",
        dependencies: [
            .product(name: "AlgoKit", package: "swift-algokit"),
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

var products: [Product] = [
    .library(
        name: "AlgoChat",
        targets: ["AlgoChat"]
    ),
    .executable(
        name: "algochat",
        targets: ["AlgoChatCLI"]
    )
]

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
targets.append(
    .executableTarget(
        name: "AlgoChatApp",
        dependencies: ["AlgoChat"]
    )
)
products.append(
    .executable(
        name: "AlgoChatApp",
        targets: ["AlgoChatApp"]
    )
)
#endif

let package = Package(
    name: "swift-algochat",
    platforms: [
        // Note: Library code is compatible with iOS 15+/macOS 12+, but
        // the demo AlgoChatApp uses SwiftUI APIs requiring higher versions
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: products,
    dependencies: [
        .package(url: "https://github.com/CorvidLabs/swift-algokit.git", from: "0.0.2"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/CorvidLabs/swift-cli.git", from: "0.1.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.0")
    ],
    targets: targets
)
