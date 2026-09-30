// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KanaSkins",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "KanaSkins", targets: ["KanaSkins"]),
    ],
    targets: [
        .target(name: "KanaSkins"),
        .testTarget(name: "KanaSkinsTests", dependencies: ["KanaSkins"]),
    ]
)
