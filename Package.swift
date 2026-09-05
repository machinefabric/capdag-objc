// swift-tools-version: 6.0
// version: 1.482.84
import PackageDescription

let package = Package(
    name: "capdag-objc",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "CapDAG",
            targets: ["CapDAG"]),
        .library(
            name: "Bifaci",
            targets: ["Bifaci"]),
        // Every capdag mirror ships the CLI: `capdag new` is how a cartridge
        // project comes into existence, and each mirror must create the same one.
        .executable(
            name: "capdag",
            targets: ["capdag-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/machinefabric/tagged-urn-objc.git", from: "1.34.211"),
        .package(url: "https://github.com/jowharshamshiri/ops-objc.git", from: "1.19.17"),
        .package(url: "https://github.com/unrelentingtech/SwiftCBOR.git", from: "0.4.7"),
        .package(url: "https://github.com/Bouke/Glob.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "CapDAG",
            dependencies: [
                .product(name: "TaggedUrn", package: "tagged-urn-objc"),
            ],
            path: "Sources/CapDAG",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "Bifaci",
            dependencies: [
                "CapDAG",
                .product(name: "Ops", package: "ops-objc"),
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
                .product(name: "Glob", package: "Glob"),
            ],
            path: "Sources/Bifaci"
        ),
        .executableTarget(
            name: "capdag-cli",
            dependencies: ["Bifaci", "CapDAG"],
            path: "Sources/capdag-cli"
        ),
        .testTarget(
            name: "CapDAGTests",
            dependencies: ["CapDAG"]),
        .testTarget(
            name: "BifaciTests",
            dependencies: [
                "Bifaci",
                "CapDAG",
                .product(name: "Ops", package: "ops-objc"),
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
            ]),
    ]
)
