// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoctwebUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NoctwebUI", targets: ["NoctwebUI"])
    ],
    targets: [
        .target(name: "NoctwebUI"),
        .testTarget(name: "NoctwebUITests", dependencies: ["NoctwebUI"])
    ]
)
