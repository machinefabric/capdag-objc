/// Live-feed transport-resolution parity tests (13.2 §Reference Media, live
/// family): selector parsing, the synthetic provider, capture-edge overrun
/// accounting, stop conditions, and `LiveFeedContext` resolution through the
/// demux. Mirrors the same-numbered tests in
/// capdag/src/bifaci/cartridge_runtime.rs (TEST8128–TEST8134) and their
/// Python mirrors.

import XCTest
import Foundation
@preconcurrency import SwiftCBOR
import CapDAG
@testable import Bifaci

/// A manifest whose test cap consumes a live feed: the arg is declared
/// with the SYNTHETIC reference URN, is_sequence (a feed is a sequence
/// of items), and a stdin source carrying the CONTENT urn — the exact
/// file-path reference shape, unbounded.
private let LIVE_FEED_MANIFEST = #"""
{"name":"FeedCartridge","version":"1.0.0","channel":"release","registry_url":null,"description":"Live feed test cartridge","cap_groups":[{"name":"default","caps":[{"urn":"cap:effect=none","title":"Identity","aliases":["identity"]},{"urn":"cap:drain;in=\"media:feed-frames\";out=\"media:fmt=json;record\"","title":"Drain","aliases":["drain"],"args":[{"media_urn":"media:live;synthetic","required":true,"is_sequence":true,"sources":[{"stdin":"media:feed-frames"}]}]}]}]}
"""#

private let FEED_CAP_URN = #"cap:drain;in="media:feed-frames";out="media:fmt=json;record""#

@available(macOS 10.15.4, iOS 13.4, *)
final class LiveFeedTests: XCTestCase {

    // MARK: - Helpers

    // Build a resolution context over the feed manifest. `argIsSequence`
    // false flips the arg's declared `is_sequence` to exercise the contract
    // violation.
    private func makeContext(
        argIsSequence: Bool = true,
        capUrn: String = FEED_CAP_URN
    ) throws -> (ctx: LiveFeedContext, providers: LiveFeedProviders, handles: LiveFeedHandles) {
        let json = argIsSequence
            ? LIVE_FEED_MANIFEST
            : LIVE_FEED_MANIFEST.replacingOccurrences(of: "\"is_sequence\":true", with: "\"is_sequence\":false")
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(json.utf8))
        let providers = LiveFeedProviders()
        let handles = LiveFeedHandles()
        let ctx = try LiveFeedContext(
            capUrn: capUrn,
            manifest: manifest,
            providers: providers,
            handles: handles
        )
        return (ctx, providers, handles)
    }

    // Feed a live-feed reference through the demux: STREAM_START with the
    // reference URN, one CHUNK carrying the selector JSON, STREAM_END, END.
    private func demuxLiveReference(ctx: LiveFeedContext, selector: String) -> InputPackage {
        let rid = MessageId.newUUID()
        let payload = Data(CBOR.utf8String(selector).encode())
        let frames: [Frame] = [
            Frame.streamStart(reqId: rid, streamId: "ref", mediaUrn: MEDIA_LIVE_SYNTHETIC),
            Frame.chunk(
                reqId: rid, streamId: "ref", seq: 0,
                payload: payload, chunkIndex: 0,
                checksum: Frame.computeChecksum(payload)
            ),
            Frame.streamEnd(reqId: rid, streamId: "ref", chunkCount: 1),
            Frame.end(id: rid),
        ]
        var index = 0
        let iterator = AnyIterator<Frame> {
            guard index < frames.count else { return nil }
            let frame = frames[index]
            index += 1
            return frame
        }
        return demuxMultiStream(frameIterator: iterator, liveFeedCtx: ctx)
    }

    // A meta field read as an unsigned integer; nil when absent or another
    // CBOR type (which the callers assert against).
    private func unsignedMeta(_ meta: StreamMeta, _ key: String) -> UInt64? {
        guard case .unsignedInt(let value)? = meta[key] else { return nil }
        return value
    }

    // MARK: - Tests

    // TEST8128: a live-feed reference resolves through the demux exactly like
    // a file path — the handler receives an UNBOUNDED SEQUENCE InputStream
    // labeled with the arg's stdin CONTENT urn, delivering the captured items
    // with seq/pts_us/capture_ts_us metadata, and the op is none the wiser.
    func test8128_liveFeedReferenceResolvesToUnboundedContentStream() throws {
        let (ctx, _, handles) = try makeContext()
        let package = demuxLiveReference(
            ctx: ctx,
            selector: #"{"params":{"items":5,"interval_ms":1,"item_bytes":4}}"#
        )
        guard let first = package.nextStream() else {
            return XCTFail("the resolved feed stream must be delivered")
        }
        let stream = try first.get()
        XCTAssertEqual(stream.mediaUrn, "media:feed-frames", "labeled with the CONTENT urn")
        XCTAssertTrue(stream.isUnbounded, "a live feed makes no length promise (L16)")
        XCTAssertEqual(
            stream.streamMeta?["feed"], CBOR.utf8String("synthetic"),
            "STREAM_START meta carries the provider's format actuals"
        )

        var seqs: [UInt64] = []
        for itemResult in stream {
            let (value, meta) = try itemResult.get()
            guard case .byteString(let bytes) = value else {
                return XCTFail("a live item is raw payload bytes, got \(value)")
            }
            XCTAssertEqual(bytes.count, 4, "the selector's item_bytes is honored")
            let itemMeta = try XCTUnwrap(meta, "every live item carries metadata")
            seqs.append(try XCTUnwrap(unsignedMeta(itemMeta, "seq"), "item must carry integer seq"))
            XCTAssertNotNil(itemMeta["pts_us"], "item carries pts_us")
            XCTAssertNotNil(itemMeta["capture_ts_us"], "item carries capture_ts_us")
        }
        XCTAssertEqual(seqs, [0, 1, 2, 3, 4], "all items, in capture order")
        XCTAssertEqual(handles.count, 1, "the open feed registered its handle")

        // The manifest lookup is canonical-to-canonical: the same cap spelled
        // with its tags in another order resolves the same arg. (Swift
        // manifests carry the declared surface spelling, so this is the seam
        // where a string compare would silently fail to find the arg.)
        let reordered = try makeContext(
            capUrn: #"cap:in="media:feed-frames";drain;out="media:fmt=json;record""#
        )
        let reorderedStream = try reordered.ctx.resolve(
            referenceUrn: MEDIA_LIVE_SYNTHETIC,
            selectorBytes: Data(#"{"stop":{"max_items":1},"params":{"items":1,"interval_ms":0}}"#.utf8)
        )
        XCTAssertEqual(
            reorderedStream.mediaUrn, "media:feed-frames",
            "a differently-spelled cap URN finds the same declared arg"
        )
        reordered.handles.closeAll()
    }

    // TEST8129: overrun under drop-oldest — a flooding feed with a lagging
    // consumer loses items ONLY at the capture edge, counts every loss, and
    // stamps the next delivered item with a gap marker so the discontinuity
    // is visible in-band. delivered + dropped always equals captured.
    func test8129_overrunDropOldestCountsAndMarksGaps() throws {
        let (ctx, providers, _) = try makeContext()
        let package = demuxLiveReference(
            ctx: ctx,
            selector: #"{"params":{"items":50,"interval_ms":0,"item_bytes":4,"ring":2}}"#
        )
        let stream = try XCTUnwrap(package.nextStream()).get()
        // Lag: let the producer flood to completion before consuming — the
        // bounded delivery queue + tiny ring force capture-edge drops.
        Thread.sleep(forTimeInterval: 0.5)

        var delivered: UInt64 = 0
        var droppedViaGaps: UInt64 = 0
        var lastSeq: UInt64? = nil
        for itemResult in stream {
            let (_, meta) = try itemResult.get()  // drop-oldest never fails the stream
            let itemMeta = try XCTUnwrap(meta)
            let seq = try XCTUnwrap(unsignedMeta(itemMeta, "seq"), "item must carry integer seq")
            if let previous = lastSeq {
                XCTAssertGreaterThan(seq, previous, "seq strictly increases across gaps")
            }
            if let gap = itemMeta["gap"] {
                guard case .map(let fields) = gap,
                      case .unsignedInt(let dropped)? = fields[.utf8String("dropped")] else {
                    return XCTFail("gap carries an integer dropped count, got \(gap)")
                }
                XCTAssertGreaterThan(dropped, 0, "a gap marker means real loss")
                droppedViaGaps += dropped
            }
            delivered += 1
            lastSeq = seq
        }
        XCTAssertLessThan(delivered, 50, "a lagging consumer cannot receive everything")
        XCTAssertGreaterThan(droppedViaGaps, 0, "the loss is visible in-band")
        XCTAssertEqual(
            delivered + droppedViaGaps, 50,
            "every captured item is either delivered or counted as dropped — nothing silent"
        )
        XCTAssertEqual(
            providers.overrunsTotal, droppedViaGaps,
            "the runtime-wide overrun counter matches the in-band accounting"
        )
    }

    // TEST8130: on_overrun=fail — a pipeline that declares it needs every
    // frame gets a classified FEED_OVERRUN stream error instead of loss.
    func test8130_overrunFailEndsFeedWithClassifiedError() throws {
        let (ctx, _, _) = try makeContext()
        let package = demuxLiveReference(
            ctx: ctx,
            selector: #"{"on_overrun":"fail","params":{"items":50,"interval_ms":0,"item_bytes":4,"ring":2}}"#
        )
        let stream = try XCTUnwrap(package.nextStream()).get()
        Thread.sleep(forTimeInterval: 0.5)

        var sawOverrunError = false
        for itemResult in stream {
            if case .failure(let error) = itemResult {
                XCTAssertTrue(
                    "\(error)".contains("FEED_OVERRUN"),
                    "the failure names the overrun: \(error)"
                )
                sawOverrunError = true
            }
        }
        XCTAssertTrue(sawOverrunError, "on_overrun=fail must surface the overrun as an error")
    }

    // TEST8131: max_items stop condition — the feed ends itself after
    // exactly N captured items; the stream ends cleanly (a run stops on its
    // own when its input ends, 15.2 §Runs Stop).
    func test8131_maxItemsStopConditionEndsFeed() throws {
        let (ctx, _, _) = try makeContext()
        let package = demuxLiveReference(
            ctx: ctx,
            selector: #"{"stop":{"max_items":3},"params":{"items":1000,"interval_ms":1,"item_bytes":4}}"#
        )
        let stream = try XCTUnwrap(package.nextStream()).get()
        var delivered = 0
        for itemResult in stream {
            _ = try itemResult.get()  // items deliver cleanly
            delivered += 1
        }
        XCTAssertEqual(delivered, 3, "the stop condition bounds the feed exactly")
    }

    // TEST8132: stop = close the tap — closing the feed's handle ends the
    // stream cleanly mid-capture; what was already captured drains, then the
    // stream ends without error (the drain path of a stopped run).
    func test8132_handleCloseStopsFeedAndDrains() throws {
        let (ctx, _, handles) = try makeContext()
        let package = demuxLiveReference(
            ctx: ctx,
            selector: #"{"params":{"items":100000,"interval_ms":2,"item_bytes":4}}"#
        )
        let stream = try XCTUnwrap(package.nextStream()).get()
        let iterator = stream.makeIterator()

        // Consume one live item, then stop.
        let first = try XCTUnwrap(iterator.next(), "live item").get()
        guard case .byteString = first.0 else {
            return XCTFail("a live item is raw payload bytes, got \(first.0)")
        }
        XCTAssertEqual(handles.count, 1)
        handles.all()[0].close()

        // The stream must END (not hang, not error) — drain then done.
        let deadline = Date().addingTimeInterval(5)
        while let item = iterator.next() {
            _ = try item.get()  // drained items are clean
            XCTAssertLessThan(Date(), deadline, "a closed feed must end promptly")
        }
    }

    // TEST8133: a live-feed arg declared is_sequence=false is a contract
    // violation — a feed is an unbounded SEQUENCE — and fails hard at
    // resolution, never delivering a mislabeled stream.
    func test8133_scalarLiveFeedArgRejected() throws {
        let (ctx, _, _) = try makeContext(argIsSequence: false)
        let package = demuxLiveReference(ctx: ctx, selector: "{}")
        guard let result = package.nextStream() else {
            return XCTFail("the failure must be delivered")
        }
        guard case .failure(let error) = result else {
            return XCTFail("a scalar live-feed arg must be rejected")
        }
        XCTAssertTrue("\(error)".contains("is_sequence"), "\(error)")
    }

    // TEST8134: an unparseable selector is a hard error — never a silent
    // all-defaults feed.
    func test8134_invalidSelectorRejected() throws {
        let (ctx, _, _) = try makeContext()
        let package = demuxLiveReference(ctx: ctx, selector: "{not json")
        guard let result = package.nextStream() else {
            return XCTFail("the failure must be delivered")
        }
        guard case .failure(let error) = result else {
            return XCTFail("garbage selectors must be rejected")
        }
        XCTAssertTrue("\(error)".contains("selector"), "\(error)")

        // The same hard-error rule at the parser itself: an empty value is
        // the all-defaults selector, an unknown field is not.
        XCTAssertEqual(try LiveFeedSelector.parse(Data("   ".utf8)).onOverrun, .dropOldest,
                       "an empty selector is all-defaults")
        XCTAssertNil(try LiveFeedSelector.parse(Data()).device)
        XCTAssertThrowsError(try LiveFeedSelector.parse(Data(#"{"devise":"mic"}"#.utf8)),
                             "an unknown field is a hard error, never silently ignored")
        XCTAssertEqual(
            try LiveFeedSelector.parse(Data(#"{"on_overrun":"fail","stop":{"max_items":7}}"#.utf8)).stop.maxItems,
            7
        )
    }
}
