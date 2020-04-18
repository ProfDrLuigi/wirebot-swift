// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "wirebot",
    platforms: [
        .macOS(.v10_15)
    ],
    dependencies: [
        .package(name: "WiredSwift", url: "https://github.com/nark/WiredSwift", from: "1.0.3"),
        .package(name: "swift-argument-parser", url: "https://github.com/apple/swift-argument-parser", from: "0.0.4"),
        .package(name: "Yams", url: "https://github.com/jpsim/Yams.git", from: "2.0.0"),
        .package(name: "Fuse", url: "https://github.com/krisk/fuse-swift", .branch("master")),
        .package(name: "FeedKit", url: "https://github.com/nmdias/FeedKit.git", from: "9.1.2"),
        .package(name: "CLibreSSL", url: "https://github.com/vapor-community/clibressl.git", .branch("master")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "wirebot",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "WiredSwift",
                "Yams",
                "Fuse",
                "FeedKit"
            ]),
        .testTarget(
            name: "wirebotTests",
            dependencies: ["wirebot"]),
    ]
)
