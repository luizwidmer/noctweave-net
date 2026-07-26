// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NoctwebBrowser",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "NoctwebBrowserCore",
            targets: ["NoctwebBrowserCore"]
        ),
        .executable(
            name: "NoctwebBrowser",
            targets: ["NoctwebBrowser"]
        ),
    ],
    targets: [
        .target(
            name: "NoctwebBrowserCore"
        ),
        .executableTarget(
            name: "NoctwebBrowser",
            dependencies: ["NoctwebBrowserCore"],
            linkerSettings: [
                .linkedFramework("WebKit"),
            ]
        ),
        .testTarget(
            name: "NoctwebBrowserCoreTests",
            dependencies: ["NoctwebBrowserCore"]
        ),
        .testTarget(
            name: "NoctwebBrowserAppTests",
            dependencies: [
                "NoctwebBrowser",
                "NoctwebBrowserCore",
            ]
        ),
    ]
)
