//
//  ResponseOutputsTests.swift
//  Bifaci
//
//  A cap answers on every output it declares (13.2 §Outputs): one response
//  stream per output, the main one naming none and every other the output it
//  is. Mirrors the reference's cartridge_runtime.rs tests TEST12719-TEST12731.
//
//  Tests use // TEST###: comments matching the Rust implementation for cross-tracking.

import XCTest
import Foundation
import SwiftCBOR
@testable import Bifaci
import CapDAG

/// A network handle under `full`, for handlers run directly by tests.
func fullNetwork() -> NetworkAccess {
    NetworkAccess(LivePolicy(HostPolicy(network: .full)))
}
import Ops

private let SERIES = "media:fmt=json;record;series"
private let FIT = "media:fmt=json;record;regression"
private let RESIDUALS = "media:fmt=json;list;record;residual"
private let NOTE = "media:enc=utf-8;note"
private let REJECTED = "media:enc=utf-8;rejected"

/// `regress`: takes a series; its main output, the fit, is not the first it
/// declares; the residuals are a sequence; a note may not fire; a rejection
/// carries the input and may not fire.
private func regressCap() -> CapDefinition {
    CapDefinition(
        urn: "cap:in=\"\(SERIES)\";regress;out=\"\(FIT)\"",
        title: "Regress",
        aliases: ["regress"],
        args: [CapArg(mediaUrn: SERIES, name: "series", required: true, sources: [.stdin(SERIES)])],
        outputs: [
            CapOutput(mediaUrn: RESIDUALS, name: "residuals", outputDescription: "Residuals", isSequence: true),
            CapOutput(mediaUrn: FIT, name: "fit", outputDescription: "The fit"),
            CapOutput(mediaUrn: NOTE, name: "note", outputDescription: "A note", optional: true),
            CapOutput(mediaUrn: REJECTED, name: "rejected", outputDescription: "Rejected input", optional: true, carries: .input),
        ]
    )
}

private func manifest(_ caps: [CapDefinition]) -> Manifest {
    Manifest(
        name: "Regress",
        version: "1.0.0",
        channel: "release",
        registryURL: nil,
        description: "Test",
        capGroups: [CapGroup(name: "default", caps: [identityCapDefinition()] + caps)]
    )
}

/// The outputs of `capUrn` on streams that record every frame they send.
private func recordedOutputs(_ capUrn: String, _ manifest: Manifest?) throws -> (ResponseOutputs, RecordingFrameSender) {
    let sender = RecordingFrameSender()
    let rid = MessageId.newUUID()
    let outputs = try ResponseOutputs.forCap(capUrn, manifest: manifest) { label in
        Bifaci.OutputStream(
            sender: sender,
            streamId: UUID().uuidString,
            mediaUrn: label,
            requestId: rid,
            routingId: nil,
            maxChunk: DEFAULT_MAX_CHUNK
        )
    }
    return (outputs, sender)
}

/// (output named, media label, isSequence, stream id) of every STREAM_START sent.
private func starts(_ sender: RecordingFrameSender) -> [(output: String?, label: String, isSequence: Bool?, streamId: String)] {
    sender.snapshot()
        .filter { $0.frameType == .streamStart }
        .map { (output: $0.outputUrn, label: $0.mediaUrn ?? "", isSequence: $0.isSequence, streamId: $0.streamId ?? "") }
}

private func emptyInput() -> InputPackage {
    var sent = false
    return demuxMultiStream(frameIterator: AnyIterator {
        guard !sent else { return nil }
        sent = true
        return Frame.end(id: .newUUID())
    })
}

/// Writes two residual rows and nothing else, or fails.
private struct ResidualsOnlyOp: Op, Sendable {
    typealias Output = Void
    let fail: Bool

    func perform(dry: DryContext, wet: WetContext) async throws {
        let req = try wet.getRequired(CborRequest.self, for: WET_KEY_REQUEST)
        let residuals = try req.output(for: RESIDUALS)
        try residuals.start(isSequence: true)
        for row in [1, 2] {
            try await residuals.emitListItem(.unsignedInt(UInt64(row)))
        }
        if fail {
            throw CartridgeRuntimeError.handlerError("no fit")
        }
    }

    func metadata() -> OpMetadata { OpMetadata.builder("ResidualsOnlyOp").build() }
}

/// Writes nothing.
private struct SilentOp: Op, Sendable {
    typealias Output = Void
    func perform(dry: DryContext, wet: WetContext) async throws {}
    func metadata() -> OpMetadata { OpMetadata.builder("SilentOp").build() }
}

/// One CHUNK of `stream` carrying `value`.
private func valueChunk(_ rid: MessageId, _ stream: String, _ index: UInt64, _ value: CBOR) -> Frame {
    let payload = Data(value.encode())
    return Frame.chunk(reqId: rid, streamId: stream, seq: 0, payload: payload, chunkIndex: index, checksum: Frame.computeChecksum(payload))
}

private func iterate(_ frames: [Frame]) -> AnyIterator<Frame> {
    var remaining = frames[...]
    return AnyIterator {
        guard let next = remaining.first else { return nil }
        remaining = remaining.dropFirst()
        return next
    }
}

final class ResponseOutputsTests: XCTestCase {

    // TEST12719: a request answers on every output its cap declares. Each has a
    // stream of its own, carrying the label of what it holds: the main output
    // the label the cap's effect derives, another output its own URN, and one
    // that carries the input the cap's declared input. The main output's
    // stream names no output — it is the cap's answer — and every other stream
    // names the output it is. An output is found by its media URN as a tagged
    // URN; one the cap does not declare is unknownOutput.
    func test12719_aRequestAnswersOnEveryDeclaredOutput() throws {
        let cap = regressCap()
        let (outputs, sender) = try recordedOutputs(cap.urn, manifest([cap]))
        let req = CborRequest(input: emptyInput(), outputs: outputs, peer: NoPeerInvoker(), network: fullNetwork())

        // The main output is the one whose URN is `out=`, wherever it is declared.
        XCTAssertTrue(req.output() === (try req.output(for: FIT)))
        XCTAssertTrue(req.output() === (try req.output(for: "media:regression;record;fmt=json")))
        // Another output, with its tags in another order, is the same stream.
        let residuals = try req.output(for: RESIDUALS)
        XCTAssertTrue(residuals === (try req.output(for: "media:residual;record;list;fmt=json")))
        XCTAssertFalse(residuals === req.output())

        for (urn, sequence) in [(FIT, false), (RESIDUALS, true), (NOTE, false), (REJECTED, false)] {
            let stream = try req.output(for: urn)
            XCTAssertFalse(stream.isStarted)
            try stream.start(isSequence: sequence)
            XCTAssertTrue(stream.isStarted)
            try stream.blockingClose()
        }
        let sent = starts(sender)
        XCTAssertEqual(sent.count, 4)
        // Exactly one stream names no output: the main one.
        let unnamed = sent.filter { $0.output == nil }
        XCTAssertEqual(unnamed.count, 1, "\(sent)")
        XCTAssertEqual(unnamed.first?.label, FIT, "the main output carries the label the effect derives")
        XCTAssertFalse(sent.contains { $0.output == FIT }, "the main output is not named")
        func named(_ urn: String) -> String? { sent.first { $0.output == urn }?.label }
        XCTAssertEqual(named(RESIDUALS), RESIDUALS, "another output carries its own URN")
        XCTAssertEqual(named(NOTE), NOTE)
        XCTAssertEqual(named(REJECTED), SERIES, "an output that carries the input is labelled with it")
        XCTAssertEqual(Set(sent.map { $0.streamId }).count, 4, "each output has a stream of its own")

        // What the cap does not declare is not an output of it — a tag short or
        // a tag more is another URN.
        for unknown in ["media:enc=utf-8", "media:fmt=json;record", "media:enc=utf-8;note;extra", "not a urn"] {
            XCTAssertThrowsError(try req.output(for: unknown)) { error in
                guard case CartridgeRuntimeError.unknownOutput(let capUrn, let output) = error else {
                    return XCTFail("\(unknown): expected unknownOutput, got \(error)")
                }
                XCTAssertEqual(capUrn, cap.urn)
                XCTAssertEqual(output, unknown)
            }
        }

        // A request made from a bare stream has the one output that stream is,
        // and nothing is known of the cap it is for.
        let bare = Bifaci.OutputStream(sender: RecordingFrameSender(), streamId: "bare", mediaUrn: "media:",
                                       requestId: .newUUID(), routingId: nil, maxChunk: DEFAULT_MAX_CHUNK)
        let lone = CborRequest(input: emptyInput(), output: bare, peer: NoPeerInvoker(), network: fullNetwork())
        XCTAssertTrue(lone.output() === (try lone.output(for: "media:")))
        XCTAssertThrowsError(try lone.output(for: "media:integer")) { error in
            guard case CartridgeRuntimeError.unknownOutput(let capUrn, let output) = error else {
                return XCTFail("expected unknownOutput, got \(error)")
            }
            XCTAssertEqual(capUrn, "")
            XCTAssertEqual(output, "media:integer")
        }
    }

    // TEST12720: what the runtime sends for outputs the handler did not write
    // to, once it has returned. A required output is sent empty in its declared
    // cardinality, so its consumers get a value; an optional one is not sent —
    // it did not fire. A handler that failed gets nothing sent on its behalf.
    func test12720_unwrittenOutputsWhenTheHandlerReturns() throws {
        let cap = regressCap()
        let regressManifest = manifest([cap])

        var (outputs, sender) = try recordedOutputs(cap.urn, regressManifest)
        try dispatchOp(op: AnyOp(ResidualsOnlyOp(fail: false)), input: emptyInput(), outputs: outputs, peer: NoPeerInvoker(), network: fullNetwork())
        var sent = starts(sender)
        XCTAssertEqual(sent.count, 2, "the written output and the required unwritten one: \(sent)")
        XCTAssertEqual(sent.compactMap { $0.output }, [RESIDUALS], "the residuals are named; optional outputs did not fire")
        // The other stream is the main output's: it names none.
        let fit = try XCTUnwrap(sent.first { $0.output == nil }, "the main output's stream")
        XCTAssertEqual(fit.label, FIT)
        XCTAssertEqual(fit.isSequence, false, "the fit is declared a single value")
        // The empty stream is a whole stream: STREAM_END promising no chunks.
        let fitFrames = sender.snapshot().filter { $0.streamId == fit.streamId }
        XCTAssertEqual(fitFrames.map { $0.frameType }, [.streamStart, .streamEnd], "STREAM_START and STREAM_END only")
        XCTAssertEqual(fitFrames.last?.chunkCount, 0)
        // Every stream that was opened was closed.
        XCTAssertEqual(sender.snapshot().filter { $0.frameType == .streamEnd }.count, 2)

        // A required SEQUENCE output nobody wrote to is an empty sequence.
        (outputs, sender) = try recordedOutputs(cap.urn, regressManifest)
        try dispatchOp(op: AnyOp(SilentOp()), input: emptyInput(), outputs: outputs, peer: NoPeerInvoker(), network: fullNetwork())
        sent = starts(sender)
        XCTAssertEqual(sent.count, 2, "\(sent)")
        XCTAssertEqual(sent.first { $0.output == RESIDUALS }?.isSequence, true, "the residuals are declared a sequence")

        // A failed handler: only what it wrote itself, and that left open — the
        // request ends with ERR, not with outputs made up for it.
        (outputs, sender) = try recordedOutputs(cap.urn, regressManifest)
        XCTAssertThrowsError(try dispatchOp(op: AnyOp(ResidualsOnlyOp(fail: true)), input: emptyInput(), outputs: outputs, peer: NoPeerInvoker(), network: fullNetwork()))
        sent = starts(sender)
        XCTAssertEqual(sent.map { $0.output }, [RESIDUALS], "\(sent)")
        XCTAssertFalse(sender.snapshot().contains { $0.frameType == .streamEnd })

        // A cap whose `out=` is void has no output: nothing is opened for it.
        (outputs, sender) = try recordedOutputs("cap:in=\"media:enc=utf-8\";sink;out=media:void", nil)
        try dispatchOp(op: AnyOp(SilentOp()), input: emptyInput(), outputs: outputs, peer: NoPeerInvoker(), network: fullNetwork())
        XCTAssertTrue(sender.snapshot().isEmpty)

        // The main output's label follows the cap's effect, and is not its
        // name: a cap that passes its input through labels the stream with the
        // input's type and names no output.
        let pass = "cap:effect=none;in=\"media:enc=utf-8;line\";out=\"media:enc=utf-8\";pass"
        (outputs, sender) = try recordedOutputs(pass, nil)
        try dispatchOp(op: AnyOp(SilentOp()), input: emptyInput(), outputs: outputs, peer: NoPeerInvoker(), network: fullNetwork())
        sent = starts(sender)
        XCTAssertEqual(sent.count, 1)
        XCTAssertNil(sent.first?.output, "the main output's stream names no output")
        XCTAssertEqual(sent.first?.label, try deriveResponseMedia(capUrn: pass))
        XCTAssertNotEqual(sent.first?.label, "media:enc=utf-8", "the label is the input's type")

        // A cap served without a definition answers on the one output its URN states.
        (outputs, sender) = try recordedOutputs("cap:in=\"media:enc=utf-8\";count;out=\"media:integer\"", nil)
        try dispatchOp(op: AnyOp(SilentOp()), input: emptyInput(), outputs: outputs, peer: NoPeerInvoker(), network: fullNetwork())
        sent = starts(sender)
        XCTAssertEqual(sent.count, 1)
        XCTAssertNil(sent.first?.output)
        XCTAssertEqual(sent.first?.label, "media:integer")

        // A cap of one text input and the one output `declare` makes.
        func oneOutput(_ urn: String, _ name: String, _ declare: (String) -> CapOutput) throws -> (CapDefinition, Manifest) {
            let out = try CSCapUrn.fromString(urn).getOutSpec()
            let cap = CapDefinition(
                urn: urn, title: name, aliases: [name],
                args: [CapArg(mediaUrn: "media:enc=utf-8", name: "input", required: true, sources: [.stdin("media:enc=utf-8")])],
                outputs: [declare(out)]
            )
            return (cap, manifest([cap]))
        }
        // A main output declared a sequence, that nobody wrote to, is an empty sequence.
        let (listing, listingManifest) = try oneOutput("cap:in=\"media:enc=utf-8\";list;out=\"media:enc=utf-8;line\"", "list") {
            CapOutput(mediaUrn: $0, name: "made", outputDescription: "What it makes", isSequence: true)
        }
        (outputs, sender) = try recordedOutputs(listing.urn, listingManifest)
        try dispatchOp(op: AnyOp(SilentOp()), input: emptyInput(), outputs: outputs, peer: NoPeerInvoker(), network: fullNetwork())
        sent = starts(sender)
        XCTAssertEqual(sent.count, 1, "\(sent)")
        XCTAssertNil(sent.first?.output)
        XCTAssertEqual(sent.first?.isSequence, true)
        // A main output its definition declares optional is not sent when
        // nobody wrote to it.
        let (maybe, maybeManifest) = try oneOutput("cap:in=\"media:enc=utf-8\";maybe;out=\"media:integer\"", "maybe") {
            CapOutput(mediaUrn: $0, name: "made", outputDescription: "What it makes", optional: true)
        }
        (outputs, sender) = try recordedOutputs(maybe.urn, maybeManifest)
        try dispatchOp(op: AnyOp(SilentOp()), input: emptyInput(), outputs: outputs, peer: NoPeerInvoker(), network: fullNetwork())
        XCTAssertTrue(sender.snapshot().isEmpty)

        // A request made from a bare stream has an output nothing is known of:
        // nothing is sent for it unless the handler writes.
        let bareSender = RecordingFrameSender()
        let bare = Bifaci.OutputStream(sender: bareSender, streamId: "bare", mediaUrn: "media:",
                                       requestId: .newUUID(), routingId: nil, maxChunk: DEFAULT_MAX_CHUNK)
        try dispatchOp(op: AnyOp(SilentOp()), input: emptyInput(), outputs: .undeclared(bare), peer: NoPeerInvoker(), network: fullNetwork())
        XCTAssertTrue(bareSender.snapshot().isEmpty)
    }

    // TEST12721: a request stream names no output: the argument of a peer call
    // is identified by its media URN alone. (That one which does name an output
    // is refused where it is read is TEST12731.)
    func test12721_aRequestStreamNamesNoOutput() throws {
        let sender = RecordingFrameSender()
        let call = PeerCall(sender: sender, requestId: .newUUID(), maxChunk: DEFAULT_MAX_CHUNK, responseRx: AnyIterator { nil })
        let arg = call.arg(mediaUrn: "media:enc=utf-8;prompt")
        XCTAssertNil(arg.outputUrn)
        try arg.start(isSequence: false)
        let sent = starts(sender)
        XCTAssertEqual(sent.count, 1)
        XCTAssertNil(sent.first?.output, "an argument stream does not carry key 21")
        XCTAssertEqual(sent.first?.label, "media:enc=utf-8;prompt")
    }

    // TEST12731: a request stream names no output: an argument is identified
    // by its media URN alone. A request stream that does name one is refused
    // where it is read — the request ends with a protocol error, and nothing
    // of the stream is read as an argument.
    func test12731_aRequestStreamThatNamesAnOutputIsRefused() throws {
        let rid = MessageId.newUUID()
        func feed(_ named: String?) -> InputPackage {
            var start = Frame.streamStart(reqId: rid, streamId: "arg0", mediaUrn: "media:enc=utf-8")
            if let named { start = start.forOutput(named) }
            return demuxMultiStream(frameIterator: iterate([
                start,
                valueChunk(rid, "arg0", 0, .byteString([0x78])),
                Frame.streamEnd(reqId: rid, streamId: "arg0", chunkCount: 1),
                Frame.end(id: rid),
            ]))
        }

        // An argument, as every request stream is.
        let plain = feed(nil).makeIterator()
        let stream = try XCTUnwrap(plain.next()).get().makeIterator()
        XCTAssertNoThrow(try XCTUnwrap(stream.next()).get())

        // The same stream naming an output: a response stream where an
        // argument belongs.
        let named = feed("media:enc=utf-8;kept").makeIterator()
        guard case .failure(.protocolError(let message))? = named.next() else {
            return XCTFail("expected a protocol error")
        }
        XCTAssertTrue(message.contains("names an output") && message.contains("media:enc=utf-8;kept"), message)
        XCTAssertNil(named.next(), "nothing of the request is read as an argument")
    }

    // TEST12722: a command line has one standard output, and it carries the
    // cap's main output: the stream that names no output. A stream that names
    // one is another output — recognised by naming it, not by what it carries,
    // which may be the same type — and its data is not printed.
    func test12722_standardOutputCarriesTheMainOutput() throws {
        let rid = MessageId.newUUID()
        let main = Frame.streamStart(reqId: rid, streamId: "s1", mediaUrn: "media:enc=utf-8", isSequence: false)
        let other = Frame.streamStart(reqId: rid, streamId: "s2", mediaUrn: "media:enc=utf-8", isSequence: false)
            .forOutput("media:enc=utf-8;dropped")
        let sender = CliFrameSender.withoutNdjson()
        XCTAssertFalse(sender.isUnprintedStart(main))
        XCTAssertTrue(sender.isUnprintedStart(other))

        try sender.send(main)
        try sender.send(other)
        XCTAssertEqual(sender.unprinted, ["s2"])
        // A chunk of an unprinted stream is consumed without being decoded or
        // printed: this one is not even CBOR, and is accepted.
        let junk = Data([0xff])
        let unprintedJunk = Frame.chunk(reqId: rid, streamId: "s2", seq: 0, payload: junk, chunkIndex: 0, checksum: Frame.computeChecksum(junk))
        XCTAssertNoThrow(try sender.send(unprintedJunk), "an unprinted stream's chunk is skipped")
        // The same bytes on the printed stream are read, and refused.
        let printedJunk = Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: junk, chunkIndex: 0, checksum: Frame.computeChecksum(junk))
        XCTAssertThrowsError(try sender.send(printedJunk))
    }

    // TEST12730: a peer call's response has one stream per output the callee
    // answers on. The stream that names no output is the callee's main output:
    // its items are the response's data. A stream that names an output yields
    // items tagged with it, and they are not part of the data a caller
    // collects. The response ends at the request's END, not at the first
    // stream's end, and each stream is credited by name, since a grant that
    // names no stream reaches a callee with several only by guessing.
    func test12730_aPeerResponseHasAStreamPerOutput() throws {
        let rid = MessageId.newUUID()
        let rest = "media:enc=utf-8;split-rest"
        func text(_ t: String) -> CBOR { .byteString(Array(t.utf8)) }
        func start(_ stream: String, _ sequence: Bool) -> Frame {
            Frame.streamStart(reqId: rid, streamId: stream, mediaUrn: "media:enc=utf-8", isSequence: sequence)
        }
        func frames() -> [Frame] {
            [
                // The other output starts first, ends first, and carries the
                // same type as the main one.
                start("rest", false).forOutput(rest),
                valueChunk(rid, "rest", 0, text("R1")),
                start("head", false),
                valueChunk(rid, "head", 0, text("H1")),
                valueChunk(rid, "rest", 1, text("R2")),
                Frame.streamEnd(reqId: rid, streamId: "rest", chunkCount: 2),
                valueChunk(rid, "head", 1, text("H2")),
                Frame.streamEnd(reqId: rid, streamId: "head", chunkCount: 2),
                Frame.endOk(id: rid),
            ]
        }

        // Item by item: which output each belongs to, in arrival order.
        let response = demuxPeerResponse(responseRx: iterate(frames()))
        var seen: [String] = []
        while let item = response.recv() {
            switch item {
            case .data(.success(.byteString(let bytes)), _):
                seen.append("main:" + String(decoding: bytes, as: UTF8.self))
            case .output(let output, .success(.byteString(let bytes)), _):
                seen.append(output + ":" + String(decoding: bytes, as: UTF8.self))
            default:
                XCTFail("unexpected item \(item)")
            }
        }
        XCTAssertEqual(seen, ["\(rest):R1", "main:H1", "\(rest):R2", "main:H2"], "everything up to END, each item under its own output")

        // A caller that collects the cap's answer gets the main output only.
        XCTAssertEqual(try demuxPeerResponse(responseRx: iterate(frames())).collectBytes(), Data("H1H2".utf8))

        // Each stream is credited by name as its items are consumed.
        let creditSender = RecordingFrameSender()
        let credited = demuxPeerResponse(responseRx: iterate(frames()),
                                         grants: PeerGrantSource(sender: creditSender, rid: rid, initialCredit: 2))
        while credited.recv() != nil {}
        let grants = creditSender.snapshot().filter { $0.frameType == .credit }
        XCTAssertTrue(grants.allSatisfy { $0.streamId != nil }, "every grant names its stream")
        func granted(_ stream: String) -> UInt64 { grants.filter { $0.streamId == stream }.compactMap { $0.credit }.reduce(0, +) }
        XCTAssertGreaterThanOrEqual(granted("rest"), 1)
        XCTAssertGreaterThanOrEqual(granted("head"), 1)

        // A chunk for a stream that was never started is not data of any
        // output, and the response ends there: what follows it is not read.
        let stray = demuxPeerResponse(responseRx: iterate([
            valueChunk(rid, "ghost", 0, text("?")),
            start("head", false),
            valueChunk(rid, "head", 0, text("H1")),
            Frame.endOk(id: rid),
        ]))
        guard case .data(.failure(.protocolError(let strayMessage)), _)? = stray.recv() else {
            return XCTFail("expected a protocol error")
        }
        XCTAssertTrue(strayMessage.contains("ghost"), strayMessage)
        XCTAssertNil(stray.recv())
        // So does a second STREAM_START for a stream: which of the two the
        // chunks after it belong to is not something to guess.
        let twice = demuxPeerResponse(responseRx: iterate([
            start("head", false),
            valueChunk(rid, "head", 0, text("H1")),
            start("head", false).forOutput(rest),
            valueChunk(rid, "head", 1, text("H2")),
            Frame.endOk(id: rid),
        ]))
        guard case .data(.success, _)? = twice.recv() else { return XCTFail("the first item") }
        guard case .data(.failure(.protocolError(let twiceMessage)), _)? = twice.recv() else {
            return XCTFail("expected a protocol error")
        }
        XCTAssertTrue(twiceMessage.contains("a second STREAM_START for stream 'head'"), twiceMessage)
        XCTAssertNil(twice.recv())

        // What goes wrong on another output's stream is an error of the
        // response: it is tagged with its output, and a collector does not
        // pass over it.
        func broken() -> [Frame] {
            var damaged = valueChunk(rid, "rest", 0, text("R1"))
            damaged.checksum = damaged.checksum.map { $0 &+ 1 }
            return [
                start("rest", false).forOutput(rest),
                start("head", false),
                valueChunk(rid, "head", 0, text("H1")),
                damaged,
                Frame.streamEnd(reqId: rid, streamId: "rest", chunkCount: 1),
                Frame.streamEnd(reqId: rid, streamId: "head", chunkCount: 1),
                Frame.endOk(id: rid),
            ]
        }
        let failing = demuxPeerResponse(responseRx: iterate(broken()))
        var tagged: [String] = []
        while let item = failing.recv() {
            switch item {
            case .output(let output, .failure, _): tagged.append(output)
            case .data(.failure(let error), _): XCTFail("an error of the main output: \(error)")
            default: break
            }
        }
        XCTAssertEqual(tagged, [rest])
        func mismatch(_ body: () throws -> Void) {
            XCTAssertThrowsError(try body()) { error in
                guard case StreamError.protocolError(let message) = error else { return XCTFail("\(error)") }
                XCTAssertTrue(message.contains("Checksum mismatch"), message)
            }
        }
        mismatch { _ = try demuxPeerResponse(responseRx: iterate(broken())).collectBytes() }
        mismatch { _ = try demuxPeerResponse(responseRx: iterate(broken())).collectValue() }
        let forwardTo = Bifaci.OutputStream(sender: RecordingFrameSender(), streamId: "fwd", mediaUrn: "media:integer",
                                            requestId: .newUUID(), routingId: nil, maxChunk: DEFAULT_MAX_CHUNK)
        mismatch { _ = try demuxPeerResponse(responseRx: iterate(broken())).collectBytesForwarding(output: forwardTo, progressBase: 0, progressWeight: 1) }

        // A sequence stream of another output that the request's END cuts
        // inside an item ends with that error, under its output.
        let whole = Data(CBOR.utf8String("a long enough item").encode())
        let half = whole.prefix(whole.count / 2)
        let cut = demuxPeerResponse(responseRx: iterate([
            start("rows", true).forOutput(rest),
            Frame.chunk(reqId: rid, streamId: "rows", seq: 0, payload: Data(half), chunkIndex: 0, checksum: Frame.computeChecksum(Data(half))),
            Frame.endOk(id: rid),
        ]))
        guard case .output(let output, .failure(.decode(let message)), _)? = cut.recv() else {
            return XCTFail("expected the unfinished item's error, under its output")
        }
        XCTAssertEqual(output, rest)
        XCTAssertTrue(message.contains("ended mid-item"), message)
        XCTAssertNil(cut.recv())
    }
}
