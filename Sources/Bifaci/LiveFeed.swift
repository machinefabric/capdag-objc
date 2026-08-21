//
//  LiveFeed.swift
//  Bifaci
//
//  Live-feed transport resolution (13.2 §Reference Media, live family).
//
//  A live feed is an input that arrives BY REFERENCE: the wire value is a
//  small selector record, and the runtime — never the op — resolves it by
//  opening a capture device through a registered `LiveFeedProvider` and
//  delivering an UNBOUNDED SEQUENCE stream of items labeled with the arg's
//  stdin content URN. The op is transport-blind: it consumes items exactly
//  as it would consume a file's bytes, and cannot tell the difference.
//
//  Backpressure is end-to-end and every stage has a defined full-state
//  behavior (12.5 §Overrun): wire credit stalls the op's output → the op
//  stops consuming input → the BOUNDED delivery queue fills → the feeder
//  stops draining the capture ring → the ring fills → the capture edge
//  applies the feed's declared overrun policy. Loss can occur only at the
//  capture edge, only under the declared policy, and always counted — with
//  an in-band `gap` marker on the next delivered item so downstream sees
//  the discontinuity.
//
//  The runtime ships one built-in provider, `SyntheticFeedProvider`
//  (`media:live;synthetic`): a deterministic clock source used by the
//  shared test range and available everywhere as a fixture feed. Hardware
//  providers (microphone, webcam) are registered by capture-capable
//  cartridges; on sandboxed platforms the host captures instead and this
//  seam is not involved.
//
//  Mirrors capdag/src/bifaci/live_feed.rs (and the LiveFeedContext part of
//  cartridge_runtime.rs) one-to-one.
//

import Foundation
import CapDAG
@preconcurrency import SwiftCBOR

/// Reference-family pattern: any media URN carrying the `live` marker tag
/// is a live-feed reference (the live analog of `media:file-path`).
public let MEDIA_LIVE_FEED: String = "media:live"

/// The built-in deterministic test feed's reference URN.
public let MEDIA_LIVE_SYNTHETIC: String = "media:live;synthetic"

/// Ring capacity when the selector's params don't override it (`ring`).
private let DEFAULT_RING_CAP: Int = 64

/// Bounded delivery-queue capacity — the op-side half of the backpressure
/// chain. Small on purpose: the ring is the elastic stage.
private let DELIVERY_QUEUE_CAP: Int = 8

/// How long the feeder waits between re-checks while the ring is empty or
/// the delivery queue is full — the granularity at which a close or a
/// `duration_ms` deadline takes effect.
private let FEEDER_POLL_INTERVAL: TimeInterval = 0.05

// MARK: - Selector

/// How the capture edge behaves when the ring is full because the consumer
/// lags reality (12.5 §Overrun).
public enum OverrunPolicy: String, Sendable {
    /// Evict the oldest ring entry, count the overrun, stamp the next
    /// delivered item with a `gap` marker. Real-time consumers prefer
    /// fresh data over complete data. The default.
    case dropOldest = "drop-oldest"
    /// End the feed with a classified `FEED_OVERRUN` error. For pipelines
    /// that need every item and say so explicitly.
    case fail = "fail"
}

/// Stop conditions for a feed (absent = "until stopped").
public struct LiveFeedStop: Sendable {
    /// End the feed after this much capture time.
    public var durationMs: UInt64?
    /// End the feed after this many CAPTURED items (dropped items count —
    /// they were captured).
    public var maxItems: UInt64?

    public init(durationMs: UInt64? = nil, maxItems: UInt64? = nil) {
        self.durationMs = durationMs
        self.maxItems = maxItems
    }
}

/// The selector record carried as a live-feed reference arg's value (JSON).
/// An empty value is the all-defaults selector.
public struct LiveFeedSelector: Sendable {
    /// Provider-defined device selector. A provider with exactly one
    /// device may default this.
    public var device: String?
    /// Provider-defined capture parameters (sample rate, resolution, …).
    public var params: [String: JSONValue]
    public var stop: LiveFeedStop
    public var onOverrun: OverrunPolicy

    public init(
        device: String? = nil,
        params: [String: JSONValue] = [:],
        stop: LiveFeedStop = LiveFeedStop(),
        onOverrun: OverrunPolicy = .dropOldest
    ) {
        self.device = device
        self.params = params
        self.stop = stop
        self.onOverrun = onOverrun
    }

    /// A `params` entry read as an unsigned integer, or nil when absent or
    /// not a non-negative integer.
    public func paramUInt(_ key: String) -> UInt64? {
        guard case .integer(let value)? = params[key], value >= 0 else { return nil }
        return UInt64(value)
    }

    /// Parse a selector from the reference value bytes. Empty (or
    /// whitespace-only) bytes are the all-defaults selector; anything else
    /// must be a valid selector record — an unparseable selector is a hard
    /// error, never a silent default. Unknown fields are rejected: a
    /// misspelled knob must not be silently ignored.
    public static func parse(_ bytes: Data) throws -> LiveFeedSelector {
        let text = String(decoding: bytes, as: UTF8.self)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return LiveFeedSelector()
        }
        func reject(_ why: String) -> CartridgeRuntimeError {
            CartridgeRuntimeError.handlerError(
                "live-feed selector is not a valid selector record: \(why) (value: \(trimmed))"
            )
        }
        let root: JSONValue
        do {
            root = try JSONDecoder().decode(JSONValue.self, from: Data(trimmed.utf8))
        } catch {
            throw reject("\(error)")
        }
        guard case .object(let fields) = root else {
            throw reject("a selector must be a JSON object")
        }

        var selector = LiveFeedSelector()
        for (key, value) in fields {
            switch key {
            case "device":
                switch value {
                case .string(let device): selector.device = device
                case .null: selector.device = nil
                default: throw reject("`device` must be a string")
                }
            case "params":
                guard case .object(let params) = value else {
                    throw reject("`params` must be an object")
                }
                selector.params = params
            case "stop":
                guard case .object(let stopFields) = value else {
                    throw reject("`stop` must be an object")
                }
                for (stopKey, stopValue) in stopFields {
                    switch stopKey {
                    case "duration_ms":
                        selector.stop.durationMs = try unsignedField(stopValue, "stop.duration_ms", reject)
                    case "max_items":
                        selector.stop.maxItems = try unsignedField(stopValue, "stop.max_items", reject)
                    default:
                        throw reject("unknown field `stop.\(stopKey)`")
                    }
                }
            case "on_overrun":
                guard case .string(let raw) = value, let policy = OverrunPolicy(rawValue: raw) else {
                    throw reject("`on_overrun` must be one of \"drop-oldest\", \"fail\"")
                }
                selector.onOverrun = policy
            default:
                throw reject("unknown field `\(key)`")
            }
        }
        return selector
    }

    private static func unsignedField(
        _ value: JSONValue,
        _ path: String,
        _ reject: (String) -> CartridgeRuntimeError
    ) throws -> UInt64? {
        switch value {
        case .null:
            return nil
        case .integer(let raw) where raw >= 0:
            return UInt64(raw)
        default:
            throw reject("`\(path)` must be a non-negative integer")
        }
    }
}

// MARK: - Items and ring

/// One captured item, as a provider hands it to the sink. `seq` and gap
/// accounting are assigned by the sink/feeder — providers supply only the
/// payload and its timestamps.
public struct LiveFeedItem: Sendable {
    /// Raw item bytes (one audio buffer, one video frame, …).
    public let payload: [UInt8]
    /// Presentation timestamp, microseconds from capture start.
    public let ptsUs: UInt64
    /// Wall-clock capture time, Unix microseconds.
    public let captureTsUs: UInt64

    public init(payload: [UInt8], ptsUs: UInt64, captureTsUs: UInt64) {
        self.payload = payload
        self.ptsUs = ptsUs
        self.captureTsUs = captureTsUs
    }
}

/// A captured item annotated by the sink at push time.
private struct RingItem {
    let item: LiveFeedItem
    /// Capture-order index, monotonic from 0, counting dropped items too —
    /// a gap in delivered `seq` is real (12.4 §Live Feeds).
    let seq: UInt64
}

/// What the feeder found when it asked the ring for the next item.
private enum FeedTake {
    case item(LiveFeedItem, seq: UInt64, droppedSinceDelivery: UInt64)
    /// `on_overrun = fail` fired: the loss IS the outcome, surface it as
    /// the stream's terminal error.
    case failed(String)
    /// Drained and finished (producer done, or the tap was closed).
    case done
}

/// Runtime-wide overrun total (rides heartbeat meta as `overruns_total`).
public final class OverrunCounter: @unchecked Sendable {
    private var count: UInt64 = 0
    private let lock = NSLock()

    public init() {}

    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    public var total: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

/// The shared state of one open feed: the capture ring plus its accounting.
/// Every field is guarded by `condition`, which both the capture edge and
/// the feeder wait on.
private final class FeedShared: @unchecked Sendable {
    private let condition = NSCondition()
    private var ring: [RingItem] = []
    /// Set when the producer finished (stop condition, device closed) —
    /// the feeder drains the ring then ends the stream.
    private var producerDone = false
    /// Set by `on_overrun = fail` with the failure message; the feeder
    /// surfaces it as the stream's terminal error.
    private var failure: String?
    /// Feed closed (stop, abort, or delivery side gone): providers observe
    /// this via `push()` returning false and must stop capturing.
    private var closed = false
    /// Items captured so far (delivered + dropped) — the `seq` source and
    /// the `max_items` stop-condition counter.
    private var captured: UInt64 = 0
    /// Items dropped at the capture edge since the last delivered item —
    /// reset to zero when the feeder stamps a `gap` marker.
    private var droppedSinceDelivery: UInt64 = 0
    /// This feed's total overruns.
    private var overrunCount: UInt64 = 0

    let ringCap: Int
    let policy: OverrunPolicy
    private let runtimeOverruns: OverrunCounter

    init(ringCap: Int, policy: OverrunPolicy, runtimeOverruns: OverrunCounter) {
        self.ringCap = ringCap
        self.policy = policy
        self.runtimeOverruns = runtimeOverruns
    }

    var isClosed: Bool {
        condition.lock()
        defer { condition.unlock() }
        return closed
    }

    var overruns: UInt64 {
        condition.lock()
        defer { condition.unlock() }
        return overrunCount
    }

    func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }

    func finishProducer() {
        condition.lock()
        producerDone = true
        condition.broadcast()
        condition.unlock()
    }

    /// Capture-edge push. Returns the seq assigned, or nil when the feed is
    /// closed (including by this push under `on_overrun = fail`).
    func push(_ item: LiveFeedItem) -> UInt64? {
        condition.lock()
        if closed {
            condition.unlock()
            return nil
        }
        let seq = captured
        captured += 1
        if ring.count >= ringCap {
            switch policy {
            case .dropOldest:
                ring.removeFirst()
                overrunCount += 1
                droppedSinceDelivery += 1
                runtimeOverruns.increment()
            case .fail:
                failure = "FEED_OVERRUN: capture ring full at item seq=\(seq) — the consumer's "
                    + "window lagged reality and the feed declared on_overrun=fail"
                closed = true
                condition.broadcast()
                condition.unlock()
                return nil
            }
        }
        ring.append(RingItem(item: item, seq: seq))
        condition.broadcast()
        let stillOpen = !closed
        condition.unlock()
        return stillOpen ? seq : nil
    }

    /// Feeder-side take: the next ring item, the terminal failure, or done.
    /// Waits (bounded, so a close or a deadline takes effect) while the
    /// ring is empty and the producer is still running.
    func take(deadline: Date?) -> FeedTake {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let message = failure {
                failure = nil
                return .failed(message)
            }
            if !ring.isEmpty {
                let entry = ring.removeFirst()
                let dropped = droppedSinceDelivery
                droppedSinceDelivery = 0
                condition.broadcast()
                return .item(entry.item, seq: entry.seq, droppedSinceDelivery: dropped)
            }
            if producerDone || closed {
                return .done
            }
            if let deadline = deadline, Date() >= deadline {
                closed = true
                condition.broadcast()
                return .done
            }
            condition.wait(until: Date().addingTimeInterval(FEEDER_POLL_INTERVAL))
        }
    }
}

// MARK: - Provider-facing handles

/// The provider's write side of a feed. Owned by the provider's capture
/// thread; `push` applies the overrun policy at the capture edge.
public final class LiveFeedSink: @unchecked Sendable {
    private let shared: FeedShared
    private let maxItems: UInt64?

    fileprivate init(shared: FeedShared, maxItems: UInt64?) {
        self.shared = shared
        self.maxItems = maxItems
    }

    /// Push one captured item. Returns `false` when the feed is closed —
    /// the provider must stop capturing and release the device. A full
    /// ring applies the feed's overrun policy (12.5 §Overrun); under
    /// `fail` the feed ends and this returns `false`.
    @discardableResult
    public func push(_ item: LiveFeedItem) -> Bool {
        guard let seq = shared.push(item) else {
            return false
        }
        // max_items counts CAPTURED items; reaching it finishes the
        // producer side (the ring still drains).
        if let maxItems = maxItems, seq + 1 >= maxItems {
            finish()
            return false
        }
        return true
    }

    /// The producer finished on its own (stop condition, device closed).
    /// The feeder drains the remaining ring, then the stream ends.
    public func finish() {
        shared.finishProducer()
    }

    /// Whether the feed has been closed (stop/abort/consumer gone).
    public var isClosed: Bool {
        shared.isClosed
    }
}

/// A handle to one open feed, held by the runtime per request so a stop
/// (a CloseStream frame to the feed-bearing request) can close the tap and
/// let the run drain (15.2 §Runs Stop).
public final class LiveFeedHandle: @unchecked Sendable {
    private let shared: FeedShared
    /// The input stream (bifaci `stream_id`) this feed was resolved for, once
    /// the runtime has bound it — what a CloseStream naming one stream is
    /// matched against. nil for host-opened taps, which are not wire streams.
    public private(set) var streamId: String?

    fileprivate init(shared: FeedShared) {
        self.shared = shared
    }

    /// Bind the handle to the input stream it was resolved for.
    func bind(streamId: String) {
        self.streamId = streamId
    }

    /// Close the tap: the provider's next `push` returns false, the feeder
    /// drains what was already captured, and the stream ends — the drain
    /// path of a stopped run.
    public func close() {
        shared.close()
    }

    /// This feed's overrun total so far.
    public var overruns: UInt64 {
        shared.overruns
    }
}

/// One request's open feed handles — shared between the request's
/// `LiveFeedContext` (which registers each opened feed) and the runtime's
/// per-rid registry (whose stop path closes through the same object).
public final class LiveFeedHandles: @unchecked Sendable {
    private var handles: [LiveFeedHandle] = []
    private let lock = NSLock()

    public init() {}

    func add(_ handle: LiveFeedHandle) {
        lock.lock()
        handles.append(handle)
        lock.unlock()
    }

    /// The handles opened so far, in open order.
    public func all() -> [LiveFeedHandle] {
        lock.lock()
        defer { lock.unlock() }
        return handles
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return handles.count
    }

    /// Close every open tap. The feeds drain and their streams end.
    public func closeAll() {
        for handle in all() {
            handle.close()
        }
    }

    /// Close the taps a CloseStream names: the one bound to `streamId`, or
    /// every tap when `streamId` is nil. Returns how many were closed.
    @discardableResult
    public func close(streamId: String?) -> Int {
        var closed = 0
        for handle in all() where streamId == nil || handle.streamId == streamId {
            handle.close()
            closed += 1
        }
        return closed
    }
}

// MARK: - Providers

/// A live-capture backend. Implementations own a capture thread: `open`
/// starts capture pushing into `sink` and returns the stream-level format
/// actuals (sample rate, resolution, …) for STREAM_START meta. `push`
/// returning false — or `sink.isClosed` — means stop capturing and
/// release the device.
public protocol LiveFeedProvider: Sendable {
    /// Provider name, for errors and logs.
    var name: String { get }
    /// The CONTENT media URN this provider's feed delivers (e.g. the
    /// microphone provider delivers `media:audio-frames;pcm`). Used when a
    /// live reference resolves against a cap's MAIN INPUT (the cap declares
    /// no explicit reference arg): the content urn must conform to the main
    /// input's declared urn, and the delivered stream is labeled with it.
    var contentUrn: String { get }
    /// Open the device described by `selector` and start capturing into
    /// `sink`. A device that cannot be opened is a hard error — never a
    /// silent empty feed.
    func open(selector: LiveFeedSelector, sink: LiveFeedSink) throws -> StreamMeta?
}

/// Registered providers: reference-URN pattern → provider. First
/// registered pattern that ACCEPTS the incoming reference URN wins;
/// registration order is deliberate (a cartridge may register a more
/// specific device provider before the generic family).
public final class LiveFeedProviders: @unchecked Sendable {
    private var entries: [(pattern: CSMediaUrn, provider: any LiveFeedProvider)] = []
    private let lock = NSLock()
    /// Runtime-wide overrun total (heartbeat `overruns_total`).
    fileprivate let overrunCounter = OverrunCounter()

    /// A registry with the built-in synthetic provider pre-registered.
    public init() {
        register(pattern: MEDIA_LIVE_SYNTHETIC, provider: SyntheticFeedProvider())
    }

    /// Register a provider for a reference-URN pattern. The pattern must
    /// itself be a live-feed reference (carry the `live` marker) — a
    /// provider registered off-family would be unreachable, which is a
    /// wiring bug surfaced loudly here.
    public func register(pattern: String, provider: any LiveFeedProvider) {
        guard let patternUrn = try? CSMediaUrn.fromString(pattern) else {
            preconditionFailure("BUG: live-feed provider pattern '\(pattern)' is not a valid media URN")
        }
        guard let family = try? CSMediaUrn.fromString(MEDIA_LIVE_FEED) else {
            preconditionFailure("BUG: MEDIA_LIVE_FEED constant is invalid")
        }
        // family.accepts(patternUrn) == patternUrn.conforms(to: family).
        guard patternUrn.conforms(to: family) else {
            preconditionFailure(
                "BUG: live-feed provider pattern '\(pattern)' is outside the live reference "
                + "family '\(MEDIA_LIVE_FEED)' — it would never be resolved"
            )
        }
        lock.lock()
        entries.append((pattern: patternUrn, provider: provider))
        lock.unlock()
    }

    fileprivate func find(_ reference: CSMediaUrn) -> (any LiveFeedProvider)? {
        lock.lock()
        defer { lock.unlock() }
        // pattern.accepts(reference) == reference.conforms(to: pattern).
        return entries.first { reference.conforms(to: $0.pattern) }?.provider
    }

    /// The CONTENT urn the provider matching `reference` delivers, if a
    /// provider is registered for it. Used by main-input resolution: the
    /// content urn must conform to the consuming arg's declared urn.
    public func contentUrn(for reference: CSMediaUrn) -> String? {
        find(reference)?.contentUrn
    }

    /// Runtime-wide overrun total (rides heartbeat meta).
    public var overrunsTotal: UInt64 {
        overrunCounter.total
    }
}

// MARK: - Opening a feed

/// The consumer end of an open feed. Its deinit is the receiver-drop
/// signal the Rust reference gets from a dropped channel: when the
/// handler releases the `InputStream`, the tap closes and the provider
/// stops capturing.
private final class FeedReceiver {
    let delivery: BlockingQueue<Result<(CBOR, StreamMeta?), StreamError>>
    private let shared: FeedShared

    init(delivery: BlockingQueue<Result<(CBOR, StreamMeta?), StreamError>>, shared: FeedShared) {
        self.delivery = delivery
        self.shared = shared
    }

    deinit {
        // Consumer gone: refuse further delivery and close the tap so the
        // provider stops capturing.
        delivery.finish()
        shared.close()
    }
}

/// Everything `openFeed` returns to the demux: the item iterator the
/// `InputStream` consumes, the stream-level meta for STREAM_START, and the
/// handle the runtime registers for stop.
public struct OpenedFeed {
    public let items: AnyIterator<Result<(CBOR, StreamMeta?), StreamError>>
    public let streamMeta: StreamMeta?
    public let handle: LiveFeedHandle
}

/// Resolve a live-feed reference: find the provider, open the device, and
/// bridge capture → bounded delivery through the ring + feeder thread.
public func openFeed(
    providers: LiveFeedProviders,
    referenceUrn: String,
    selector: LiveFeedSelector
) throws -> OpenedFeed {
    let reference: CSMediaUrn
    do {
        reference = try CSMediaUrn.fromString(referenceUrn)
    } catch {
        throw CartridgeRuntimeError.handlerError(
            "live-feed reference URN '\(referenceUrn)' is not a valid media URN: \(error)"
        )
    }
    guard let provider = providers.find(reference) else {
        throw CartridgeRuntimeError.handlerError(
            "no live-feed provider registered for reference '\(referenceUrn)' — the runtime "
            + "cannot open this feed"
        )
    }

    let ringCap = selector.paramUInt("ring").map { Int(max($0, 1)) } ?? DEFAULT_RING_CAP
    let shared = FeedShared(
        ringCap: ringCap,
        policy: selector.onOverrun,
        runtimeOverruns: providers.overrunCounter
    )

    let sink = LiveFeedSink(shared: shared, maxItems: selector.stop.maxItems)
    let streamMeta = try provider.open(selector: selector, sink: sink)

    let delivery = BlockingQueue<Result<(CBOR, StreamMeta?), StreamError>>(capacity: DELIVERY_QUEUE_CAP)
    let receiver = FeedReceiver(delivery: delivery, shared: shared)

    // The feeder: ring → bounded delivery. Blocking pushes give the real
    // backpressure — when the op lags, the feeder blocks, the ring fills,
    // and the capture edge applies the overrun policy. A `durationMs` stop
    // condition is enforced here (uniformly across providers).
    let deadline = selector.stop.durationMs.map {
        Date().addingTimeInterval(TimeInterval($0) / 1000.0)
    }
    Thread.detachNewThread {
        var lastDeliveredPts: UInt64? = nil
        while true {
            if let deadline = deadline, Date() >= deadline {
                shared.close()
            }
            switch shared.take(deadline: deadline) {
            case .done:
                // Drained + done → the stream ends.
                delivery.finish()
                return
            case .failed(let message):
                // An overrun failure preempts remaining ring items: the
                // feed declared on_overrun=fail, so the loss IS the
                // outcome — surface it as the stream's terminal error.
                _ = delivery.push(.failure(.protocolError(message)))
                delivery.finish()
                return
            case .item(let item, let seq, let dropped):
                var meta: StreamMeta = [:]
                meta["seq"] = .unsignedInt(seq)
                meta["pts_us"] = .unsignedInt(item.ptsUs)
                meta["capture_ts_us"] = .unsignedInt(item.captureTsUs)
                if dropped > 0 {
                    let durationUs = lastDeliveredPts.map { item.ptsUs >= $0 ? item.ptsUs - $0 : 0 } ?? 0
                    meta["gap"] = .map([
                        .utf8String("dropped"): .unsignedInt(dropped),
                        .utf8String("duration_us"): .unsignedInt(durationUs),
                    ])
                }
                lastDeliveredPts = item.ptsUs
                if !delivery.push(.success((.byteString(item.payload), meta))) {
                    // Consumer gone (the handler released the stream):
                    // close the tap so the provider stops capturing.
                    shared.close()
                    return
                }
            }
        }
    }

    // The iterator holds the receiver: when the handler releases the
    // InputStream, `FeedReceiver.deinit` closes the tap.
    let items = AnyIterator<Result<(CBOR, StreamMeta?), StreamError>> {
        receiver.delivery.dequeue()
    }
    return OpenedFeed(items: items, streamMeta: streamMeta, handle: LiveFeedHandle(shared: shared))
}

// MARK: - Synthetic provider

/// The built-in deterministic feed (`media:live;synthetic`): a logical
/// clock emitting `items` payloads of `item_bytes` bytes every
/// `interval_ms` (params, all optional; defaults 10 × 32B × 10ms).
/// `pts_us` is the LOGICAL clock (i × interval), so tests are
/// deterministic; `capture_ts_us` is wall clock. `interval_ms = 0` emits
/// as fast as possible — with a small `ring` and a slow consumer this
/// exercises real overruns without hardware.
/// The content urn the synthetic feed delivers: opaque test frames.
public let MEDIA_FEED_FRAMES: String = "media:feed-frames"

public struct SyntheticFeedProvider: LiveFeedProvider {
    public init() {}

    public var name: String { "synthetic" }

    public var contentUrn: String { MEDIA_FEED_FRAMES }

    public func open(selector: LiveFeedSelector, sink: LiveFeedSink) throws -> StreamMeta? {
        let items = selector.paramUInt("items") ?? 10
        let intervalMs = selector.paramUInt("interval_ms") ?? 10
        let itemBytes = Int(max(selector.paramUInt("item_bytes") ?? 32, 1))

        Thread.detachNewThread {
            let start = UInt64(Date().timeIntervalSince1970 * 1_000_000)
            var i: UInt64 = 0
            while i < items {
                if sink.isClosed {
                    break
                }
                // Deterministic payload: the item index repeated.
                let payload = [UInt8](repeating: UInt8(i % 256), count: itemBytes)
                let pushed = sink.push(LiveFeedItem(
                    payload: payload,
                    ptsUs: i * intervalMs * 1000,
                    captureTsUs: start + i * intervalMs * 1000
                ))
                if !pushed {
                    break
                }
                if intervalMs > 0 {
                    Thread.sleep(forTimeInterval: TimeInterval(intervalMs) / 1000.0)
                }
                i += 1
            }
            sink.finish()
        }

        return [
            "feed": .utf8String("synthetic"),
            "interval_ms": .unsignedInt(intervalMs),
        ]
    }
}

// MARK: - Runtime-side resolution

/// Runtime-side context for LIVE-FEED reference resolution (13.2 §Reference
/// Media, live family) — the live sibling of the file-path transport
/// resolution. An incoming stream whose media URN carries the `live` marker
/// is a reference: the demux accumulates its selector value, opens the feed
/// through the registered providers, and delivers an UNBOUNDED SEQUENCE
/// `InputStream` labeled with the arg's stdin content URN. Opened feeds
/// register their handles so a stop (non-force Cancel on a feed-bearing
/// request) can close the tap and let the run drain (15.2 §Runs Stop).
internal final class LiveFeedContext: @unchecked Sendable {
    /// The CANONICAL rendering of this request's cap URN, so the manifest
    /// lookup compares canonical-to-canonical, independent of the caller's
    /// surface spelling (tag order, quoting).
    private let capUrn: String
    private let manifest: Manifest?
    private let providers: LiveFeedProviders
    /// This request's open feed handles, shared with the runtime's per-rid
    /// registry (the stop path closes through the same object).
    private let handles: LiveFeedHandles

    /// Build the context for one request. The cap URN is stored CANONICAL so
    /// the manifest lookup compares canonical-to-canonical, independent of
    /// the caller's surface spelling (tag order, quoting).
    init(
        capUrn: String,
        manifest: Manifest?,
        providers: LiveFeedProviders,
        handles: LiveFeedHandles
    ) throws {
        let parsedCap: CSCapUrn
        do {
            parsedCap = try CSCapUrn.fromString(capUrn)
        } catch {
            throw CartridgeRuntimeError.handlerError(
                "live-feed context: cap URN '\(capUrn)' does not parse: \(error)"
            )
        }
        self.capUrn = parsedCap.toString()
        self.manifest = manifest
        self.providers = providers
        self.handles = handles
    }

    /// Whether an incoming stream's media URN is a live-feed reference —
    /// delegated to the canonical family predicate `CSMediaUrnIsLiveFeed`.
    /// The URN arrives off the wire, so it is parse-guarded first: an
    /// unparseable URN is simply not a live reference (the demux's own
    /// validation rejects it downstream), never a raised exception.
    func isLiveFeed(_ mediaUrn: String) -> Bool {
        guard let parsed = try? CSMediaUrn.fromString(mediaUrn) else { return false }
        return CSMediaUrnIsLiveFeed(parsed.toString())
    }

    /// The cap's arg declaring this reference — matched by the encapsulated
    /// URN-equivalence predicate, never by string compare.
    private func findArg(_ incoming: CSMediaUrn) -> CapArg? {
        guard let manifest = manifest else { return nil }
        // Canonical-to-canonical: the manifest's declared spelling and the
        // dispatched cap URN may differ in tag order or quoting and still be
        // the same cap.
        guard let capDef = manifest.allCaps().first(where: { candidate in
            guard let parsed = try? CSCapUrn.fromString(candidate.urn) else { return false }
            return parsed.toString() == capUrn
        }) else { return nil }
        return capDef.args.first { arg in
            guard let argUrn = try? CSMediaUrn.fromString(arg.mediaUrn) else { return false }
            return argUrn.isEquivalent(to: incoming)
        }
    }

    /// The cap's MAIN INPUT arg (the stdin-sourced arg carrying `in=`, via
    /// the encapsulated `CapArg.isMainInput` predicate) — the arg a
    /// transport-blind cap consumes a live feed's CONTENT through.
    private func findMainInputArg() -> CapArg? {
        guard let manifest = manifest else { return nil }
        guard let capDef = manifest.allCaps().first(where: { candidate in
            guard let parsed = try? CSCapUrn.fromString(candidate.urn) else { return false }
            return parsed.toString() == capUrn
        }) else { return nil }
        guard let parsedCap = try? CSCapUrn.fromString(capUrn),
              let inSpec = try? CSMediaUrn.fromString(parsedCap.getInSpec()) else { return nil }
        return capDef.args.first { $0.isMainInput(inSpec: inSpec) }
    }

    /// Resolve the live reference into an open feed and the InputStream
    /// delivering it, by one of two arg matches (13.2 §Reference Media):
    /// an EXPLICIT reference arg (urn equivalent to the reference; content
    /// label = its stdin urn), else the cap's MAIN INPUT — the registered
    /// provider's `contentUrn` must conform to it, and labels the
    /// delivered stream. Hard errors on: no matching arg, no stdin source,
    /// `isSequence=false`, non-conforming provider content, an unparseable
    /// selector, or a provider/device failure. (matches Rust
    /// `LiveFeedContext::resolve`)
    func resolve(streamId: String, referenceUrn: String, selectorBytes: Data) throws -> InputStream {
        guard let incoming = try? CSMediaUrn.fromString(referenceUrn) else {
            throw StreamError.protocolError("invalid live-feed reference URN: \(referenceUrn)")
        }
        let arg: CapArg
        let contentUrn: String
        if let explicit = findArg(incoming) {
            var stdinUrn: String? = nil
            for source in explicit.sources {
                if case .stdin(let target) = source {
                    stdinUrn = target
                    break
                }
            }
            guard let stdinUrn = stdinUrn else {
                throw StreamError.protocolError(
                    "live-feed arg '\(explicit.mediaUrn)' on cap '\(capUrn)' declares no stdin source — a live "
                    + "reference must resolve to piped content (13.2 §Reference Media)"
                )
            }
            arg = explicit
            contentUrn = stdinUrn
        } else {
            guard let main = findMainInputArg() else {
                throw StreamError.protocolError(
                    "cap '\(capUrn)' declares no arg matching live-feed reference '\(referenceUrn)' "
                    + "and no stdin-sourced main input to resolve it against"
                )
            }
            guard let providerContent = providers.contentUrn(for: incoming) else {
                throw StreamError.protocolError(
                    "no live-feed provider is registered for reference '\(referenceUrn)' in this "
                    + "runtime — the cap's cartridge must register a capture backend for that device family"
                )
            }
            guard let content = try? CSMediaUrn.fromString(providerContent) else {
                throw StreamError.protocolError(
                    "provider for '\(referenceUrn)' declares an invalid content urn '\(providerContent)'"
                )
            }
            guard let mainUrn = try? CSMediaUrn.fromString(main.mediaUrn) else {
                throw StreamError.protocolError(
                    "main input urn '\(main.mediaUrn)' on cap '\(capUrn)' is not a valid media URN"
                )
            }
            guard content.conforms(to: mainUrn) else {
                throw StreamError.protocolError(
                    "live-feed reference '\(referenceUrn)' delivers '\(providerContent)' which does not "
                    + "conform to cap '\(capUrn)' main input '\(main.mediaUrn)' — this machine cannot "
                    + "consume that device"
                )
            }
            arg = main
            contentUrn = providerContent
        }
        if !arg.isSequence {
            throw StreamError.protocolError(
                "live-feed arg '\(arg.mediaUrn)' on cap '\(capUrn)' must declare is_sequence=true — a live "
                + "feed is an unbounded SEQUENCE of items"
            )
        }
        let selector: LiveFeedSelector
        do {
            selector = try LiveFeedSelector.parse(selectorBytes)
        } catch {
            throw StreamError.protocolError("\(error.localizedDescription)")
        }
        let opened: OpenedFeed
        do {
            opened = try openFeed(providers: providers, referenceUrn: referenceUrn, selector: selector)
        } catch {
            throw StreamError.protocolError("\(error.localizedDescription)")
        }
        opened.handle.bind(streamId: streamId)
        handles.add(opened.handle)
        return InputStream(
            mediaUrn: contentUrn,
            streamMeta: opened.streamMeta,
            rx: opened.items,
            unbounded: true,
            grants: nil
        )
    }
}
