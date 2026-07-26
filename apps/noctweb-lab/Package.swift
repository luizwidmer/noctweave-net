// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoctwebLab",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NoctwebLabCore",
            targets: ["NoctwebLabCore"]
        ),
        .executable(
            name: "NoctwebLab",
            targets: ["NoctwebLab"]
        )
    ],
    targets: [
        .target(
            name: "NoctwebLabCore",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "NoctwebLab",
            dependencies: ["NoctwebLabCore"],
            linkerSettings: [
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "NoctwebLabCoreTests",
            dependencies: ["NoctwebLabCore"]
        ),
        .testTarget(
            name: "NoctwebLabAppTests",
            dependencies: ["NoctwebLab"]
        )
    ]
)
