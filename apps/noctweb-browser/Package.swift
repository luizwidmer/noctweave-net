// swift-tools-version: 6.0
import Foundation
import PackageDescription

let noctweaveDependency: Package.Dependency
let noctweavePackageIdentity: String
if let localPath = ProcessInfo.processInfo.environment[
    "NOCTWEAVE_PACKAGE_PATH"
], !localPath.isEmpty {
    noctweaveDependency = .package(path: localPath)
    noctweavePackageIdentity = URL(
        fileURLWithPath: localPath
    ).lastPathComponent
} else {
    noctweaveDependency = .package(
        url: "https://github.com/luizwidmer/Noctweave.git",
        revision: "8912862d49f10c8bd307078ba0f05dc021fea1f5"
    )
    noctweavePackageIdentity = "Noctweave"
}

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
    dependencies: [
        noctweaveDependency,
        .package(path: "../noctweb-lab"),
        .package(path: "../noctweb-ui"),
    ],
    targets: [
        .target(
            name: "NoctwebBrowserCore",
            dependencies: [
                .product(
                    name: "NoctweaveCore",
                    package: noctweavePackageIdentity
                )
            ]
        ),
        .executableTarget(
            name: "NoctwebBrowser",
            dependencies: [
                "NoctwebBrowserCore",
                .product(name: "NoctwebLabCore", package: "noctweb-lab"),
                .product(name: "NoctwebUI", package: "noctweb-ui"),
                .product(
                    name: "NoctweaveCore",
                    package: noctweavePackageIdentity
                ),
            ],
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
