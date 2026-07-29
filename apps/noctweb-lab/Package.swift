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
        branch: "main"
    )
    noctweavePackageIdentity = "Noctweave"
}

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
    dependencies: [
        noctweaveDependency,
        .package(path: "../noctweb-ui"),
    ],
    targets: [
        .target(
            name: "NoctwebLabCore",
            dependencies: [
                .product(
                    name: "NoctweaveCore",
                    package: noctweavePackageIdentity
                )
            ],
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "NoctwebLab",
            dependencies: ["NoctwebLabCore", .product(name: "NoctwebUI", package: "noctweb-ui")],
            linkerSettings: [
                .linkedFramework("Network"),
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
