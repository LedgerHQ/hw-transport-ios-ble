// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BleTransport",
    platforms: [
        .iOS(.v13),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "BleTransport",
            targets: ["BleTransport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/harrisonf-ledger/bluejay", branch: "multiplatform"),
    ],
    targets: [
        .target(
            name: "BleTransport",
            dependencies: [.product(name: "Bluejay", package: "bluejay")]),
        .testTarget(
            name: "BleTransportTests",
            dependencies: ["BleTransport"]),
    ]
)
