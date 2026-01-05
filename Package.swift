// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EdgenIOSClient",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15), .tvOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EdgenIOSClient",
            targets: ["EdgenIOSClient"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "EdgenIOSClient",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "EdgenIOSClientTests",
            dependencies: ["EdgenIOSClient"]
        ),
        .executableTarget(
            name: "EdgenAIClientSample",
            dependencies: ["EdgenIOSClient"],
            path: "Examples/EdgenAIClientSample"
        ),
    ]
)
