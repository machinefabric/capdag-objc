import XCTest
import Foundation
import SwiftCBOR
import CapDAG
@testable import Bifaci
import Ops

// =============================================================================
// CartridgeRuntime + CapArgumentValue Tests
//
// Covers TEST248-273 from cartridge_runtime.rs and TEST274-283 from caller.rs
// in the reference Rust implementation.
//
// N/A tests (Rust-specific traits):
// TEST253: Test OpFactory can be cloned via Arc and sent across tasks (Send + Sync)
//   TEST279: cap_argument_value_clone (Swift structs are value types, always copied)
//   TEST280: cap_argument_value_debug (Rust Debug trait has no Swift equivalent)
//   TEST281: cap_argument_value_into_string (Rust Into trait - Swift uses String directly)
// =============================================================================

// MARK: - Helper Functions for Frame-Based Testing

/// Collect all CHUNK frame payloads from a frame stream
@available(macOS 10.15.4, iOS 13.4, *)
func collectFramePayloads(_ frames: AsyncStream<Frame>) async -> Data {
    var accumulated = Data()
    for await frame in frames {
        if case .chunk = frame.frameType, let payload = frame.payload {
            accumulated.append(payload)
        }
    }
    return accumulated
}

/// Create a test frame stream with a single payload chunk
@available(macOS 10.15.4, iOS 13.4, *)
func createSinglePayloadStream(requestId: MessageId = .newUUID(), streamId: String = "test", mediaUrn: String = "media:", data: Data) -> AsyncStream<Frame> {
    return AsyncStream<Frame> { continuation in
        continuation.yield(Frame.streamStart(reqId: requestId, streamId: streamId, mediaUrn: mediaUrn))
        let cborPayload = CBOR.byteString([UInt8](data)).encode()
        continuation.yield(Frame.chunk(reqId: requestId, streamId: streamId, seq: 0, payload: Data(cborPayload), chunkIndex: 0, checksum: Frame.computeChecksum(Data(cborPayload))))
        continuation.yield(Frame.streamEnd(reqId: requestId, streamId: streamId, chunkCount: 1))
        continuation.yield(Frame.end(id: requestId))
        continuation.finish()
    }
}

// MARK: - Test Op Types and invokeOp Helper

/// Helper: invoke a factory-produced Op with NoPeerInvoker.
/// Matches Rust's invoke_op() test helper.
func invokeOp(_ factory: OpFactory, input: InputPackage, output: Bifaci.OutputStream) throws {
    let op = factory()
    try dispatchOp(op: op, input: input, output: output, peer: NoPeerInvoker())
}

/// Test Op that decodes the CBOR args array, extracts the first arg's
/// `value` byteString, and stores it in a shared sink. Mirrors Rust
/// ExtractValueOp.
final class ExtractValueOp: Op, @unchecked Sendable {
    typealias Output = Void
    let received: NSLockedBytes
    init(received: NSLockedBytes) { self.received = received }
    func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        try req.output().start(isSequence: false)
        let bytes = try input.collectAllBytes()
        guard let cborVal = try CBOR.decode([UInt8](bytes)) else { return }
        if case .array(let args) = cborVal {
            for arg in args {
                if case .map(let m) = arg {
                    if case .byteString(let b) = m[.utf8String("value")] ?? .null {
                        received.set(Data(b))
                        try req.output().emitCbor(CBOR.byteString(b))
                        return
                    }
                }
            }
        }
    }
    func metadata() -> OpMetadata { OpMetadata.builder("ExtractValueOp").build() }
}

/// Thread-safe Data sink for ExtractValueOp.
final class NSLockedBytes: @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data = Data()
    func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

/// Test Op: echoes all input bytes to output (collectAllBytes → write).
/// dispatchOp closes output on success — do NOT call output.close() here.
final class EchoAllBytesOp: Op, @unchecked Sendable {
    typealias Output = Void
    init() {}
    func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        let data = try input.collectAllBytes()
        try req.output().start(isSequence: false)
        try req.output().write(data)
    }
    func metadata() -> OpMetadata { OpMetadata.builder("EchoAllBytesOp").build() }
}

/// Test Op: writes fixed Data value, drains input (ignores it).
final class WriteFixedOp: Op, @unchecked Sendable {
    typealias Output = Void
    private let data: Data
    init(data: Data) { self.data = data }
    func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        _ = try? input.collectAllBytes()
        try req.output().start(isSequence: false)
        try req.output().write(data)
    }
    func metadata() -> OpMetadata { OpMetadata.builder("WriteFixedOp").build() }
}

/// Test Op: emits fixed CBOR byteString value, drains input.
final class EmitCborBytesOp: Op, @unchecked Sendable {
    typealias Output = Void
    private let bytes: [UInt8]
    init(bytes: [UInt8]) { self.bytes = bytes }
    func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let input = try req.takeInput()
        _ = try? input.collectAllBytes()
        try req.output().start(isSequence: false)
        try req.output().emitCbor(CBOR.byteString(bytes))
    }
    func metadata() -> OpMetadata { OpMetadata.builder("EmitCborBytesOp").build() }
}

// Helper functions for testing are defined later in the file
// See: streamToInputPackage(), OutputCollector, createCollectingOutputStream()

// File-scope helpers, accessible from every test class in this file.
fileprivate func makeTestCap(urn: String, args: [CapArg]) -> CapDefinition {
    return CapDefinition(
        urn: urn,
        title: "Test",
        command: "test",
        capDescription: nil,
        args: args
    )
}

@available(macOS 10.15.4, iOS 13.4, *)
final class CartridgeRuntimeTests: XCTestCase {

    // MARK: - Test Constants

    static let testManifestJSON = """
    {"name":"TestCartridge","version":"1.0.0","channel":"release","description":"Test cartridge","cap_groups":[{"name":"default","caps":[{"urn":"cap:in=media:;out=media:","title":"Identity","command":"identity"},{"urn":"cap:in=media:;op=test;out=media:","title":"Test","command":"test"}]}]}
    """
    static let testManifestData = testManifestJSON.data(using: .utf8)!

    // MARK: - Handler Registration Tests (TEST248-252, TEST270-271)

    // TEST248: Test register_op and find_handler by exact cap URN
    func test248_registerAndFindHandler() {
        let runtime = CartridgeRuntime(manifest: Self.testManifestData)

        runtime.register_op(capUrn: "cap:in=*;op=test;out=*") {
            AnyOp(EmitCborBytesOp(bytes: Array("result".utf8)))
        }

        XCTAssertNotNil(runtime.findHandler(capUrn: "cap:in=*;op=test;out=*"),
            "handler must be found by exact URN")
    }

    // TEST249: Test register_op handler echoes bytes directly
    func test249_rawHandler() throws {
        let runtime = CartridgeRuntime(manifest: Self.testManifestData)

        runtime.register_op(capUrn: "cap:op=raw") { AnyOp(EchoAllBytesOp()) }

        let factory = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=raw"))
        let collector = OutputCollector()
        let output = createCollectingOutputStream(collector: collector)

        let inputData = "echo this".data(using: .utf8)!
        let inputStream = createSinglePayloadStream(data: inputData)
        let inputPackage = streamToInputPackage(inputStream)

        try invokeOp(factory, input: inputPackage, output: output)
        XCTAssertEqual(String(data: collector.getData(), encoding: .utf8), "echo this", "raw handler must echo payload")
    }

    // TEST250: Test Op handler collects input and processes it
    // Handlers manually deserialize JSON from input bytes if needed - no automatic deserialization

    // TEST251: Test Op handler propagates errors through RuntimeError::Handler

    // TEST252: Test find_handler returns None for unregistered cap URNs
    func test252_findHandlerUnknownCap() {
        let runtime = CartridgeRuntime(manifest: Self.testManifestData)
        XCTAssertNil(runtime.findHandler(capUrn: "cap:op=nonexistent"),
            "unregistered cap must return nil")
    }

    // TEST270: Test registering multiple Op handlers for different caps and finding each independently
    func test270_multipleHandlers() throws {
        let runtime = CartridgeRuntime(manifest: Self.testManifestData)

        runtime.register_op(capUrn: "cap:op=alpha") { AnyOp(WriteFixedOp(data: Data("a".utf8))) }
        runtime.register_op(capUrn: "cap:op=beta")  { AnyOp(WriteFixedOp(data: Data("b".utf8))) }
        runtime.register_op(capUrn: "cap:op=gamma") { AnyOp(WriteFixedOp(data: Data("g".utf8))) }

        let emptyStream = createSinglePayloadStream(mediaUrn: "media:void", data: Data())

        let fAlpha = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=alpha"))
        let collectorA = OutputCollector()
        let outputA = createCollectingOutputStream(collector: collectorA)
        try invokeOp(fAlpha, input: streamToInputPackage(emptyStream), output: outputA)
        XCTAssertEqual(collectorA.getData(), "a".data(using: .utf8)!)

        let fBeta = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=beta"))
        let collectorB = OutputCollector()
        let outputB = createCollectingOutputStream(collector: collectorB)
        let emptyStream2 = createSinglePayloadStream(mediaUrn: "media:void", data: Data())
        try invokeOp(fBeta, input: streamToInputPackage(emptyStream2), output: outputB)
        XCTAssertEqual(collectorB.getData(), "b".data(using: .utf8)!)

        let fGamma = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=gamma"))
        let collectorG = OutputCollector()
        let outputG = createCollectingOutputStream(collector: collectorG)
        let emptyStream3 = createSinglePayloadStream(mediaUrn: "media:void", data: Data())
        try invokeOp(fGamma, input: streamToInputPackage(emptyStream3), output: outputG)
        XCTAssertEqual(collectorG.getData(), "g".data(using: .utf8)!)
    }

    // TEST271: Test Op handler replacing an existing registration for the same cap URN
    func test271_handlerReplacement() throws {
        let runtime = CartridgeRuntime(manifest: Self.testManifestData)

        runtime.register_op(capUrn: "cap:op=test") { AnyOp(WriteFixedOp(data: Data("first".utf8))) }
        runtime.register_op(capUrn: "cap:op=test") { AnyOp(WriteFixedOp(data: Data("second".utf8))) }

        let factory = try XCTUnwrap(runtime.findHandler(capUrn: "cap:op=test"))
        let collector = OutputCollector()
        let output = createCollectingOutputStream(collector: collector)
        let emptyStream = createSinglePayloadStream(mediaUrn: "media:void", data: Data())
        try invokeOp(factory, input: streamToInputPackage(emptyStream), output: output)
        XCTAssertEqual(String(data: collector.getData(), encoding: .utf8), "second",
            "later registration must replace earlier")
    }

    // MARK: - NoPeerInvoker Tests (TEST254-255)

    // TEST254: Test NoPeerInvoker always returns PeerRequest error
    func test254_noPeerInvoker() {
        let noPeer = NoPeerInvoker()

        XCTAssertThrowsError(try noPeer.call(capUrn: "cap:op=test")) { error in
            if let runtimeError = error as? CartridgeRuntimeError,
               case .peerRequestError(let msg) = runtimeError {
                XCTAssertTrue(msg.lowercased().contains("not supported"),
                    "error must indicate peer not supported: \(msg)")
            } else {
                XCTFail("expected peerRequestError, got \(error)")
            }
        }
    }

    // TEST255: Test NoPeerInvoker call_with_bytes also returns error
    func test255_noPeerInvokerWithArguments() {
        let noPeer = NoPeerInvoker()

        XCTAssertThrowsError(try noPeer.call(capUrn: "cap:op=test"),
            "must throw error")
    }

    // MARK: - Runtime Creation Tests (TEST256-258)

    // TEST256: Test CartridgeRuntime::with_manifest_json stores manifest data and parses when valid
    func test256_withManifestJson() {
        let runtime = CartridgeRuntime(manifestJSON: Self.testManifestJSON)
        XCTAssertFalse(runtime.manifestData.isEmpty, "manifestData must be populated")
        // Note: "cap:op=test" may or may not parse as valid Manifest depending on validation
    }

    // TEST257: Test CartridgeRuntime::new with invalid JSON still creates runtime (manifest is None)
    func test257_newWithInvalidJson() {
        let runtime = CartridgeRuntime(manifest: "not json".data(using: .utf8)!)
        XCTAssertFalse(runtime.manifestData.isEmpty, "manifestData should store raw bytes")
        XCTAssertNil(runtime.parsedManifest, "invalid JSON should leave parsedManifest as nil")
    }

    // TEST258: Test CartridgeRuntime::with_manifest creates runtime with valid manifest data
    func test258_withManifestStruct() {
        let runtime = CartridgeRuntime(manifest: Self.testManifestData)
        XCTAssertFalse(runtime.manifestData.isEmpty)
        // parsedManifest may or may not be nil depending on whether "cap:op=test" validates
        // The key behavior is that manifestData is stored
    }

    // MARK: - Extract Effective Payload Tests (TEST259-265, TEST272-273)

    // TEST259: Test extract_effective_payload with non-CBOR content_type returns raw payload unchanged
    func test259_extractEffectivePayloadNonCbor() throws {
        let cap = makeTestCap(urn: "cap:in=\"media:void\";op=test;out=\"media:void\"", args: [])
        let payload = "raw data".data(using: .utf8)!
        let result = try extractEffectivePayload(payload: payload, contentType: "application/json", cap: cap, isCliMode: true)
        XCTAssertEqual(result, payload)
    }

    // TEST260: Test extract_effective_payload with empty content_type returns raw payload unchanged
    func test260_extractEffectivePayloadNoContentType() throws {
        let cap = makeTestCap(urn: "cap:in=\"media:void\";op=test;out=\"media:void\"", args: [])
        let payload = "raw data".data(using: .utf8)!
        let result = try extractEffectivePayload(payload: payload, contentType: nil, cap: cap, isCliMode: true)
        XCTAssertEqual(result, payload)
    }

    // TEST261: Test extract_effective_payload with CBOR content extracts matching argument value
    func test261_extractEffectivePayloadCborMatch() throws {
        // Build CBOR: [{media_urn: "media:string;textable", value: bytes("hello")}]
        let cborArray: CBOR = .array([
            .map([
                .utf8String("media_urn"): .utf8String("media:string;textable"),
                .utf8String("value"): .byteString([UInt8]("hello".utf8))
            ])
        ])
        let payload = Data(cborArray.encode())

        let cap = makeTestCap(urn: "cap:in=\"media:string;textable\";op=test;out=\"media:void\"", args: [])
        let result = try extractEffectivePayload(payload: payload, contentType: "application/cbor", cap: cap, isCliMode: false)
        // NEW REGIME: result is full CBOR array; extract value from matching argument
        guard let decoded = try CBOR.decode([UInt8](result)),
              case .array(let arr) = decoded,
              arr.count == 1,
              case .map(let m) = arr[0],
              let valEntry = m[CBOR.utf8String("value")],
              case .byteString(let valBytes) = valEntry
        else { return XCTFail("Expected CBOR array with one arg map containing value bytes") }
        XCTAssertEqual(String(decoding: valBytes, as: UTF8.self), "hello")
    }

    // TEST262: Test extract_effective_payload with CBOR content fails when no argument matches expected input
    func test262_extractEffectivePayloadCborNoMatch() {
        let cborArray: CBOR = .array([
            .map([
                .utf8String("media_urn"): .utf8String("media:other-type"),
                .utf8String("value"): .byteString([UInt8]("data".utf8))
            ])
        ])
        let payload = Data(cborArray.encode())

        let cap = makeTestCap(urn: "cap:in=\"media:string;textable\";op=test;out=\"media:void\"", args: [])
        XCTAssertThrowsError(try extractEffectivePayload(payload: payload, contentType: "application/cbor", cap: cap, isCliMode: false)) { error in
            if let runtimeError = error as? CartridgeRuntimeError,
               case .deserializationError(let msg) = runtimeError {
                XCTAssertTrue(msg.contains("No argument found matching"), "\(msg)")
            }
        }
    }

    // TEST263: Test extract_effective_payload with invalid CBOR bytes returns deserialization error
    func test263_extractEffectivePayloadInvalidCbor() {
        let cap = makeTestCap(urn: "cap:in=\"media:void\";op=test;out=\"media:void\"", args: [])
        XCTAssertThrowsError(try extractEffectivePayload(
            payload: "not cbor".data(using: .utf8)!,
            contentType: "application/cbor",
            cap: cap,
            isCliMode: false
        ))
    }

    // TEST264: Test extract_effective_payload with CBOR non-array (e.g. map) returns error
    func test264_extractEffectivePayloadCborNotArray() {
        let cborMap: CBOR = .map([:])
        let payload = Data(cborMap.encode())

        let cap = makeTestCap(urn: "cap:in=\"media:void\";op=test;out=\"media:void\"", args: [])
        XCTAssertThrowsError(try extractEffectivePayload(payload: payload, contentType: "application/cbor", cap: cap, isCliMode: false)) { error in
            if let runtimeError = error as? CartridgeRuntimeError,
               case .deserializationError(let msg) = runtimeError {
                XCTAssertTrue(msg.contains("must be an array"), "\(msg)")
            }
        }
    }

    // TEST272: Test extract_effective_payload CBOR with multiple arguments selects the correct one
    func test272_extractEffectivePayloadMultipleArgs() throws {
        let cborArray: CBOR = .array([
            .map([
                .utf8String("media_urn"): .utf8String("media:other-type;textable"),
                .utf8String("value"): .byteString([UInt8]("wrong".utf8))
            ]),
            .map([
                .utf8String("media_urn"): .utf8String("media:model-spec;textable"),
                .utf8String("value"): .byteString([UInt8]("correct".utf8))
            ]),
        ])
        let payload = Data(cborArray.encode())

        let cap = makeTestCap(urn: "cap:in=\"media:model-spec;textable\";op=infer;out=\"media:void\"", args: [])
        let result = try extractEffectivePayload(payload: payload, contentType: "application/cbor", cap: cap, isCliMode: false)
        // Handler matches against in_spec to find main input.
        guard let decoded = try CBOR.decode([UInt8](result)),
              case .array(let arr) = decoded
        else { return XCTFail("Expected CBOR array") }
        XCTAssertEqual(arr.count, 2)
        let inSpec = try CSMediaUrn.fromString("media:model-spec;textable")
        var found: [UInt8]? = nil
        for arg in arr {
            guard case .map(let m) = arg else { continue }
            guard case .utf8String(let urnStr) = m[.utf8String("media_urn")] ?? .null,
                  case .byteString(let val) = m[.utf8String("value")] ?? .null
            else { continue }
            if let argUrn = try? CSMediaUrn.fromString(urnStr), inSpec.isComparable(to: argUrn) {
                found = val
                break
            }
        }
        XCTAssertEqual(found.map { String(decoding: $0, as: UTF8.self) }, "correct")
    }

    // TEST273: Test extract_effective_payload with binary data in CBOR value (not just text)
    func test273_extractEffectivePayloadBinaryValue() throws {
        var binaryData = [UInt8]()
        for i: UInt8 in 0...255 { binaryData.append(i) }

        let cborArray: CBOR = .array([
            .map([
                .utf8String("media_urn"): .utf8String("media:pdf"),
                .utf8String("value"): .byteString(binaryData)
            ])
        ])
        let payload = Data(cborArray.encode())

        let cap = makeTestCap(urn: "cap:in=\"media:pdf\";op=process;out=\"media:void\"", args: [])
        let result = try extractEffectivePayload(payload: payload, contentType: "application/cbor", cap: cap, isCliMode: false)
        guard let decoded = try CBOR.decode([UInt8](result)),
              case .array(let arr) = decoded,
              arr.count == 1,
              case .map(let m) = arr[0],
              let valEntry = m[CBOR.utf8String("value")],
              case .byteString(let val) = valEntry
        else { return XCTFail("Expected CBOR array with binary value") }
        XCTAssertEqual(val, binaryData)
    }

    // MARK: - CliStreamEmitter Tests (TEST266-267)
    // TEST266: Test CliFrameSender wraps CliStreamEmitter correctly (basic construction)
    // TEST267: REMOVED - CliStreamEmitter removed

    // MARK: - RuntimeError Display Tests (TEST268)

    // TEST268: Test RuntimeError variants display correct messages
    func test268_runtimeErrorDisplay() {
        let err1 = CartridgeRuntimeError.noHandler("cap:op=missing")
        XCTAssertTrue((err1.errorDescription ?? "").contains("cap:op=missing"))

        let err2 = CartridgeRuntimeError.missingArgument("model")
        XCTAssertTrue((err2.errorDescription ?? "").contains("model"))

        let err3 = CartridgeRuntimeError.unknownSubcommand("badcmd")
        XCTAssertTrue((err3.errorDescription ?? "").contains("badcmd"))

        let err4 = CartridgeRuntimeError.manifestError("parse failed")
        XCTAssertTrue((err4.errorDescription ?? "").contains("parse failed"))

        let err5 = CartridgeRuntimeError.peerRequestError("denied")
        XCTAssertTrue((err5.errorDescription ?? "").contains("denied"))

        let err6 = CartridgeRuntimeError.peerResponseError("timeout")
        XCTAssertTrue((err6.errorDescription ?? "").contains("timeout"))
    }

    // MARK: - Typed Handler Tests (TEST250-251, 253, 266)

    // TEST250: Test Op handler collects input and processes it
    func test250_typedHandlerRegistration() throws {
        // Verify Op handlers can be constructed and registered
        // Op protocol requires: typealias Output, perform(dry:wet:), metadata()

        // Create an Op-conforming type
        let op = EchoAllBytesOp()

        // Verify it has the expected metadata
        let meta = op.metadata()
        XCTAssertEqual(meta.name, "EchoAllBytesOp")

        // Verify AnyOp can wrap it
        let anyOp = AnyOp(op)
        // AnyOp wraps the op correctly if we get here without error
        XCTAssertNotNil(anyOp)
    }

    // TEST251: Test Op handler propagates errors through RuntimeError::Handler
    func test251_typedHandlerErrorPropagation() {
        // Verify that errors thrown from handlers are wrapped correctly
        let error = CartridgeRuntimeError.handlerError("test handler error")
        XCTAssertTrue((error.errorDescription ?? "").contains("Handler"))

        // Verify error types are distinct
        let handlerErr = CartridgeRuntimeError.handlerError("x")
        let protocolErr = CartridgeRuntimeError.protocolError("x")
        XCTAssertNotEqual(handlerErr.errorDescription, protocolErr.errorDescription)
    }

    // TEST253: Test OpFactory can be cloned via Arc and sent across tasks (Send + Sync)
    func test253_handlerIsSendable() async throws {
        // Verify AnyOp is Sendable (can be sent across actor boundaries)
        // EchoAllBytesOp is marked @unchecked Sendable
        let op = AnyOp(EchoAllBytesOp())

        // Use in Task context (requires Sendable)
        let result = await Task.detached {
            // Access the wrapped op - if AnyOp isn't Sendable, this won't compile
            return op
        }.value

        // Verify we got the same op back
        XCTAssertNotNil(result)
    }

    // TEST266: Test CliFrameSender wraps CliStreamEmitter correctly (basic construction)
    func test266_cliFrameSenderConstruction() {
        // Default CLI sender uses NDJSON mode
        let sender = CliFrameSender()
        XCTAssertTrue(sender.ndjson, "default CLI sender must use NDJSON")

        // Can create without NDJSON
        let sender2 = CliFrameSender.withoutNdjson()
        XCTAssertFalse(sender2.ndjson, "withoutNdjson must disable NDJSON")

        // Explicit ndjson parameter
        let sender3 = CliFrameSender(ndjson: false)
        XCTAssertFalse(sender3.ndjson)

        let sender4 = CliFrameSender(ndjson: true)
        XCTAssertTrue(sender4.ndjson)
    }

}

// =============================================================================
// CapArgumentValue Tests (TEST274-278, TEST282-283)
// =============================================================================

final class CapArgumentValueTests: XCTestCase {

    // TEST274: Test CapArgumentValue::new stores media_urn and raw byte value
    func test274_capArgumentValueNew() {
        let arg = CapArgumentValue(
            mediaUrn: "media:model-spec;textable",
            value: "gpt-4".data(using: .utf8)!
        )
        XCTAssertEqual(arg.mediaUrn, "media:model-spec;textable")
        XCTAssertEqual(arg.value, "gpt-4".data(using: .utf8)!)
    }

    // TEST275: Test CapArgumentValue::from_str converts string to UTF-8 bytes
    func test275_capArgumentValueFromStr() {
        let arg = CapArgumentValue.fromString(mediaUrn: "media:string;textable", value: "hello world")
        XCTAssertEqual(arg.mediaUrn, "media:string;textable")
        XCTAssertEqual(arg.value, "hello world".data(using: .utf8)!)
    }

    // TEST276: Test CapArgumentValue::value_as_str succeeds for UTF-8 data
    func test276_capArgumentValueAsStrValid() throws {
        let arg = CapArgumentValue.fromString(mediaUrn: "media:string", value: "test")
        XCTAssertEqual(try arg.valueAsString(), "test")
    }

    // TEST277: Test CapArgumentValue::value_as_str fails for non-UTF-8 binary data
    func test277_capArgumentValueAsStrInvalidUtf8() {
        let arg = CapArgumentValue(mediaUrn: "media:pdf", value: Data([0xFF, 0xFE, 0x80]))
        XCTAssertThrowsError(try arg.valueAsString(), "non-UTF-8 data must fail")
    }

    // TEST278: Test CapArgumentValue::new with empty value stores empty vec
    func test278_capArgumentValueEmpty() throws {
        let arg = CapArgumentValue(mediaUrn: "media:void", value: Data())
        XCTAssertTrue(arg.value.isEmpty)
        XCTAssertEqual(try arg.valueAsString(), "")
    }

    // TEST282: Test CapArgumentValue::from_str with Unicode string preserves all characters
    func test282_capArgumentValueUnicode() throws {
        let arg = CapArgumentValue.fromString(mediaUrn: "media:string", value: "hello 世界 🌍")
        XCTAssertEqual(try arg.valueAsString(), "hello 世界 🌍")
    }

    // TEST283: Test CapArgumentValue with large binary payload preserves all bytes
    func test283_capArgumentValueLargeBinary() {
        var data = Data()
        for _ in 0..<40 {  // 40 * 256 = 10240 > 10000
            for i: UInt8 in 0...255 {
                data.append(i)
            }
        }
        data = data.prefix(10000)  // trim to exactly 10000
        let arg = CapArgumentValue(mediaUrn: "media:pdf", value: data)
        XCTAssertEqual(arg.value.count, 10000)
        XCTAssertEqual(arg.value, data)
    }
}

// =============================================================================
// File-Path to Bytes Conversion Tests (TEST336-TEST360)
// =============================================================================

@available(macOS 10.15.4, iOS 13.4, *)
final class CborFilePathConversionTests: XCTestCase {

    // Helper to create test manifest with caps. Caps live exclusively
    // inside cap_groups now; tests get a single "default" group. Channel
    // is part of the cartridge's identity — fixtures use "release" since
    // these tests don't exercise channel-specific behaviour.
    private func createTestManifest(caps: [CapDefinition]) -> Data {
        // Always append CAP_IDENTITY at the end - cartridges must declare it
        // (Appending instead of prepending to avoid breaking tests that reference caps[0])
        var allCaps = caps
        let identityCap = CapDefinition(
            urn: "cap:",
            title: "Identity",
            command: "identity"
        )
        allCaps.append(identityCap)

        let manifest = Manifest(
            name: "TestCartridge",
            version: "1.0.0",
            channel: "release",
            description: "Test cartridge",
            capGroups: [CapGroup(name: "default", caps: allCaps, adapterUrns: [])]
        )
        return try! JSONEncoder().encode(manifest)
    }

    // Helper to create a cap definition
    private func createCap(
        urn: String,
        title: String,
        command: String,
        args: [CapArg] = []
    ) -> CapDefinition {
        return CapDefinition(
            urn: urn,
            title: title,
            command: command,
            capDescription: nil,
            args: args
        )
    }

    // Helper mirroring Rust test_filepath_conversion: drives CLI flow and
    // extracts the first arg's `value` bytes from the post-extract CBOR array.
    private func filepathConversion(cap: CapDefinition, cliArgs: [String], runtime: CartridgeRuntime) throws -> Data {
        let raw = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: raw, contentType: "application/cbor", cap: cap, isCliMode: true)
        guard let decoded = try CBOR.decode([UInt8](payload)),
              case .array(let arr) = decoded,
              !arr.isEmpty,
              case .map(let m) = arr[0],
              case .byteString(let bytes) = m[.utf8String("value")] ?? .null
        else { throw CartridgeRuntimeError.deserializationError("Expected CBOR array with byteString value") }
        return Data(bytes)
    }

    // Helper mirroring Rust test_filepath_array_conversion: drives CLI flow
    // and returns the first arg's value as a [Data] sequence.
    private func filepathArrayConversion(cap: CapDefinition, cliArgs: [String], runtime: CartridgeRuntime) throws -> [Data] {
        let raw = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: raw, contentType: "application/cbor", cap: cap, isCliMode: true)
        guard let decoded = try CBOR.decode([UInt8](payload)),
              case .array(let arr) = decoded,
              !arr.isEmpty,
              case .map(let m) = arr[0],
              case .array(let items) = m[.utf8String("value")] ?? .null
        else { throw CartridgeRuntimeError.deserializationError("Expected CBOR array with array value") }
        var out: [Data] = []
        for item in items {
            if case .byteString(let b) = item { out.append(Data(b)) }
        }
        return out
    }

    // Helper to create a cap arg
    private func createArg(
        mediaUrn: String,
        required: Bool,
        isSequence: Bool = false,
        sources: [ArgSource]
    ) -> CapArg {
        return CapArg(
            mediaUrn: mediaUrn,
            required: required,
            isSequence: isSequence,
            sources: sources,
            argDescription: nil,
            defaultValue: nil
        )
    }

    // TEST336: Single file-path arg with stdin source reads file and passes bytes to handler
    // TEST336: Single file-path arg with stdin source reads file and passes
    // bytes to handler. Mirrors Rust test336_file_path_reads_file_passes_bytes.
    func test336_file_path_reads_file_passes_bytes() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test336_input.pdf")
        try Data("PDF binary content 336".utf8).write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let cap = createCap(
            urn: "cap:in=\"media:pdf\";op=process;out=\"media:void\"",
            title: "Process PDF",
            command: "process",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.stdin("media:pdf"), .positional(0)]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let received = NSLockedBytes()
        runtime.register_op(capUrn: cap.urn) { AnyOp(ExtractValueOp(received: received)) }

        // Simulate CLI invocation: cartridge process /path/to/file.pdf
        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", cap: cap, isCliMode: true)

        let factory = try XCTUnwrap(runtime.findHandler(capUrn: cap.urn))
        let collector = OutputCollector()
        let output = createCollectingOutputStream(collector: collector)
        try invokeOp(factory, input: testInputPackage([("media:", payload)]), output: output)

        // Verify handler decoded the args and received file bytes (not file path string).
        XCTAssertEqual(received.get(), Data("PDF binary content 336".utf8),
                       "Handler receives file bytes after auto-conversion")
    }

    // TEST337: file-path arg without stdin source passes path as string (no conversion).
    // Mirrors Rust test337_file_path_without_stdin_passes_string.
    func test337_file_path_without_stdin_passes_string() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test337_input.txt")
        try Data("content".utf8).write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let cap = createCap(
            urn: "cap:in=\"media:void\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.positional(0)]  // NO stdin source!
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let (result, cameFromStdin) = try runtime.extractArgValue(argDef: cap.args[0], cliArgs: cliArgs, stdinData: nil)
        XCTAssertFalse(cameFromStdin)
        let valueStr = String(decoding: result ?? Data(), as: UTF8.self)
        XCTAssertTrue(valueStr.contains("test337_input.txt"),
                      "Should receive file path string when no stdin source: \(valueStr)")
    }

    // TEST338: file-path arg reads file via --file CLI flag.
    // Mirrors Rust test338_file_path_via_cli_flag.
    func test338_file_path_via_cli_flag() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test338.pdf")
        try Data("PDF via flag 338".utf8).write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let cap = createCap(
            urn: "cap:in=\"media:pdf\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.stdin("media:pdf"), .cliFlag("--file")]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = ["--file", testFile.path]
        let fileContents = try filepathConversion(cap: cap, cliArgs: cliArgs, runtime: runtime)
        XCTAssertEqual(fileContents, Data("PDF via flag 338".utf8), "Should read file from --file flag")
    }

    // TEST339: A sequence-declared file-path arg (isSequence=true) expands a
    // glob into N files and the runtime delivers them as a CBOR Array of
    // bytes — one item per matched file. List-ness comes from the arg
    // declaration, NOT from any `;list` URN tag.
    // TEST339: A sequence-declared file-path arg expands a glob to N files
    // and the runtime delivers them as a CBOR Array of bytes — one item per
    // matched file. List-ness comes from the arg declaration, not from any
    // `;list` URN tag. Mirrors Rust test339_file_path_array_glob_expansion.
    func test339_file_path_array_glob_expansion() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test339")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("doc1.txt")
        let file2 = tempDir.appendingPathComponent("doc2.txt")
        try Data("content1".utf8).write(to: file1)
        try Data("content2".utf8).write(to: file2)

        let cap = createCap(
            urn: "cap:in=\"media:\";op=batch;out=\"media:void\"",
            title: "Batch",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                isSequence: true,
                sources: [.stdin("media:"), .positional(0)]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        // CLI: bare glob pattern.
        let pattern = "\(tempDir.path)/*.txt"
        let cliArgs = [pattern]
        let filesBytes = try filepathArrayConversion(cap: cap, cliArgs: cliArgs, runtime: runtime)
        XCTAssertEqual(filesBytes.count, 2, "Should find 2 files")
        let sorted = filesBytes.sorted { $0.lexicographicallyPrecedes($1) }
        XCTAssertEqual(sorted, [Data("content1".utf8), Data("content2".utf8)])
    }

    // TEST340: File not found error provides clear message
    func test340_file_not_found_clear_error() throws {
        let cap = createCap(
            urn: "cap:in=\"media:pdf\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [
                    .stdin("media:pdf"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = ["/nonexistent/file.pdf"]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        XCTAssertThrowsError(try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", cap: cap, isCliMode: true)) { error in
            let errMsg = error.localizedDescription
            XCTAssertTrue(errMsg.contains("/nonexistent/file.pdf"), "Error should mention file path; got: \(errMsg)")
            XCTAssertTrue(errMsg.contains("File not found") || errMsg.contains("Failed to read file"),
                          "Error should be clear; got: \(errMsg)")
        }
    }

    // TEST341: stdin takes precedence over file-path in source order.
    // Mirrors Rust test341_stdin_precedence_over_file_path.
    func test341_stdin_precedence_over_file_path() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test341_input.txt")
        try Data("file content".utf8).write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        // Stdin source comes BEFORE position source.
        let cap = createCap(
            urn: "cap:in=\"media:\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.stdin("media:"), .positional(0)]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let stdinData = Data("stdin content 341".utf8)
        let (result, cameFromStdin) = try runtime.extractArgValue(argDef: cap.args[0], cliArgs: cliArgs, stdinData: stdinData)
        XCTAssertTrue(cameFromStdin)
        XCTAssertEqual(result, stdinData, "stdin source should take precedence")
    }

    // TEST342: file-path with position 0 reads first positional arg as file.
    // Mirrors Rust test342_file_path_position_zero_reads_first_arg.
    func test342_file_path_position_zero_reads_first_arg() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test342.dat")
        try Data("binary data 342".utf8).write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let cap = createCap(
            urn: "cap:in=\"media:\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.stdin("media:"), .positional(0)]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let result = try filepathConversion(cap: cap, cliArgs: cliArgs, runtime: runtime)
        XCTAssertEqual(result, Data("binary data 342".utf8), "Should read file at position 0")
    }

    // TEST343: Non-file-path args are not affected by file reading.
    // Mirrors Rust test343_non_file_path_args_unaffected.
    func test343_non_file_path_args_unaffected() throws {
        let cap = createCap(
            urn: "cap:in=\"media:void\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:model-spec;textable",  // NOT file-path
                required: true,
                sources: [.stdin("media:model-spec;textable"), .positional(0)]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = ["mlx-community/Llama-3.2-3B-Instruct-4bit"]
        let (result, _) = try runtime.extractArgValue(argDef: cap.args[0], cliArgs: cliArgs, stdinData: nil)
        let valueStr = String(decoding: result ?? Data(), as: UTF8.self)
        XCTAssertEqual(valueStr, "mlx-community/Llama-3.2-3B-Instruct-4bit")
    }

    // TEST344: A scalar file-path arg receiving a nonexistent path fails
    // hard with a clear error that names the path. The runtime refuses to
    // silently swallow user mistakes like typos or wrong directories.
    func test344_file_path_array_invalid_json_fails() throws {
        let cap = createCap(
            urn: "cap:in=\"media:\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [
                    .stdin("media:"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = ["/nonexistent/path/to/nothing"]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        XCTAssertThrowsError(try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", cap: cap, isCliMode: true)) { error in
            let err = error.localizedDescription
            XCTAssertTrue(err.contains("/nonexistent/path/to/nothing"), "Error should mention the path; got: \(err)")
            XCTAssertTrue(err.contains("File not found") || err.contains("Failed to read"),
                          "Error should be clear about file access failure; got: \(err)")
        }
    }

    // TEST345: file-path arg with literal nonexistent path fails hard.
    // Mirrors Rust test345_file_path_array_one_file_missing_fails_hard.
    func test345_file_path_array_one_file_missing_fails_hard() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let missingPath = tempDir.appendingPathComponent("test345_missing.txt")

        let cap = createCap(
            urn: "cap:in=\"media:\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.stdin("media:"), .positional(0)]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [missingPath.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        XCTAssertThrowsError(try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", cap: cap, isCliMode: true)) { error in
            let err = error.localizedDescription
            XCTAssertTrue(err.contains("test345_missing.txt"), "Error should mention the missing file; got: \(err)")
            XCTAssertTrue(err.contains("File not found") || err.contains("doesn't exist"),
                          "Error should be clear about missing file; got: \(err)")
        }
    }

    // TEST346: Large file (1MB) reads successfully
    func test346_large_file_reads_successfully() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test346_large.bin")

        // Create 1MB file
        var largeData = Data()
        for _ in 0..<1_000_000 {
            largeData.append(42)
        }
        try largeData.write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [
                    .stdin("media:"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let result = try filepathConversion(cap: cap, cliArgs: cliArgs, runtime: runtime)
        XCTAssertEqual(result.count, 1_000_000, "Should read entire 1MB file")
        XCTAssertEqual(result, largeData, "Content should match exactly")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST347: Empty file reads as empty bytes.
    // Mirrors Rust test347_empty_file_reads_as_empty_bytes.
    func test347_empty_file_reads_as_empty_bytes() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test347_empty.txt")
        try Data().write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let cap = createCap(
            urn: "cap:in=\"media:\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.stdin("media:"), .positional(0)]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let result = try filepathConversion(cap: cap, cliArgs: cliArgs, runtime: runtime)
        XCTAssertEqual(result, Data(), "Empty file should produce empty bytes")
    }

    // TEST348: file-path conversion respects source order.
    // Mirrors Rust test348_file_path_conversion_respects_source_order.
    func test348_file_path_conversion_respects_source_order() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test348.txt")
        try Data("file content 348".utf8).write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        // Position source BEFORE stdin source.
        let cap = createCap(
            urn: "cap:in=\"media:\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.positional(0), .stdin("media:")]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let result = try filepathConversion(cap: cap, cliArgs: cliArgs, runtime: runtime)
        XCTAssertEqual(result, Data("file content 348".utf8), "Position source tried first, file read")
    }

    // TEST349: file-path arg with multiple sources tries all in order
    func test349_file_path_multiple_sources_fallback() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test349.txt")
        try Data("content 349".utf8).write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [
                    .cliFlag("--file"),     // First (not provided)
                    .positional(0),         // Second (provided)
                    .stdin("media:")   // Third (not used)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        // Only provide position arg, no --file flag
        let cliArgs = [testFile.path]
        let result = try filepathConversion(cap: cap, cliArgs: cliArgs, runtime: runtime)
        XCTAssertEqual(result, Data("content 349".utf8), "Should fall back to position source and read file")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST350: Integration test - full CLI mode invocation with file-path
    func test350_full_cli_mode_with_file_path_integration() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test350_input.pdf")
        let testContent = Data("PDF file content for integration test".utf8)
        try testContent.write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let cap = createCap(
            urn: "cap:in=\"media:pdf\";op=process;out=\"media:result;textable\"",
            title: "Process PDF",
            command: "process",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.stdin("media:pdf"), .positional(0)]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let received = NSLockedBytes()
        runtime.register_op(capUrn: cap.urn) { AnyOp(ExtractValueOp(received: received)) }

        // Simulate full CLI invocation
        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let payload = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", cap: cap, isCliMode: true)

        let factory = try XCTUnwrap(runtime.findHandler(capUrn: cap.urn))
        let collector = OutputCollector()
        let output = createCollectingOutputStream(collector: collector)
        try invokeOp(factory, input: testInputPackage([("media:", payload)]), output: output)

        // Verify handler received file bytes after auto-conversion.
        XCTAssertEqual(received.get(), testContent,
                       "Handler receives file bytes after auto-conversion")
    }

    // TEST351: file-path arg in CBOR mode with empty Array value returns
    // empty. CBOR Array (not JSON) is the multi-input wire form for sequence
    // args. Mirrors Rust test351_file_path_array_empty_array.
    func test351_file_path_array_empty_array() throws {
        let cap = createCap(
            urn: "cap:in=\"media:\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: false,
                isSequence: true,
                sources: [.stdin("media:")]
            )]
        )

        // CBOR-mode payload: value is an empty Array.
        let arg: CBOR = .map([
            .utf8String("media_urn"): .utf8String("media:file-path;textable"),
            .utf8String("value"): .array([])
        ])
        let payload = Data(CBOR.array([arg]).encode())
        let result = try extractEffectivePayload(payload: payload, contentType: "application/cbor", cap: cap, isCliMode: false)

        guard let decoded = try CBOR.decode([UInt8](result)),
              case .array(let arr) = decoded,
              arr.count == 1,
              case .map(let m) = arr[0],
              case .array(let value) = m[.utf8String("value")] ?? .null
        else { return XCTFail("Expected CBOR array with array value") }
        XCTAssertEqual(value.count, 0, "Empty array should produce empty result")
    }

    #if os(macOS) || os(Linux)
    // TEST352: file permission denied error is clear (Unix-specific)
    func test352_file_permission_denied_clear_error() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test352_noperm.txt")
        try Data("content".utf8).write(to: testFile)

        // Remove read permissions
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: testFile.path)

        let cap = createCap(
            urn: "cap:in=\"media:\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [
                    .stdin("media:"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        XCTAssertThrowsError(try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", cap: cap, isCliMode: true)) { error in
            let err = error.localizedDescription
            XCTAssertTrue(err.contains("test352_noperm.txt"), "Error should mention the file: \(err)")
        }

        // Cleanup: restore permissions then delete
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: testFile.path)
        try? FileManager.default.removeItem(at: testFile)
    }
    #endif

    // TEST353: CBOR payload format matches between CLI and CBOR mode
    func test353_cbor_payload_format_consistency() throws {
        let cap = createCap(
            urn: "cap:in=\"media:text;textable\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:text;textable",
                required: true,
                sources: [
                    .stdin("media:text;textable"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = ["test value"]
        let payload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Decode CBOR payload
        guard let cborValue = try? CBOR.decode([UInt8](payload)) else {
            XCTFail("Failed to decode CBOR")
            return
        }

        guard case .array(let argsArray) = cborValue else {
            XCTFail("Expected CBOR array")
            return
        }

        XCTAssertEqual(argsArray.count, 1, "Should have 1 argument")

        // Verify structure: { media_urn: "...", value: bytes }
        guard case .map(let argMap) = argsArray[0] else {
            XCTFail("Expected CBOR map")
            return
        }

        XCTAssertEqual(argMap.count, 2, "Argument should have media_urn and value")

        // Check media_urn key
        let mediaUrnKey = CBOR.utf8String("media_urn")
        guard let mediaUrnVal = argMap[mediaUrnKey],
              case .utf8String(let urnStr) = mediaUrnVal else {
            XCTFail("Should have media_urn key with string value")
            return
        }
        XCTAssertEqual(urnStr, "media:text;textable")

        // Check value key
        let valueKey = CBOR.utf8String("value")
        guard let valueVal = argMap[valueKey],
              case .byteString(let bytes) = valueVal else {
            XCTFail("Should have value key with bytes")
            return
        }
        XCTAssertEqual(bytes, [UInt8]("test value".utf8))
    }

    // TEST354: Glob pattern with no matches fails hard (NO FALLBACK).
    // Mirrors Rust test354_glob_pattern_no_matches_empty_array.
    func test354_glob_pattern_no_matches_fails_hard() throws {
        let tempDir = FileManager.default.temporaryDirectory

        let cap = createCap(
            urn: "cap:in=\"media:\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.stdin("media:"), .positional(0)]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        // CLI: bare glob that matches nothing — must fail hard.
        let pattern = "\(tempDir.path)/nonexistent_*.xyz"
        let cliArgs = [pattern]
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        XCTAssertThrowsError(try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", cap: cap, isCliMode: true)) { error in
            let err = error.localizedDescription
            XCTAssertTrue(err.contains("No files matched") || err.contains("nonexistent"),
                          "Should fail hard when glob matches nothing — NO FALLBACK; got: \(err)")
        }
    }

    // TEST355: Glob pattern skips directories.
    func test355_glob_pattern_skips_directories() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test355")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let subdir = tempDir.appendingPathComponent("subdir")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        let file1 = tempDir.appendingPathComponent("file1.txt")
        try Data("content1".utf8).write(to: file1)

        let cap = createCap(
            urn: "cap:in=\"media:\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                isSequence: true,
                sources: [
                    .stdin("media:"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let pattern = "\(tempDir.path)/*"
        let cliArgs = [pattern]
        let files = try filepathArrayConversion(cap: cap, cliArgs: cliArgs, runtime: runtime)
        XCTAssertEqual(files.count, 1, "Should only include files, not directories")
        XCTAssertEqual(files[0], Data("content1".utf8))

        try? FileManager.default.removeItem(at: tempDir)
    }

    // TEST356: Multiple glob patterns combined as CBOR Array (CBOR mode).
    // Mirrors Rust test356_multiple_glob_patterns_combined.
    func test356_multiple_glob_patterns_combined() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test356")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("doc.txt")
        let file2 = tempDir.appendingPathComponent("data.json")
        try Data("text".utf8).write(to: file1)
        try Data("json".utf8).write(to: file2)

        let cap = createCap(
            urn: "cap:in=\"media:\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                isSequence: true,
                sources: [.stdin("media:"), .positional(0)]
            )]
        )

        let pattern1 = "\(tempDir.path)/*.txt"
        let pattern2 = "\(tempDir.path)/*.json"

        // Build CBOR payload with Array of patterns (CBOR mode allows arrays).
        let arg: CBOR = .map([
            .utf8String("media_urn"): .utf8String("media:file-path;textable"),
            .utf8String("value"): .array([.utf8String(pattern1), .utf8String(pattern2)])
        ])
        let payload = Data(CBOR.array([arg]).encode())

        let result = try extractEffectivePayload(payload: payload, contentType: "application/cbor", cap: cap, isCliMode: false)

        guard let decoded = try CBOR.decode([UInt8](result)),
              case .array(let arr) = decoded,
              !arr.isEmpty,
              case .map(let m) = arr[0],
              case .array(let filesArray) = m[.utf8String("value")] ?? .null
        else { return XCTFail("Expected CBOR array with array value") }

        XCTAssertEqual(filesArray.count, 2, "Should find both files from different patterns")

        var contents: [[UInt8]] = []
        for val in filesArray {
            if case .byteString(let bytes) = val {
                contents.append(bytes)
            } else {
                XCTFail("Expected bytes")
            }
        }
        contents.sort { $0.lexicographicallyPrecedes($1) }
        XCTAssertEqual(contents, [[UInt8]("json".utf8), [UInt8]("text".utf8)])

        try? FileManager.default.removeItem(at: tempDir)
    }

    #if os(macOS) || os(Linux)
    // TEST357: Symlinks are followed when reading files
    func test357_symlinks_followed() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test357")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let realFile = tempDir.appendingPathComponent("real.txt")
        let linkFile = tempDir.appendingPathComponent("link.txt")
        try Data("real content".utf8).write(to: realFile)
        try FileManager.default.createSymbolicLink(at: linkFile, withDestinationURL: realFile)

        let cap = createCap(
            urn: "cap:in=\"media:\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [
                    .stdin("media:"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [linkFile.path]
        let result = try filepathConversion(cap: cap, cliArgs: cliArgs, runtime: runtime)
        XCTAssertEqual(result, Data("real content".utf8), "Should follow symlink and read real file")

        try? FileManager.default.removeItem(at: tempDir)
    }
    #endif

    // TEST358: Binary file with non-UTF8 data reads correctly
    func test358_binary_file_non_utf8() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test358.bin")

        // Binary data that's not valid UTF-8
        let binaryData = Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0x7F, 0xAB, 0xCD])
        try binaryData.write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:\";op=test;out=\"media:void\"",
            title: "Test",
            command: "test",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [
                    .stdin("media:"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [testFile.path]
        let result = try filepathConversion(cap: cap, cliArgs: cliArgs, runtime: runtime)
        XCTAssertEqual(result, binaryData, "Binary data should read correctly")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST359: Invalid glob pattern fails with a clear error.
    // Mirrors Rust test359_invalid_glob_pattern_fails.
    func test359_invalid_glob_pattern_fails() {
        let cap = createCap(
            urn: "cap:in=\"media:\";op=batch;out=\"media:void\"",
            title: "Test",
            command: "batch",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                isSequence: true,
                sources: [.stdin("media:"), .positional(0)]
            )]
        )

        // Invalid glob pattern (unclosed bracket) sent in CBOR mode.
        let arg: CBOR = .map([
            .utf8String("media_urn"): .utf8String("media:file-path;textable"),
            .utf8String("value"): .utf8String("[invalid")
        ])
        let payload = Data(CBOR.array([arg]).encode())

        XCTAssertThrowsError(try extractEffectivePayload(payload: payload, contentType: "application/cbor", cap: cap, isCliMode: true)) { error in
            let err = error.localizedDescription
            XCTAssertTrue(err.contains("Invalid glob pattern") || err.contains("Pattern"),
                          "Error should mention invalid glob: \(err)")
        }
    }

    // TEST360: Extract effective payload handles file-path data correctly
    func test360_extract_effective_payload_with_file_data() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test360.pdf")
        let pdfContent = Data("PDF content for extraction test".utf8)
        try pdfContent.write(to: testFile)

        let cap = createCap(
            urn: "cap:in=\"media:pdf\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [
                    .stdin("media:pdf"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let cliArgs = [testFile.path]

        // NEW REGIME: extract_effective_payload returns the full CBOR args
        // array; the matching arg's value is the file bytes after auto-conv.
        let rawPayload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)
        let effective = try extractEffectivePayload(payload: rawPayload, contentType: "application/cbor", cap: cap, isCliMode: true)

        guard let decoded = try CBOR.decode([UInt8](effective)),
              case .array(let arr) = decoded
        else { return XCTFail("Expected CBOR array") }

        let inSpec = try CSMediaUrn.fromString("media:pdf")
        var foundValue: Data? = nil
        for arg in arr {
            guard case .map(let m) = arg else { continue }
            guard case .utf8String(let urnStr) = m[.utf8String("media_urn")] ?? .null,
                  case .byteString(let val) = m[.utf8String("value")] ?? .null
            else { continue }
            if let argUrn = try? CSMediaUrn.fromString(urnStr), inSpec.isComparable(to: argUrn) {
                foundValue = Data(val)
                break
            }
        }
        XCTAssertEqual(foundValue, pdfContent, "File-path auto-converted to bytes")

        try? FileManager.default.removeItem(at: testFile)
    }

    // TEST395: Small payload (< max_chunk) produces correct CBOR arguments
    func test395_build_payload_small() throws {
        let cap = CapDefinition(
            urn: "cap:in=\"media:\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: []
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let data = "small payload".data(using: .utf8)!
        let reader = InputStream(data: data)

        let payload = try runtime.buildPayloadFromStreamingReader(cap: cap, reader: reader, maxChunk: DEFAULT_MAX_CHUNK)

        // Verify CBOR structure
        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        guard case .array(let arr) = decoded else {
            XCTFail("Expected array, got: \(String(describing: decoded))")
            return
        }
        XCTAssertEqual(arr.count, 1, "Should have one argument")

        guard case .map(let argMap) = arr[0] else {
            XCTFail("Expected map, got: \(arr[0])")
            return
        }

        guard case .byteString(let valueBytes) = argMap[CBOR.utf8String("value")] else {
            XCTFail("Expected bytes for value")
            return
        }

        XCTAssertEqual(Data(valueBytes), data, "Payload bytes should match")
    }

    // TEST396: Large payload (> max_chunk) accumulates across chunks correctly
    func test396_build_payload_large() throws {
        let cap = CapDefinition(
            urn: "cap:in=\"media:\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: []
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        // Use small max_chunk to force multi-chunk
        let data = Data((0..<1000).map { UInt8($0 % 256) })
        let reader = InputStream(data: data)

        let payload = try runtime.buildPayloadFromStreamingReader(cap: cap, reader: reader, maxChunk: 100)

        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        guard case .array(let arr) = decoded,
              case .map(let argMap) = arr[0],
              case .byteString(let valueBytes) = argMap[CBOR.utf8String("value")] else {
            XCTFail("Invalid CBOR structure")
            return
        }

        XCTAssertEqual(valueBytes.count, 1000, "All bytes should be accumulated")
        XCTAssertEqual(Data(valueBytes), data, "Data should match exactly")
    }

    // TEST397: Empty reader produces valid empty CBOR arguments
    func test397_build_payload_empty() throws {
        let cap = CapDefinition(
            urn: "cap:in=\"media:\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: []
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let reader = InputStream(data: Data())

        let payload = try runtime.buildPayloadFromStreamingReader(cap: cap, reader: reader, maxChunk: DEFAULT_MAX_CHUNK)

        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        guard case .array(let arr) = decoded,
              case .map(let argMap) = arr[0],
              case .byteString(let valueBytes) = argMap[CBOR.utf8String("value")] else {
            XCTFail("Invalid CBOR structure")
            return
        }

        XCTAssertEqual(valueBytes.count, 0, "Empty reader should produce empty bytes")
    }

    // ErrorInputStream that simulates an IO error
    class ErrorInputStream: Foundation.InputStream {
        private var _streamStatus: Stream.Status = .notOpen
        private var _streamError: Error?

        override func open() {
            _streamStatus = .open
        }

        override func close() {
            _streamStatus = .closed
        }

        override var streamStatus: Stream.Status {
            return _streamStatus
        }

        override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
            _streamError = NSError(domain: "test", code: -1, userInfo: [NSLocalizedDescriptionKey: "simulated read error"])
            return -1 // Simulate error
        }

        override var hasBytesAvailable: Bool {
            return true
        }

        override var streamError: Error? {
            return _streamError
        }
    }

    // TEST398: IO error from reader propagates as RuntimeError::Io
    func test398_build_payload_io_error() {
        let cap = CapDefinition(
            urn: "cap:in=\"media:\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: []
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        let reader = ErrorInputStream()

        XCTAssertThrowsError(try runtime.buildPayloadFromStreamingReader(cap: cap, reader: reader, maxChunk: DEFAULT_MAX_CHUNK)) { thrownError in
            let errorStr = "\(thrownError)"
            XCTAssertTrue(errorStr.contains("simulated read error") || errorStr.contains("Stream read error"),
                          "Expected error to contain 'simulated read error', got: \(errorStr)")
        }
    }

    // TEST361: CLI mode with file path - pass file path as command-line argument
    func test361_cli_mode_file_path() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test361.pdf")
        let pdfContent = Data("PDF content for CLI file path test".utf8)
        try pdfContent.write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let cap = createCap(
            urn: "cap:in=\"media:pdf\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [
                    .stdin("media:pdf"),
                    .positional(0)
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        // CLI mode: pass file path as positional argument
        let cliArgs = [testFile.path]
        let payload = try runtime.buildPayloadFromCli(cap: cap, cliArgs: cliArgs)

        // Verify payload is CBOR array with file-path argument
        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        if case .array = decoded {
            // Success - it's an array
        } else {
            XCTFail("CLI mode should produce CBOR array")
        }
    }

    // TEST362: CLI mode with binary piped in - pipe binary data via stdin This test simulates real-world conditions: - Pure binary data piped to stdin (NOT CBOR) - CLI mode detected (command arg present) - Cap accepts stdin source - Binary is chunked on-the-fly and accumulated - Handler receives complete CBOR payload
    func test362_cli_mode_piped_binary() throws {
        // Simulate large binary being piped (1MB PDF)
        let pdfContent = Data(repeating: 0xAB, count: 1_000_000)

        // Create cap that accepts stdin
        let cap = createCap(
            urn: "cap:in=\"media:pdf\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: [createArg(
                mediaUrn: "media:pdf",
                required: true,
                sources: [
                    .stdin("media:pdf")
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        // Mock stdin with Data (simulates piped binary)
        let mockStdin = InputStream(data: pdfContent)
        mockStdin.open()
        defer { mockStdin.close() }

        // Build payload from streaming reader (what CLI piped mode does)
        let payload = try runtime.buildPayloadFromStreamingReader(cap: cap, reader: mockStdin, maxChunk: DEFAULT_MAX_CHUNK)

        // Verify payload is CBOR array with correct structure
        let decoded = try CBORDecoder(input: [UInt8](payload)).decodeItem()
        guard case .array(let arr) = decoded else {
            XCTFail("Expected CBOR Array")
            return
        }

        XCTAssertEqual(arr.count, 1, "CBOR array should have one argument")

        guard case .map(let argMap) = arr[0] else {
            XCTFail("Expected Map in CBOR array")
            return
        }

        var mediaUrn: String?
        var value: Data?

        for (k, v) in argMap {
            if case .utf8String(let key) = k {
                switch key {
                case "media_urn":
                    if case .utf8String(let s) = v {
                        mediaUrn = s
                    }
                case "value":
                    if case .byteString(let bytes) = v {
                        value = Data(bytes)
                    }
                default:
                    break
                }
            }
        }

        XCTAssertEqual(mediaUrn, "media:pdf", "Media URN should match cap in_spec")
        XCTAssertEqual(value, pdfContent, "Binary content should be preserved exactly")
    }

    // TEST363: CBOR mode with chunked content - send file content streaming as chunks
    func test363_cbor_mode_chunked_content() async throws {
        let pdfContent = Data(repeating: 0xAA, count: 10000)  // 10KB of data

        final class ResultHolder: @unchecked Sendable {
            var data: Data?
        }
        let resultHolder = ResultHolder()

        let cap = createCap(
            urn: "cap:in=\"media:pdf\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: [createArg(
                mediaUrn: "media:pdf",
                required: true,
                sources: [
                    .stdin("media:pdf")
                ]
            )]
        )

        let manifest = createTestManifest(caps: [cap])
        let runtime = CartridgeRuntime(manifest: manifest)

        // Register Op handler that captures received bytes and echoes them
        let resultHolderRef = resultHolder
        runtime.register_op(capUrn: cap.urn) {
            final class CaptureEchoOp: Op, @unchecked Sendable {
                typealias Output = Void
                let holder: ResultHolder
                init(_ h: ResultHolder) { holder = h }
                func perform(dry: DryContext, wet: WetContext) async throws {
                    let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
                    let input = try req.takeInput()
                    let total = try input.collectAllBytes()
                    holder.data = total
                    try req.output().start(isSequence: false)
                    try req.output().write(total)
                }
                func metadata() -> OpMetadata { OpMetadata.builder("CaptureEchoOp").build() }
            }
            return AnyOp(CaptureEchoOp(resultHolderRef))
        }

        // Build CBOR payload
        let args = [CapArgumentValue(mediaUrn: "media:pdf", value: pdfContent)]
        let cborArgs: [CBOR] = args.map { arg in
            CBOR.map([
                CBOR.utf8String("media_urn"): CBOR.utf8String(arg.mediaUrn),
                CBOR.utf8String("value"): CBOR.byteString([UInt8](arg.value))
            ])
        }
        let payloadBytes = Data(CBOR.array(cborArgs).encode())

        // Create InputPackage from payload
        let inputPackage = createInputPackage(fromPayload: payloadBytes, mediaUrn: "media:pdf")

        // Create output collector
        let outputCollector = OutputCollector()
        let outputStream = createCollectingOutputStream(collector: outputCollector, mediaUrn: "media:pdf")

        // Execute Op handler
        let factory = try XCTUnwrap(runtime.findHandler(capUrn: cap.urn))
        try invokeOp(factory, input: inputPackage, output: outputStream)

        XCTAssertEqual(resultHolder.data, pdfContent, "Handler should receive chunked content")
    }

    // TEST364: CBOR mode with file path - file-path arg in CBOR mode is
    // auto-converted to file bytes via extract_effective_payload.
    // Mirrors Rust test364_cbor_mode_file_path.
    func test364_cbor_mode_file_path() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test364.pdf")
        let pdfContent = Data("PDF content for CBOR file path test".utf8)
        try pdfContent.write(to: testFile)
        defer { try? FileManager.default.removeItem(at: testFile) }

        let cap = createCap(
            urn: "cap:in=\"media:pdf\";op=process;out=\"media:void\"",
            title: "Process",
            command: "process",
            args: [createArg(
                mediaUrn: "media:file-path;textable",
                required: true,
                sources: [.stdin("media:pdf")]
            )]
        )

        // Build CBOR arguments with file-path URN.
        let arg: CBOR = .map([
            .utf8String("media_urn"): .utf8String("media:file-path;textable"),
            .utf8String("value"): .byteString([UInt8](testFile.path.utf8))
        ])
        let payload = Data(CBOR.array([arg]).encode())

        // Extract effective payload (triggers file-path auto-conversion).
        let effective = try extractEffectivePayload(payload: payload, contentType: "application/cbor", cap: cap, isCliMode: false)

        // Verify the result is modified CBOR with PDF bytes (not file path) and
        // the arg is relabeled to the stdin source's target URN.
        guard let decoded = try CBOR.decode([UInt8](effective)),
              case .array(let arr) = decoded,
              !arr.isEmpty,
              case .map(let m) = arr[0]
        else { return XCTFail("Expected CBOR array with map[0]") }

        var mediaUrn: String? = nil
        var value: [UInt8]? = nil
        for (k, v) in m {
            if case .utf8String(let key) = k {
                if key == "media_urn", case .utf8String(let s) = v { mediaUrn = s }
                else if key == "value", case .byteString(let b) = v { value = b }
            }
        }
        XCTAssertEqual(mediaUrn, "media:pdf", "Should be relabeled to stdin source target")
        XCTAssertEqual(value.map { Data($0) }, pdfContent, "File-path auto-converted to bytes")
    }
}

// MARK: - Test Helpers

/// Mock FrameSender for collecting output from handlers
private final class MockFrameSender: FrameSender, @unchecked Sendable {
    private let onSend: @Sendable (Frame) -> Void

    init(onSend: @escaping @Sendable (Frame) -> Void) {
        self.onSend = onSend
    }

    func send(_ frame: Frame) throws {
        onSend(frame)
    }
}

/// Collects CBOR output from OutputStream for testing
private final class OutputCollector: @unchecked Sendable {
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

/// Creates an OutputStream that collects emitted data into a buffer
private func createCollectingOutputStream(collector: OutputCollector, mediaUrn: String = "media:") -> Bifaci.OutputStream {
    let mockSender = MockFrameSender { frame in
        if frame.frameType == .chunk, let payload = frame.payload {
            if let cbor = try? CBOR.decode([UInt8](payload)), case .byteString(let bytes) = cbor {
                collector.append(Data(bytes))
            }
        }
    }
    return Bifaci.OutputStream(
        sender: mockSender,
        streamId: "test",
        mediaUrn: mediaUrn,
        requestId: .newUUID(),
        routingId: nil,
        maxChunk: 1000
    )
}

/// Creates an InputPackage from a CBOR payload OR raw bytes
private func createInputPackage(fromPayload payload: Data, mediaUrn: String) -> InputPackage {
    // Try to decode as CBOR - if it fails, treat as raw bytes
    guard let cborValue = try? CBOR.decode([UInt8](payload)) else {
        // Payload is raw bytes, not CBOR - wrap as byteString chunk
        let chunks: [Result<CBOR, StreamError>] = [.success(.byteString([UInt8](payload)))]
        var chunkIndex = 0
        let chunkIterator = AnyIterator<Result<CBOR, StreamError>> {
            guard chunkIndex < chunks.count else { return nil }
            let chunk = chunks[chunkIndex]
            chunkIndex += 1
            return chunk
        }
        let stream = Bifaci.InputStream(mediaUrn: mediaUrn, rx: chunkIterator)
        let streams: [Result<Bifaci.InputStream, StreamError>] = [.success(stream)]
        var streamIndex = 0
        let streamIterator = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
            guard streamIndex < streams.count else { return nil }
            let s = streams[streamIndex]
            streamIndex += 1
            return s
        }
        return InputPackage(rx: streamIterator)
    }

    // Extract value from CBOR arguments format: [{media_urn: "...", value: <bytes>}]
    var extractedValue: CBOR = cborValue
    if case .array(let args) = cborValue, let firstArg = args.first {
        if case .map(let argMap) = firstArg {
            // Extract the "value" field from the argument map
            if let value = argMap[.utf8String("value")] {
                extractedValue = value
            }
        }
    }

    // Create a single chunk with the extracted value
    let chunks: [Result<CBOR, StreamError>] = [.success(extractedValue)]
    var chunkIndex = 0
    let chunkIterator = AnyIterator<Result<CBOR, StreamError>> {
        guard chunkIndex < chunks.count else { return nil }
        let chunk = chunks[chunkIndex]
        chunkIndex += 1
        return chunk
    }

    // Create a single stream
    let stream = Bifaci.InputStream(mediaUrn: mediaUrn, rx: chunkIterator)
    let streams: [Result<Bifaci.InputStream, StreamError>] = [.success(stream)]
    var streamIndex = 0
    let streamIterator = AnyIterator<Result<Bifaci.InputStream, StreamError>> {
        guard streamIndex < streams.count else { return nil }
        let s = streams[streamIndex]
        streamIndex += 1
        return s
    }

    return InputPackage(rx: streamIterator)
}

/// Build an InputPackage from a list of (mediaUrn, data) streams.
/// Each `data` is sent as a single CBOR byteString chunk. Mirrors Rust
/// test_input_package(&[(&str, &[u8])]).
@available(macOS 10.15.4, iOS 13.4, *)
private func testInputPackage(_ streams: [(String, Data)]) -> InputPackage {
    let requestId = MessageId.newUUID()
    var frames: [Frame] = []
    for (mediaUrn, data) in streams {
        let streamId = UUID().uuidString
        frames.append(Frame.streamStart(reqId: requestId, streamId: streamId, mediaUrn: mediaUrn))
        let cborPayload = CBOR.byteString([UInt8](data)).encode()
        let cborData = Data(cborPayload)
        frames.append(Frame.chunk(
            reqId: requestId, streamId: streamId, seq: 0,
            payload: cborData, chunkIndex: 0,
            checksum: Frame.computeChecksum(cborData)
        ))
        frames.append(Frame.streamEnd(reqId: requestId, streamId: streamId, chunkCount: 1))
    }
    frames.append(Frame.end(id: requestId))
    var idx = 0
    let iter = AnyIterator<Frame> {
        guard idx < frames.count else { return nil }
        let f = frames[idx]; idx += 1; return f
    }
    return demuxMultiStream(frameIterator: iter)
}

/// Converts AsyncStream<Frame> to InputPackage by collecting frames synchronously
@available(macOS 10.15.4, iOS 13.4, *)
private func streamToInputPackage(_ stream: AsyncStream<Frame>) -> InputPackage {
    // Collect all frames synchronously
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var collected: [Frame] = []
    Task {
        var frames: [Frame] = []
        for await frame in stream {
            frames.append(frame)
        }
        collected = frames
        semaphore.signal()
    }
    semaphore.wait()
    let allFrames = collected

    var frameIndex = 0
    let frameIterator = AnyIterator<Frame> {
        guard frameIndex < allFrames.count else { return nil }
        let frame = allFrames[frameIndex]
        frameIndex += 1
        return frame
    }

    // Use the demuxMultiStream function from CartridgeRuntime
    return demuxMultiStream(frameIterator: frameIterator)
}
