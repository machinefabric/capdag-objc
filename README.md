# CapDAG for Swift and Objective-C

This public Swift package is CapDAG's Apple-platform mirror. The `CapDAG`
product exposes Objective-C-compatible URN, definition, dispatch, registry, and
planning APIs. The `Bifaci` product supplies Swift protocol, stream, cartridge,
host, and relay runtime components. The package also builds the `capdag` CLI.

Rust is the behavioral reference. Applicable shared numbered tests have the
same meaning and assertions in the Apple mirror.

## Add the package

```swift
dependencies: [
    .package(
        url: "https://github.com/machinefabric/capdag-objc.git",
        from: "1.426.15"
    )
]
```

The package supports macOS 13 or newer and iOS 16 or newer. Import `CapDAG` for
the core APIs and `Bifaci` for runtime components.

## Parse and build Cap URNs

```swift
import CapDAG

let parsed = try CSCapUrn.fromString(
    "cap:disbind;in=\"media:ext=pdf\";out=\"media:enc=utf-8;page\""
)
let built = try CSCapUrnBuilder()
    .inSpec("media:ext=pdf")
    .outSpec("media:enc=utf-8;page")
    .marker("disbind")
    .build()

precondition(parsed.toString() == built.toString())
```

The Objective-C surface provides the corresponding `fromString:error:`,
builder, and predicate APIs. CapDAG objects support the Foundation coding and
copying behavior declared by their public headers, including secure coding
where the type declares it.

Treat URNs as opaque parsed values. Use CapDAG predicates for equivalence,
conformance, dispatch, and ranking rather than raw string comparison.

## Find the relevant API

- `Sources/CapDAG/` and its public headers define the core Objective-C bridge.
- `Sources/Bifaci/` defines frames, streams, flow control, runtimes, hosts, and
  relay components in Swift.
- `Sources/capdag-cli/` provides the command-line entry.
- DocC and source comments beside public declarations are the language-specific
  API reference.

The normative shared rules live in the
[CapDAG specification](https://github.com/machinefabric/capdag/blob/main/docs/01-overview.md).

## Scaffold a Swift cartridge

```bash
capdag new sentiment-tagger --swift
cd sentiment-tagger
swift build -c release
capdag dev-install .
echo "I love this" | capdag sentiment-tagger
```

See [Build and Run a Cartridge](https://github.com/machinefabric/capdag/blob/main/docs/18.2-getting-started-cartridge-development.md)
for the complete development loop.

## Verify changes

```bash
swift test
```

Shared behavior changes require the applicable reference test with the same
substantive number and assertions.

## License

MIT
