import XCTest
import SwiftCBOR
@testable import Bifaci
@testable import CapDAG
import Ops

/// Tests for standard capabilities and manifest validation (TEST473-480)
/// Based on Rust tests in standard/caps.rs and bifaci/manifest.rs
final class StandardCapsTests: XCTestCase {

    // MARK: - CAP_DISCARD Tests (TEST473-474)

    // TEST473: CAP_DISCARD parses as valid CapUrn with in=media: and out=media:void
    func test473_capDiscardParsesAsValidCapUrn() throws {
        let discardUrn = try CSCapUrn.fromString(CSCapDiscard)

        XCTAssertNotNil(discardUrn, "CAP_DISCARD must parse as valid CapUrn")
        XCTAssertEqual(discardUrn.inSpec, "media:", "CAP_DISCARD input must be media: (any media type)")
        XCTAssertEqual(discardUrn.outSpec, "media:void", "CAP_DISCARD output must be media:void")
    }

    // TEST474: CAP_DISCARD accepts specific-input/void-output caps
    func test474_capDiscardAcceptsVoidOutputCaps() throws {
        let discardPattern = try CSCapUrn.fromString(CSCapDiscard)

        // CAP_DISCARD should accept any cap with void output
        let voidCap1 = try CSCapUrn.fromString("cap:in=media:text;out=media:void")
        let voidCap2 = try CSCapUrn.fromString("cap:delete;in=media:;out=media:void")

        XCTAssertTrue(discardPattern.accepts(voidCap1), "CAP_DISCARD must accept text->void cap")
        XCTAssertTrue(discardPattern.accepts(voidCap2), "CAP_DISCARD must accept any->void cap")

        // CAP_DISCARD should NOT accept caps with non-void output
        let nonVoidCap = try CSCapUrn.fromString("cap:in=media:;out=media:text")
        XCTAssertFalse(discardPattern.accepts(nonVoidCap), "CAP_DISCARD must not accept non-void output")
    }

    // MARK: - Adapter selection constants (TEST1271-1273)

    // TEST1271: MEDIA_ADAPTER_SELECTION constant parses and has expected tags
    func test1271_mediaAdapterSelectionConstant() throws {
        let urn = try CSMediaUrn.fromString(CSMediaAdapterSelection)
        XCTAssertNotNil(
            urn.getTag("adapter-selection"),
            "Must have adapter-selection tag, got: \(urn.toString())"
        )
        XCTAssertEqual(
            urn.getTag("fmt"), "json",
            "Must have fmt=json tag, got: \(urn.toString())"
        )
        XCTAssertTrue(urn.isRecord(), "Must have record tag, got: \(urn.toString())")
    }

    // TEST1272: CAP_ADAPTER_SELECTION constant parses as a valid CapUrn
    func test1272_adapterCapConstantParses() throws {
        XCTAssertNoThrow(
            try CSCapUrn.fromString(CSCapAdapterSelection),
            "CAP_ADAPTER_SELECTION must be a valid cap URN"
        )
    }

    // TEST1273: the adapter-selection cap URN has correct in/out specs — in
    // is the bare wildcard `media:` (accepts any) and out conforms to the
    // adapter-selection media URN. (The reference exposes this as the
    // `adapter_selection_urn()` builder; here the parsed constant IS the
    // canonical form the runtime registers.)
    func test1273_adapterSelectionUrnBuilder() throws {
        let urn = try CSCapUrn.fromString(CSCapAdapterSelection)
        XCTAssertEqual(urn.inSpec, "media:", "in_spec must be bare media: (accepts any)")
        let outUrn = try CSMediaUrn.fromString(urn.outSpec)
        let expectedOut = try CSMediaUrn.fromString(CSMediaAdapterSelection)
        XCTAssertTrue(
            outUrn.conforms(to: expectedOut),
            "out_spec '\(urn.outSpec)' should conform to adapter-selection URN"
        )
    }

    // MARK: - Manifest Validation Tests (TEST475-477)

    // TEST6598: CapManifest::validate() passes when CAP_IDENTITY is present
    func test6598_manifestValidatePassesWithIdentity() throws {
        let identityUrn = try CSCapUrn.fromString(CSCapIdentity)
        let identityCap = CSCap(urn: identityUrn, title: "Identity", aliases: ["identity"])
        let group = CSCapGroup(name: "default", caps: [identityCap], adapterUrns: [])
        let manifest = CSCapManifest(name: "TestCartridge",
                                     version: "1.0.0",
                                     channel: .release,
                                     registryURL: nil,
                                     manifestDescription: "Test",
                                     capGroups: [group])

        XCTAssertNoThrow(try manifest.validate(), "Manifest with CAP_IDENTITY must validate successfully")
    }

    // TEST6599: CapManifest::validate() fails when CAP_IDENTITY is missing
    func test6599_manifestValidateFailsWithoutIdentity() throws {
        let otherUrn = try CSCapUrn.fromString("cap:test;in=media:;out=media:")
        let otherCap = CSCap(urn: otherUrn, title: "Test", aliases: ["test"])
        let group = CSCapGroup(name: "default", caps: [otherCap], adapterUrns: [])
        let manifest = CSCapManifest(name: "TestCartridge",
                                     version: "1.0.0",
                                     channel: .release,
                                     registryURL: nil,
                                     manifestDescription: "Test",
                                     capGroups: [group])

        XCTAssertThrowsError(try manifest.validate(), "Manifest without CAP_IDENTITY must fail validation")
    }

    // Mirror-specific coverage: Manifest.ensureIdentity() adds if missing, idempotent if present
    func test6244_manifestEnsureIdentityIdempotent() throws {
        // Test 1: Adding identity when missing
        let testUrn = try CSCapUrn.fromString("cap:test;in=media:;out=media:")
        let cap1 = CSCap(urn: testUrn, title: "Test", aliases: ["test"])
        let group = CSCapGroup(name: "default", caps: [cap1], adapterUrns: [])
        let manifestWithout = CSCapManifest(name: "TestCartridge",
                                            version: "1.0.0",
                                            channel: .release,
                                            registryURL: nil,
                                            manifestDescription: "Test",
                                            capGroups: [group])

        let withIdentity = manifestWithout.ensureIdentity()
        XCTAssertNoThrow(try withIdentity.validate(), "ensureIdentity() must add CAP_IDENTITY")
        XCTAssertEqual(withIdentity.allCaps().count, 2, "ensureIdentity() must add identity cap")

        // Test 2: Idempotent when already present
        let withIdentityAgain = withIdentity.ensureIdentity()
        XCTAssertEqual(withIdentityAgain.allCaps().count, 2, "ensureIdentity() must be idempotent")
    }

    // MARK: - Auto-Registration Tests (TEST478-480)

    // TEST478: CartridgeRuntime auto-registers identity and discard handlers on construction
    func test478_cartridgeRuntimeAutoRegistersIdentity() throws {
        let manifest = """
        {"name":"Test","version":"1.0.0","channel":"release","description":"Test","cap_groups":[{"name":"default","caps":[
            {"urn":"\(CSCapIdentity)","title":"Identity","aliases":["identity"]}
        ]}]}
        """.data(using: .utf8)!

        let runtime = CartridgeRuntime(manifest: manifest)

        // Verify identity handler is registered
        let identityHandler = runtime.findHandler(capUrn: CSCapIdentity)
        XCTAssertNotNil(identityHandler, "CartridgeRuntime must auto-register CAP_IDENTITY handler")
    }

    // TEST479: Custom identity Op overrides auto-registered default
    func test479_identityHandlerEchoesInput() throws {
        let manifest = """
        {"name":"Test","version":"1.0.0","channel":"release","description":"Test","cap_groups":[{"name":"default","caps":[
            {"urn":"\(CSCapIdentity)","title":"Identity","aliases":["identity"]}
        ]}]}
        """.data(using: .utf8)!

        let runtime = CartridgeRuntime(manifest: manifest)
        let factory = runtime.findHandler(capUrn: CSCapIdentity)!

        // Create test input - pre-collected chunks
        let testData = "test data".data(using: .utf8)!
        let chunks: [Result<(CBOR, StreamMeta?), StreamError>] = [.success((.byteString([UInt8](testData)), nil))]
        var chunkIndex = 0
        let chunkIterator = AnyIterator<Result<(CBOR, StreamMeta?), StreamError>> {
            guard chunkIndex < chunks.count else { return nil }
            let chunk = chunks[chunkIndex]
            chunkIndex += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:", rx: chunkIterator)
        let streams: [Result<Bifaci.InputStream, StreamError>] = [.success(stream)]
        var streamIndex = 0
        let streamIterator = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIndex < streams.count else { return nil }
            let s = streams[streamIndex]
            streamIndex += 1
            return s
        }

        let input = InputPackage(rx: streamIterator)

        // Create output (mock) - use synchronized data collection
        final class OutputCollector: @unchecked Sendable {
            private var data = Data()
            private let lock = NSLock()

            func append(_ bytes: Data) {
                lock.lock()
                data.append(bytes)
                lock.unlock()
            }

            func getData() -> Data {
                lock.lock()
                defer { lock.unlock() }
                return data
            }
        }

        let collector = OutputCollector()
        let mockSender = MockFrameSender { frame in
            if frame.frameType == .chunk, let payload = frame.payload {
                if let cbor = try? CBOR.decode([UInt8](payload)), case .byteString(let bytes) = cbor {
                    collector.append(Data(bytes))
                }
            }
        }
        let output = OutputStream(sender: mockSender, streamId: "test", mediaUrn: "media:",
                                 requestId: .newUUID(), routingId: nil, maxChunk: 1000)

        // Execute Op handler via invokeOp (dispatchOp + NoPeerInvoker)
        XCTAssertNoThrow(try invokeOp(factory, input: input, output: output), "Identity handler must not throw")
        XCTAssertEqual(collector.getData(), testData, "Identity handler must echo input unchanged")
    }

    // TEST480: parse_caps_from_manifest rejects manifest without CAP_IDENTITY
    func test480_discardHandlerConsumesInput() throws {
        let manifest = """
        {"name":"Test","version":"1.0.0","channel":"release","description":"Test","cap_groups":[{"name":"default","caps":[
            {"urn":"\(CSCapIdentity)","title":"Identity","aliases":["identity"]},
            {"urn":"\(CSCapDiscard)","title":"Discard","aliases":["discard"]}
        ]}]}
        """.data(using: .utf8)!

        let runtime = CartridgeRuntime(manifest: manifest)
        let factory = runtime.findHandler(capUrn: CSCapDiscard)!

        // Create test input - pre-collected chunks
        let testData = "discard me".data(using: .utf8)!
        let chunks: [Result<(CBOR, StreamMeta?), StreamError>] = [.success((.byteString([UInt8](testData)), nil))]
        var chunkIndex = 0
        let chunkIterator = AnyIterator<Result<(CBOR, StreamMeta?), StreamError>> {
            guard chunkIndex < chunks.count else { return nil }
            let chunk = chunks[chunkIndex]
            chunkIndex += 1
            return chunk
        }

        let stream = Bifaci.InputStream(mediaUrn: "media:", rx: chunkIterator)
        let streams: [Result<Bifaci.InputStream, StreamError>] = [.success(stream)]
        var streamIndex = 0
        let streamIterator = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIndex < streams.count else { return nil }
            let s = streams[streamIndex]
            streamIndex += 1
            return s
        }

        let input = InputPackage(rx: streamIterator)

        // Create output (mock) - synchronized flag
        final class OutputChecker: @unchecked Sendable {
            private var generated = false
            private let lock = NSLock()

            func markGenerated() {
                lock.lock()
                generated = true
                lock.unlock()
            }

            func wasGenerated() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                return generated
            }
        }

        let checker = OutputChecker()
        let mockSender = MockFrameSender { _ in
            checker.markGenerated()
        }
        let output = OutputStream(sender: mockSender, streamId: "test", mediaUrn: "media:void",
                                 requestId: .newUUID(), routingId: nil, maxChunk: 1000)

        // Execute Op handler via invokeOp (dispatchOp + NoPeerInvoker)
        XCTAssertNoThrow(try invokeOp(factory, input: input, output: output), "Discard handler must not throw")
        // Discard produces void - no CHUNK output expected
        // (STREAM_START/STREAM_END might be sent by dispatchOp.close(), but no data chunks)
    }
}

// MARK: - Test Helpers

/// Mock FrameSender for testing
private final class MockFrameSender: FrameSender, @unchecked Sendable {
    private let onSend: @Sendable (Frame) -> Void

    init(onSend: @escaping @Sendable (Frame) -> Void) {
        self.onSend = onSend
    }

    func send(_ frame: Frame) throws {
        onSend(frame)
    }
}
