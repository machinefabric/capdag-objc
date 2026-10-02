/// The runtime's objects, replayed against the proved model's scripts.
///
/// The decisions these objects make are the model's generated code
/// (formal/CapDAG/Bifaci), so this does not test the rules — those are proved.
/// It tests everything around them: that a `CreditGate`, a `CreditWindow`, a
/// `ReorderBuffer`, the writer's gate, a `RequestTable`, the runtime's pools
/// and the switch's admission carry the decisions out as the model means them
/// — their counters, their containers, the order they do things in.
///
/// `../formal/conformance-bifaci.json` is written by the model (`lake exe
/// conformance_bifaci`): for each machine, short scripts of operations and,
/// for each operation, what the model says happened. The same scripts run in
/// every mirror.

import XCTest
import Foundation
@preconcurrency import SwiftCBOR
import CapDAG
import Ops
@testable import Bifaci

/// The model's table, read once. It is read-only after it is loaded.
nonisolated(unsafe) private let bifaciTable: [String: Any] = {
    // Tests/BifaciTests/<this file> → the package root → ../formal
    let formal = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("formal")
    let url = formal.appendingPathComponent("conformance-bifaci.json")
    guard let data = try? Data(contentsOf: url),
          let table = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        fatalError("the model's table is not at \(url.path)")
    }
    return table
}()

private func rows(_ section: String) -> [[String: Any]] {
    guard let rows = bifaciTable[section] as? [[String: Any]], !rows.isEmpty else {
        fatalError("the model's table has no \(section) scripts")
    }
    return rows
}

private func number(_ value: Any?) -> UInt64 {
    guard let number = value as? NSNumber else { fatalError("\(String(describing: value)) is not a count") }
    return number.uint64Value
}

private func numbers(_ value: Any?) -> [UInt64] {
    guard let list = value as? [Any] else { fatalError("\(String(describing: value)) is not a list") }
    return list.map { number($0) }
}

/// A JSON string, or nil for JSON null.
private func text(_ value: Any?) -> String? {
    value as? String
}

private func flag(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { fatalError("\(String(describing: value)) is not a flag") }
    return number.boolValue
}

/// A waiting request: a thread asking for its permit.
private final class Arrival: @unchecked Sendable {
    let cap: String
    private let lock = NSLock()
    private var permitValue: AdmissionPermit?
    private var finished = false
    private var cancelled = false
    var held = false
    var settled = false

    init(_ controller: AdmissionController, cap: String, chain: [PoolKey]) {
        self.cap = cap
        Thread.detachNewThread { [self] in
            let permit = try? controller.acquire(chain, isCancelled: { self.isCancelled })
            lock.lock()
            permitValue = permit
            finished = true
            lock.unlock()
        }
    }

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var done: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    var permit: AdmissionPermit? { lock.lock(); defer { lock.unlock() }; return permitValue }
}

/// Wait for a condition that threads are about to make true.
private func eventually(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(5)
    while !condition() {
        if Date() > deadline { return false }
        Thread.sleep(forTimeInterval: 0.0002)
    }
    return true
}

@available(macOS 10.15.4, iOS 13.4, *)
final class ProtocolConformanceTests: XCTestCase {

    private func conclude(_ what: String, _ total: Int, _ wrong: [String]) {
        XCTAssertTrue(
            wrong.isEmpty,
            "\(wrong.count) of \(total) \(what) scripts disagree with the model; first: \(wrong.first ?? "")")
    }

    private func makeWireCapture() throws -> (sender: ChannelFrameSender, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("conformance-\(UUID().uuidString).bin")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        let sender = ChannelFrameSender(
            writer: FrameWriter(handle: handle),
            writerLock: NSLock(),
            seqAssigner: SeqAssigner(),
            drops: DropCounters(),
            stragglers: StragglerCounters()
        )
        return (sender, url)
    }

    /// Decode every length-prefixed frame from a captured wire buffer.
    private func decodeWire(_ url: URL) throws -> [Frame] {
        let buf = try Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        var frames: [Frame] = []
        var pos = 0
        while pos + 4 <= buf.count {
            let len = Int(UInt32(buf[pos]) << 24 | UInt32(buf[pos + 1]) << 16 | UInt32(buf[pos + 2]) << 8 | UInt32(buf[pos + 3]))
            pos += 4
            frames.append(try decodeFrame(buf.subdata(in: pos..<(pos + len))))
            pos += len
        }
        XCTAssertEqual(pos, buf.count, "trailing bytes on the wire")
        return frames
    }

    // TEST12375: every frame type is the type the model means by its number,
    // part of a flow exactly when the model says, and an end exactly when the
    // model says. The runtime's own FrameType is mapped onto the model's by
    // hand; a type mapped to the wrong one would be numbered, ordered and
    // gated as another.
    func test12375_frameTypesAreTheModels() {
        let table = rows("frame_types")
        XCTAssertEqual(table.count, FrameType.all.count, "the model and the runtime name the same types")
        var wrong: [String] = []
        for row in table {
            let code = number(row["code"])
            guard let frameType = FrameType(rawValue: UInt8(code)) else {
                wrong.append("wire number \(code) names no frame type here")
                continue
            }
            if ProtocolModel.code(of: frameType) != code {
                wrong.append("\(frameType) (\(code)) is mapped to the model's type \(ProtocolModel.code(of: frameType))")
            }
            if frameType.isFlow != flag(row["flow"]) {
                wrong.append("\(frameType): flow is \(frameType.isFlow)")
            }
            if frameType.isTerminal != flag(row["terminal"]) {
                wrong.append("\(frameType): terminal is \(frameType.isTerminal)")
            }
            let ends = TerminalKind.of(frame: frameType)?.rawValue
            if ends != text(row["ends"]) {
                wrong.append("\(frameType): ends its request as \(ends ?? "nothing")")
            }
            if Frame(frameType: frameType, id: .uint(1)).isFlowFrame() != frameType.isFlow {
                wrong.append("\(frameType): a frame and its type disagree on being of a flow")
            }
        }
        conclude("frame type", table.count, wrong)
    }

    // TEST12376: a credit gate answers every acquire, grant and close as the
    // model does, and holds what the model says it holds afterwards.
    func test12376_creditGateFollowsTheModel() {
        let scripts = rows("gate")
        var wrong: [String] = []
        for (index, script) in scripts.enumerated() {
            let gate = CreditGate(initialCredit: number(script["window"]))
            let ops = script["ops"] as! [[String: Any]]
            let steps = script["steps"] as! [[String: Any]]
            for (at, (op, step)) in zip(ops, steps).enumerated() {
                var answer: String? = nil
                switch text(op["op"])! {
                case "acquire":
                    do {
                        answer = try gate.tryAcquire(number(op["n"])) ? "acquired" : "wait"
                    } catch let closed as CreditClosed {
                        answer = "closed:\(closed.reason)"
                    } catch {
                        answer = "\(error)"
                    }
                case "grant":
                    gate.grant(number(op["n"]))
                case "close":
                    gate.close(reason: text(op["reason"])!)
                default:
                    XCTFail("unknown gate operation \(op)")
                }
                if answer != text(step["answer"]) || gate.available != number(step["available"])
                    || gate.isClosed != (text(step["closed"]) != nil) {
                    wrong.append("step \(at) of script \(index): answered \(answer ?? "nothing"), available \(gate.available), closed \(gate.isClosed)")
                    break
                }
            }
        }
        conclude("credit gate", scripts.count, wrong)
    }

    // TEST12377: a credit window accepts, refuses and grants as the model
    // does: an arriving chunk is a violation exactly when nothing is left of
    // the window, a grant is due exactly when a batch has built up, a flush
    // grants what is pending, and a continued chunk is granted back at once.
    func test12377_creditWindowFollowsTheModel() {
        let scripts = rows("window")
        var wrong: [String] = []
        for (index, script) in scripts.enumerated() {
            let window = CreditWindow(initialCredit: number(script["window"]))
            let ops = script["ops"] as! [String]
            let steps = script["steps"] as! [[String: Any]]
            for (at, (op, step)) in zip(ops, steps).enumerated() {
                var violation = false
                var grant: UInt64 = 0
                switch op {
                case "arrive":
                    violation = !window.arrive()
                case "continuation":
                    if window.arrive() {
                        grant = window.continued()
                    } else {
                        violation = true
                    }
                case "consume":
                    grant = window.consumed()
                case "flush":
                    grant = window.flush()
                default:
                    XCTFail("unknown window operation \(op)")
                }
                if violation != flag(step["violation"]) || grant != number(step["grant"])
                    || window.remaining != number(step["remaining"]) || window.pending != number(step["pending"]) {
                    wrong.append("step \(at) of script \(index): violation \(violation), grant \(grant), remaining \(window.remaining), pending \(window.pending)")
                    break
                }
            }
        }
        conclude("credit window", scripts.count, wrong)
    }

    // TEST12378: the window two ends start with is the smaller proposal, and
    // a proposal of zero is refused — it would deadlock every stream at its
    // first chunk.
    func test12378_aZeroWindowIsRefused() {
        let table = rows("negotiate")
        var wrong: [String] = []
        for row in table {
            let ours = number(row["ours"])
            let theirs = number(row["theirs"])
            let expected = (row["window"] as? NSNumber)?.uint64Value
            if negotiateInitialCredit(ours: ours, theirs: theirs) != expected {
                wrong.append("ours \(ours), theirs \(theirs): negotiated \(String(describing: negotiateInitialCredit(ours: ours, theirs: theirs)))")
            }
            // The limits two ends agree on carry the same decision.
            do {
                let limits = try Limits(initialCredit: ours).negotiate(with: Limits(initialCredit: theirs))
                if limits.initialCredit != expected {
                    wrong.append("ours \(ours), theirs \(theirs): limits \(limits.initialCredit)")
                }
            } catch {
                if expected != nil || !"\(error)".contains("initial_credit") {
                    wrong.append("ours \(ours), theirs \(theirs): refused with \(error)")
                }
            }
        }
        conclude("negotiation", table.count, wrong)
    }

    // TEST12379: a grant credits the stream it names, or — naming none — the
    // request's only sending stream; a grant that names a stream the request
    // does not have, or names none among several, credits nothing.
    func test12379_aGrantReachesTheStreamItIsFor() {
        let table = rows("grant_target")
        var wrong: [String] = []
        for (index, row) in table.enumerated() {
            let rid = MessageId.uint(7)
            let router = CreditRouter()
            let streams = (row["streams"] as! [Any]).map { text($0) }
            let named = text(row["named"])
            let gates = streams.map { stream -> CreditGate in
                let gate = CreditGate(initialCredit: 0)
                router.register(rid: rid, streamId: stream, gate: gate)
                return gate
            }
            // A gate of ANOTHER request with the same stream id must never be credited.
            let stranger = CreditGate(initialCredit: 0)
            router.register(rid: .uint(8), streamId: named, gate: stranger)

            let matched = router.grant(Frame.credit(targetRid: rid, streamId: named, credits: 3, direction: .response))
            let credited = zip(streams, gates).filter { $0.1.available == 3 }.map { $0.0 }
            let expected: [String?] = flag(row["matched"]) ? [text(row["target"])] : []
            if matched != flag(row["matched"]) || credited != expected || stranger.available != 0 {
                wrong.append("row \(index): matched \(matched), credited \(credited)")
            }
        }
        conclude("grant routing", table.count, wrong)
    }

    // TEST12380: frames arriving out of order are handed on in the order
    // they were written — each arrival delivers exactly what the model says,
    // holds what it says, and is refused when it says: a number already
    // handed on, one already held, or one more than the buffer may hold.
    func test12380_reorderBufferFollowsTheModel() {
        let refusals = [
            "stale": "Stale/duplicate seq: expected",
            "duplicate": "already buffered",
            "overflow": "Reorder buffer overflow",
        ]
        let scripts = rows("reorder")
        var wrong: [String] = []
        for (index, script) in scripts.enumerated() {
            let buffer = ReorderBuffer(maxBufferPerFlow: Int(number(script["limit"])))
            let arrivals = numbers(script["arrivals"])
            let steps = script["steps"] as! [[String: Any]]
            for (at, (seq, step)) in zip(arrivals, steps).enumerated() {
                var frame = Frame(frameType: .log, id: .uint(1))
                frame.seq = seq
                var delivered: [UInt64]? = nil
                var refusal: String? = nil
                do {
                    delivered = try buffer.accept(frame).map { $0.seq }
                } catch {
                    refusal = "\(error)"
                }
                let agrees: Bool
                if step["deliver"] != nil {
                    agrees = delivered == numbers(step["deliver"])
                } else if step["hold"] != nil {
                    agrees = delivered == []
                } else {
                    agrees = refusal?.contains(refusals[text(step["error"])!]!) ?? false
                }
                if !agrees {
                    wrong.append("step \(at) of script \(index) (\(arrivals)): \(String(describing: delivered)) \(refusal ?? "")")
                    break
                }
            }
        }
        conclude("reorder", scripts.count, wrong)
    }

    /// A frame of one type for one request, as a writer is handed it.
    private func frameOf(_ frameType: FrameType, _ rid: MessageId) -> Frame {
        switch frameType {
        case .chunk:
            let payload = Data([1])
            return Frame.chunk(reqId: rid, streamId: "s", seq: 0, payload: payload, chunkIndex: 0, checksum: Frame.computeChecksum(payload))
        case .log:
            return Frame.progress(id: rid, progress: 0.5, message: "working")
        case .end:
            return Frame.endOkWith(id: rid, finalPayload: nil, progress: 1.0, message: nil)
        case .err:
            return Frame.err(id: rid, code: "FAILED", attributionClass: .internal, message: "it failed")
        case .credit:
            return Frame.credit(targetRid: rid, streamId: nil, credits: 1, direction: .response)
        default:
            fatalError("the writer scripts hand over no \(frameType) frame")
        }
    }

    // TEST12381: the writer writes exactly the frames the model says:
    // everything until the flow's END or ERR, then nothing of the flow —
    // while credit, which is not of the flow, still passes. What reaches the
    // wire has the flow's numbers 0, 1, 2, … without a gap.
    func test12381_theWriterGateFollowsTheModel() throws {
        let scripts = rows("writer")
        var wrong: [String] = []
        for (index, script) in scripts.enumerated() {
            let rid = MessageId.uint(1)
            let (sender, url) = try makeWireCapture()
            let handed = numbers(script["frames"]).map { frameOf(FrameType(rawValue: UInt8($0))!, rid) }
            for frame in handed {
                try sender.send(frame)
            }
            let onWire = try decodeWire(url)
            // The frames written, in order, are the handed frames the model
            // says are written.
            let expected = zip(handed, (script["written"] as! [Any]).map { flag($0) })
                .filter { $0.1 }.map { $0.0.frameType }
            if onWire.map({ $0.frameType }) != expected {
                wrong.append("script \(index): wrote \(onWire.map { $0.frameType.asString })")
                continue
            }
            let flowSeqs = onWire.filter { $0.isFlowFrame() }.map { $0.seq }
            if flowSeqs != Array(0..<UInt64(flowSeqs.count)) {
                wrong.append("script \(index): flow frames numbered \(flowSeqs)")
            }
        }
        conclude("writer", scripts.count, wrong)
    }

    private func tableId(_ name: String) -> MessageId {
        let ids: [String: UInt64] = ["x1": 1, "x2": 2, "r1": 101, "r2": 102, "r3": 103]
        return .uint(ids[name]!)
    }

    private func requestState(initialCredit: UInt64 = 32) -> RequestState {
        RequestState(
            routing: RoutingEntry(sourceMasterIdx: nil, destinationMasterIdx: 0),
            origin: nil,
            externalChannel: nil,
            isPeer: false,
            initialCredit: initialCredit
        )
    }

    // TEST12382: a request table registers a request once, ends it once,
    // keeps no state for it afterwards, and tells a frame that crossed a
    // request's end from a frame for a request nobody knew — step for step as
    // the model's table does, including when the ring of ended requests is
    // full and the oldest is forgotten.
    func test12382_requestTableFollowsTheModel() throws {
        let scripts = rows("table")
        var wrong: [String] = []
        for (index, script) in scripts.enumerated() {
            let table = RequestTable(recentCapacity: Int(number(script["keep"])))
            let ops = script["ops"] as! [[String: Any]]
            let steps = script["steps"] as! [[String: Any]]
            var agreed = true
            for (at, (op, step)) in zip(ops, steps).enumerated() {
                let key = RequestKey(xid: tableId(text(op["xid"])!), rid: tableId(text(op["rid"])!))
                var ok = false
                switch text(op["op"])! {
                case "register":
                    ok = (try? table.register(key, requestState())) != nil
                case "terminate":
                    ok = table.terminate(key, kind: .end) != nil
                    if ok && (table.contains(key) || table.xidForRid(key.rid) != nil) {
                        wrong.append("step \(at) of script \(index): state remains after the end")
                        agreed = false
                    }
                default:
                    XCTFail("unknown table operation \(op)")
                }
                if !agreed { break }
                let frames = ["r1", "r2", "r3"].map { table.disposition(tableId($0)).rawValue }
                if ok != flag(step["ok"]) || frames != (step["frames"] as! [String]) {
                    wrong.append("step \(at) of script \(index): ok \(ok), frames \(frames)")
                    agreed = false
                    break
                }
            }
            if agreed && (UInt64(table.count) != number(script["live"]) || table.totalRegistered != number(script["registered"])) {
                wrong.append("script \(index): \(table.count) live, \(table.totalRegistered) registered")
            }
        }
        conclude("request table", scripts.count, wrong)

        // The ledger a request keeps of each stream's window moves as the
        // model's does: one less for a chunk, more by a grant, and by nothing
        // else.
        for row in rows("ledger") {
            let rid = MessageId.uint(9)
            let frameType = FrameType(rawValue: UInt8(number(row["frame"])))!
            var frame = frameType == .credit
                ? Frame.credit(targetRid: rid, streamId: "s", credits: number(row["granted"]), direction: .response)
                : Frame(frameType: frameType, id: rid)
            frame.streamId = "s"
            let table = RequestTable()
            let key = RequestKey(xid: .uint(1), rid: rid)
            try table.register(key, requestState(initialCredit: number(row["remaining"])))
            table.recordFrame(key, direction: .inbound, frame: frame)
            XCTAssertEqual(
                table.get(key)?.streams["s"]?.creditOutstanding,
                (row["after"] as! NSNumber).int64Value,
                "the ledger after \(row)")
        }
    }

    // TEST12383: a pool's limit is the smaller of the operator's number and
    // what the cartridge reports, with zero meaning no limit in both and in
    // the result; and a cartridge that is not running is given one request,
    // through `all`.
    func test12383_poolLimitsAreTheModels() {
        let table = rows("effective")
        var wrong: [String] = []
        for row in table {
            let configured = number(row["configured"])
            let available = (row["available"] as? NSNumber)?.uint64Value
            let state = PoolState(declared: configured, configured: configured, available: available)
            let effective = effectiveCapacity(configured: configured, available: available)
            if effective != number(row["effective"]) || state.effective() != effective
                || advertisedCapacity(running: true, pool: poolAll, state: state) != effective
                || advertisedCapacity(running: false, pool: poolAll, state: state) != number(row["cold_all"])
                || advertisedCapacity(running: false, pool: "gpu", state: state) != number(row["cold_other"]) {
                wrong.append("configured \(configured), available \(String(describing: available)): effective \(effective)")
            }
        }
        conclude("pool limit", table.count, wrong)
    }

    /// The scripts name caps as they are written; the runtime names their
    /// pools by the canonical form.
    private func canon(_ name: String) -> String {
        guard name.hasPrefix("cap:") else { return name }
        return try! CSCapUrn.fromString(name).toString()
    }

    private func queuedRequest(_ pattern: String) -> PoolQueuedRequest {
        PoolQueuedRequest(
            factory: { AnyOp(EchoAllBytesOp()) },
            capUrn: pattern,
            pattern: pattern,
            ticket: 0,
            routingId: nil,
            requestId: .newUUID(),
            outputMediaUrn: "media:",
            frames: BlockingQueue<Frame>()
        )
    }

    // TEST12384: the runtime's pools admit, queue and release exactly as the
    // model's scripts say — who holds a slot in which pool, who is in line,
    // who goes next, and how many waiters each pool is holding back —
    // including where a pool's limit rose and a request arrives while
    // somebody in line could go: it waits behind them rather than taking the
    // slot.
    func test12384_runtimePoolsFollowTheModel() throws {
        let scripts = rows("pools")
        var wrong: [String] = []
        for (index, script) in scripts.enumerated() {
            var shared: [String: [String]] = [:]
            for pool in script["shared"] as! [[String: Any]] {
                shared[text(pool["name"])!] = (pool["caps"] as! [String]).map(canon)
            }
            var capacities: [String: UInt64] = [:]
            for capacity in script["capacities"] as! [[String: Any]] {
                capacities[canon(text(capacity["pool"])!)] = number(capacity["capacity"])
            }
            let pools = try RuntimePools(
                handlerPatterns: (script["caps"] as! [String]).map(canon),
                declarations: PoolDeclarations(pools: shared, capacities: capacities)
            )
            let names = (script["pools"] as! [String]).map(canon)
            var inLine: [UInt64: MessageId] = [:]
            let ops = script["ops"] as! [[String: Any]]
            let steps = script["steps"] as! [[String: Any]]
            for (at, (op, step)) in zip(ops, steps).enumerated() {
                var agreed = false
                switch text(op["op"])! {
                case "arrive":
                    let request = queuedRequest(canon(text(op["cap"])!))
                    switch pools.arrive(request) {
                    case .admitted(let admitted):
                        agreed = admitted.requestId == request.requestId && flag(step["admitted"])
                    case .queued(let position):
                        let ticket = pools.waiting.first { $0.value.requestId == request.requestId }!.key
                        inLine[ticket] = request.requestId
                        agreed = !flag(step["admitted"]) && ticket == number(step["ticket"])
                            && UInt64(position) == number(step["position"])
                    }
                case "release":
                    pools.release(canon(text(op["cap"])!))
                    agreed = true
                case "admit_next":
                    let expected = (step["ticket"] as? NSNumber)?.uint64Value
                    if let went = pools.admitNext() {
                        agreed = went.ticket == expected && inLine.removeValue(forKey: went.ticket) == went.requestId
                    } else {
                        agreed = expected == nil
                    }
                case "leave_oldest":
                    let ticket = number(step["ticket"])
                    let rid = inLine.removeValue(forKey: ticket)!
                    agreed = pools.removeQueued(requestId: rid)?.ticket == ticket
                        && pools.removeQueued(requestId: rid) == nil
                case "capacity":
                    try pools.applyDesired([canon(text(op["pool"])!): number(op["capacity"])])
                    agreed = true
                default:
                    XCTFail("unknown pools operation \(op)")
                }
                let snapshot = pools.snapshot()
                let active = names.map { snapshot[$0]!.active }
                let heldBack = names.map { snapshot[$0]!.queued }
                let waiting = pools.waiting.keys.sorted()
                if !agreed || active != numbers(step["active"]) || heldBack != numbers(step["held_back"])
                    || waiting != numbers(step["waiting"]) {
                    wrong.append("step \(at) of script \(index): agreed \(agreed), active \(active), held back \(heldBack), waiting \(waiting)")
                    break
                }
            }
        }
        conclude("pools", scripts.count, wrong)
    }

    /// A frame as the model's recognizer of a flow's order sees it; nil for a
    /// frame that is not of the flow.
    private func emitted(_ frame: Frame) -> ProtocolModel.Emitted? {
        guard frame.isFlowFrame() else { return nil }
        switch frame.frameType {
        case .streamStart: return .streamStart(stream: frame.streamId!)
        case .chunk: return ProtocolModel.emittedChunk(stream: frame.streamId!, index: frame.chunkIndex!)
        case .streamEnd: return ProtocolModel.emittedStreamEnd(stream: frame.streamId!, count: frame.chunkCount)
        case .end: return .fin
        case .err: return .err
        default: return .other
        }
    }

    // TEST12385: what an output stream and the writer put on the wire for
    // one request is a flow in order, by the model's own recognizer: the
    // stream is started once, its chunks are numbered 0, 1, 2, …, its end
    // says how many there were, and nothing of the flow follows END —
    // although a late progress frame and a late chunk were handed to the
    // writer after it.
    func test12385_whatReachesTheWireIsAFlowInOrder() async throws {
        let (sender, url) = try makeWireCapture()
        let rid = MessageId.newUUID()
        let output = Bifaci.OutputStream(
            sender: sender,
            streamId: "s1",
            mediaUrn: "media:enc=utf-8",
            requestId: rid,
            routingId: nil,
            maxChunk: 4
        )
        try output.start(isSequence: false)
        try await output.write(Data(repeating: 7, count: 10))
        output.progress(0.5, message: "halfway")
        try await output.close()

        // The handler's END, then what a detached sender does: frames that
        // lost the race with it.
        let late = Data([9])
        let handedOver = [
            Frame.endOkWith(id: rid, finalPayload: nil, progress: 1.0, message: nil),
            Frame.progress(id: rid, progress: 1.0, message: "late keepalive"),
            Frame.chunk(reqId: rid, streamId: "s1", seq: 0, payload: late, chunkIndex: 3, checksum: Frame.computeChecksum(late)),
        ]
        for frame in handedOver {
            try sender.send(frame)
        }

        let onWire = try decodeWire(url)
        let flow = onWire.compactMap(emitted)
        XCTAssertNil(ProtocolModel.check(flow), "the wire carries \(flow)")
        XCTAssertEqual(onWire.filter { $0.frameType == .chunk }.count, 3, "ten bytes at four a chunk")
        XCTAssertEqual(
            onWire.first { $0.frameType == .streamEnd }?.chunkCount, 3,
            "the stream's end says how many chunks it carried")
        XCTAssertEqual(onWire.last?.frameType, .end)

        // The recognizer is what found nothing wrong, not a rubber stamp: the
        // flow with the late frames the gate held back is refused for them.
        let ungated = flow + handedOver.dropFirst().compactMap(emitted)
        XCTAssertEqual(ProtocolModel.check(ungated), .afterEnd)
    }

    // TEST12386: a handler changing what one of its pools can serve wakes
    // the runtime, which starts whoever in line can now go. Without that a
    // request in line waited for the host's next frame.
    func test12386_aSelfReportWakesTheRuntime() throws {
        let cell = PoolsCell()
        cell.pools = try RuntimePools(
            handlerPatterns: ["cap:pool-a"],
            declarations: PoolDeclarations(pools: ["gpu": ["cap:pool-a"]], capacities: ["gpu": 2])
        )
        let woken = LockedCounter()
        cell.changed = { woken.increment() }

        try PoolHandle(cell: cell, name: "gpu").set(1)
        XCTAssertEqual(woken.value, 1, "a self-report must wake the runtime")
        XCTAssertEqual(cell.pools!.snapshot()["gpu"]?.available, 1)

        // A refused self-report changed nothing, and wakes nobody.
        XCTAssertThrowsError(try PoolHandle(cell: cell, name: "cap:ghost").set(1)) { error in
            XCTAssertTrue("\(error)".contains("cap:ghost"), "\(error)")
        }
        XCTAssertEqual(woken.value, 1)
    }

    private func admissionKey() -> AdmissionKey {
        AdmissionKey(masterIdx: 0, registryURL: nil, channel: "release", id: "cartridge", version: "1.0.0", sha256: "sha")
    }

    // TEST12387: the switch admits as the model's scripts say. Every arrival
    // is a waiting thread; after each thing that happens — an arrival, a
    // release, a waiter giving up, a limit changing — exactly the requests
    // the model admits have been admitted, in the model's order across caps,
    // and each pool holds what the model says it holds.
    func test12387_switchAdmissionFollowsTheModel() {
        let scripts = rows("admission")
        var wrong: [String] = []
        for (index, script) in scripts.enumerated() {
            let controller = AdmissionController()
            let install = admissionKey()
            let names = script["pools"] as! [String]
            var advertised: [String: UInt64] = [:]
            for name in names { advertised[name] = 0 }
            for capacity in script["capacities"] as! [[String: Any]] {
                advertised[text(capacity["pool"])!] = number(capacity["capacity"])
            }
            controller.configurePools(install, pools: advertised)
            let sharedPools = script["shared"] as! [[String: Any]]
            func chainOf(_ cap: String) -> [PoolKey] {
                let shared = sharedPools.filter { ($0["caps"] as! [String]).contains(cap) }.map { text($0["name"])! }
                return ([cap] + shared + [poolAll]).map { PoolKey(install: install, pool: $0) }
            }
            func state() -> (active: [UInt64], waiting: [UInt64]) {
                let active = controller.active(install)
                return (names.map { active[$0]! }, controller.waiting(install))
            }

            var arrivals: [Arrival] = []
            let ops = script["ops"] as! [[String: Any]]
            let steps = script["steps"] as! [[String: Any]]
            for (at, (op, step)) in zip(ops, steps).enumerated() {
                switch text(op["op"])! {
                case "arrive":
                    let cap = text(op["cap"])!
                    arrivals.append(Arrival(controller, cap: cap, chain: chainOf(cap)))
                case "release":
                    let holder = arrivals.first { $0.held && $0.cap == text(op["cap"])! }!
                    holder.permit!.release()
                    holder.held = false
                case "leave_oldest":
                    let oldest = arrivals.first { !$0.settled }!
                    oldest.cancel()
                    XCTAssertTrue(eventually { oldest.done }, "a cancelled waiter gives up")
                    oldest.settled = true
                case "capacity":
                    controller.configurePools(install, pools: [text(op["pool"])!: number(op["capacity"])])
                default:
                    XCTFail("unknown admission operation \(op)")
                }

                let expectedActive = numbers(step["active"])
                let expectedWaiting = numbers(step["waiting"])
                guard eventually({ state().active == expectedActive && state().waiting == expectedWaiting }) else {
                    wrong.append("step \(at) of script \(index): active and waiting \(state())")
                    break
                }
                // Exactly the tickets the model admits hold a permit now.
                var agreed = true
                for ticket in numbers(step["admitted"]) {
                    let waiter = arrivals[Int(ticket)]
                    agreed = agreed && eventually { waiter.done } && waiter.permit != nil
                    waiter.held = true
                    waiter.settled = true
                }
                let early = arrivals.enumerated().filter { !$0.element.settled && $0.element.done }.map { $0.offset }
                if !agreed || !early.isEmpty {
                    wrong.append("step \(at) of script \(index): the model admits \(numbers(step["admitted"])); admitted besides: \(early)")
                    break
                }
            }
            for waiter in arrivals {
                waiter.cancel()
            }
            if !wrong.isEmpty {
                // Every disagreement is waited out before it is one; the first says enough.
                break
            }
        }
        conclude("admission", scripts.count, wrong)
    }

    // TEST12388: a request that joins the line late into an outage is given
    // what is left of the outage's window, not a window of its own: the time
    // is the outage's.
    func test12388_aLateArrivalGetsWhatIsLeftOfTheOutage() {
        let controller = AdmissionController()
        controller.grace = 0.6
        let install = admissionKey()
        controller.configurePools(install, pools: [poolAll: 1])
        controller.disableMaster(install.masterIdx)
        Thread.sleep(forTimeInterval: 0.45)

        let arrived = Date()
        XCTAssertThrowsError(try controller.acquire([PoolKey(install: install, pool: poolAll)])) { error in
            XCTAssertTrue("\(error)".contains("unavailable for longer than"), "\(error)")
        }
        let waited = Date().timeIntervalSince(arrived)
        XCTAssertTrue(
            waited >= 0.05 && waited < 0.5,
            "it waited \(waited)s: what was left of the outage's window was about 0.15s — not nothing, and not a window of its own")
    }

    // TEST12389: a HELLO proposing a credit window of zero fails the
    // handshake, naming the window. Under a zero window no chunk may be sent,
    // and with none consumed none is ever granted: every stream would stop at
    // its first chunk, for good.
    func test12389_handshakeRefusesAZeroCreditWindow() throws {
        let toCartridge = Pipe()
        let fromCartridge = Pipe()
        try FrameWriter(handle: toCartridge.fileHandleForWriting)
            .write(Frame.hello(limits: Limits(initialCredit: 0)))
        try toCartridge.fileHandleForWriting.close()
        XCTAssertThrowsError(
            try acceptHandshakeWithManifest(
                reader: FrameReader(handle: toCartridge.fileHandleForReading),
                writer: FrameWriter(handle: fromCartridge.fileHandleForWriting),
                manifest: Data("{}".utf8),
                poolStates: [:]
            )
        ) { error in
            XCTAssertTrue("\(error)".contains("initial_credit"), "\(error)")
        }
    }
}

/// Thread-safe counter.
private final class LockedCounter: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
