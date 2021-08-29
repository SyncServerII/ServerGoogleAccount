// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ServerGoogleAccount",
    products: [
        .library(
            name: "ServerGoogleAccount",
            targets: ["ServerGoogleAccount"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SyncServerII/ServerAccount.git", from: "0.0.2"),
    ],
    targets: [
        .target(
            name: "ServerGoogleAccount",
            dependencies: ["ServerAccount"]),
        .testTarget(
            name: "ServerGoogleAccountTests",
            dependencies: ["ServerGoogleAccount"],
            resources: [
                .copy("Cat.jpg"),
                .copy("example.url"),
            ]),
    ]
)
