// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "XCTunnelManager",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "XCTunnelManager",
            targets: ["XCTunnelManager"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/min554357332/XCEvents.git", .upToNextMajor(from: "0.0.1"))
    ],
    targets: [
        .target(
            name: "XCTunnelManager",
            dependencies: [
                .product(name: "XCEvents", package: "XCEvents", condition: .when(platforms: [.iOS]))
            ],
        ),
        .testTarget(
            name: "XCTunnelManagerTests",
            dependencies: ["XCTunnelManager"]
        ),
    ]
)
