// swift-tools-version: 6.0
// version: 1.503.16
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
        .library(
            name: "LLM",
            targets: ["LLM"]),
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
        // Talking to a language model. Prompt preparation lives here because
        // it is decided from the dim profile `cap:download-model` returns, and
        // that profile is capdag's own — so the two cannot version apart.
        //
        // This was `capdag-cartridge-sdk-objc`, a separate package. Its cap
        // collection was never about language models and did not come here:
        // `CSCartridgeCaps` sits beside `CSCap` in the CapDAG target.
        .target(
            name: "LLM",
            dependencies: ["CapDAG"],
            path: "Sources/LLM"
        ),
        .executableTarget(
            name: "capdag-cli",
            dependencies: ["Bifaci", "CapDAG"],
            path: "Sources/capdag-cli"
        ),
        .testTarget(
            name: "CapDAGTests",
            dependencies: ["CapDAG"]),
        // Swift tests for the ObjC CapDAG target, in their own target because
        // SwiftPM will not mix languages in one: CapDAGTests is `.m` files.
        .testTarget(
            name: "CapDAGSwiftTests",
            dependencies: ["CapDAG"]),
        .testTarget(
            name: "LLMTests",
            dependencies: ["LLM"]),
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
