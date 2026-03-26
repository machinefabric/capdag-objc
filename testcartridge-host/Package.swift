// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "testcartridge-host",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: ".."),  // capdag-objc (provides Bifaci)
    ],
    targets: [
        .executableTarget(
            name: "testcartridge-host",
            dependencies: [
                .product(name: "Bifaci", package: "capdag-objc"),
            ],
            path: "Sources/TestcartridgeHost"
        ),
    ]
)
