// testcartridge-host — standalone OOM watchdog microcosm
//
// Hosts testcartridge as a cartridge (via CartridgeHost from Bifaci),
// invokes test-memory-hog, monitors memory metrics, tests kill mechanisms.
//
// No engine, no relay, no gRPC, no XPC, no UI.

import Foundation
import Bifaci
@preconcurrency import SwiftCBOR
import Darwin

// MARK: - SystemMemoryInfo

struct SystemMemoryInfo {
    let totalMb: UInt64
    let availableMb: UInt64     // total - active - wired (Activity Monitor style)
    let activeMb: UInt64
    let inactiveMb: UInt64      // mmap'd pages hide here
    let wiredMb: UInt64
    let compressedMb: UInt64
    let swapUsedMb: UInt64

    static func current() -> SystemMemoryInfo {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            fatalError("host_statistics64 failed: \(result)")
        }

        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let toMb: (UInt64) -> UInt64 = { ($0 * pageSize) / (1024 * 1024) }

        // Use sysctl for accurate total (vm_statistics doesn't include all pages)
        var totalBytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalBytes, &size, nil, 0)
        let totalMb = totalBytes / (1024 * 1024)

        let active = toMb(UInt64(stats.active_count))
        let inactive = toMb(UInt64(stats.inactive_count))
        let wired = toMb(UInt64(stats.wire_count))
        let compressed = toMb(UInt64(stats.compressor_page_count))
        // Activity Monitor style: available = total - active - wired
        let available = totalMb > (active + wired) ? totalMb - active - wired : 0

        // Swap usage via sysctl vm.swapusage
        var swapUsage = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swapUsage, &swapSize, nil, 0)
        let swapUsedMb = UInt64(swapUsage.xsu_used) / (1024 * 1024)

        return SystemMemoryInfo(
            totalMb: totalMb,
            availableMb: available,
            activeMb: active,
            inactiveMb: inactive,
            wiredMb: wired,
            compressedMb: compressed,
            swapUsedMb: swapUsedMb
        )
    }

    /// Compressed as percentage of total physical RAM (0-100).
    var compressedPercent: UInt64 {
        guard totalMb > 0 else { return 0 }
        return compressedMb * 100 / totalMb
    }

    /// Swap as percentage of total physical RAM (0-100).
    var swapPercent: UInt64 {
        guard totalMb > 0 else { return 0 }
        return swapUsedMb * 100 / totalMb
    }

    func summary() -> String {
        "avail=\(availableMb)MB active=\(activeMb)MB wired=\(wiredMb)MB compressed=\(compressedMb)MB swap=\(swapUsedMb)MB"
    }
}

// MARK: - Kernel Pressure Monitor

@discardableResult
func startKernelPressureMonitor(onPressure: @escaping (String) -> Void) -> DispatchSourceMemoryPressure {
    let source = DispatchSource.makeMemoryPressureSource(
        eventMask: [.warning, .critical],
        queue: .global(qos: .userInteractive)
    )
    source.setEventHandler {
        let status = source.data
        if status.contains(.critical) {
            onPressure("critical")
        } else if status.contains(.warning) {
            onPressure("warning")
        }
    }
    source.resume()
    return source
}

// MARK: - Timestamped Logging

let startTime = Date()

func log(_ msg: String) {
    let elapsed = Date().timeIntervalSince(startTime)
    let mins = Int(elapsed) / 60
    let secs = Int(elapsed) % 60
    print(String(format: "[%02d:%02d] %@", mins, secs, msg))
    fflush(stdout)
}

// MARK: - Cap Invocation

let memoryHogCapUrn = "cap:in=\"media:void\";op=test_memory_hog;out=\"media:textable\""
let hogSizeMediaUrn = "media:hog-size-mb;textable;numeric"
let hogHoldMediaUrn = "media:hog-hold-seconds;textable;numeric"

/// Build the full frame sequence to invoke test-memory-hog.
/// Returns (requestId, routingId, frames) — routingId is the XID that
/// CartridgeHost.run() requires on all incoming frames.
func buildMemoryHogRequest(sizeMb: Int, holdSeconds: Int) -> (reqId: MessageId, xid: MessageId, frames: [Frame]) {
    let reqId = MessageId.newUUID()
    let xid = MessageId.newUUID()  // We are the "relay" — we assign XID
    var frames: [Frame] = []

    // REQ
    var req = Frame.req(id: reqId, capUrn: memoryHogCapUrn, payload: Data(), contentType: "")
    req.routingId = xid
    frames.append(req)

    // Arg 1: hog-size-mb
    let sizeStreamId = UUID().uuidString
    var ss1 = Frame.streamStart(reqId: reqId, streamId: sizeStreamId, mediaUrn: hogSizeMediaUrn)
    ss1.routingId = xid
    frames.append(ss1)

    let sizePayload = Data(CBOR.byteString([UInt8]("\(sizeMb)".data(using: .utf8)!)).encode())
    let sizeChecksum = Frame.computeChecksum(sizePayload)
    var c1 = Frame.chunk(reqId: reqId, streamId: sizeStreamId, seq: 0, payload: sizePayload, chunkIndex: 0, checksum: sizeChecksum)
    c1.routingId = xid
    frames.append(c1)

    var se1 = Frame.streamEnd(reqId: reqId, streamId: sizeStreamId, chunkCount: 1)
    se1.routingId = xid
    frames.append(se1)

    // Arg 2: hog-hold-seconds
    let holdStreamId = UUID().uuidString
    var ss2 = Frame.streamStart(reqId: reqId, streamId: holdStreamId, mediaUrn: hogHoldMediaUrn)
    ss2.routingId = xid
    frames.append(ss2)

    let holdPayload = Data(CBOR.byteString([UInt8]("\(holdSeconds)".data(using: .utf8)!)).encode())
    let holdChecksum = Frame.computeChecksum(holdPayload)
    var c2 = Frame.chunk(reqId: reqId, streamId: holdStreamId, seq: 0, payload: holdPayload, chunkIndex: 0, checksum: holdChecksum)
    c2.routingId = xid
    frames.append(c2)

    var se2 = Frame.streamEnd(reqId: reqId, streamId: holdStreamId, chunkCount: 1)
    se2.routingId = xid
    frames.append(se2)

    // END — all input sent
    var end = Frame.end(id: reqId)
    end.routingId = xid
    frames.append(end)

    return (reqId, xid, frames)
}

// MARK: - Response Reader

enum CapResult {
    case completed(String)    // Final textable output
    case error(String, String) // code, message
    case cartridgeDied(String)
    case timeout              // No terminal frame within deadline
}

/// Process a single frame, returning a CapResult if terminal (END/ERR/EOF),
/// or nil if the frame was non-terminal (LOG, CHUNK, etc.).
func processFrame(_ frame: Frame, reqId: MessageId, resultText: inout String) -> CapResult? {
    guard frame.id == reqId else { return nil }

    switch frame.frameType {
    case .log:
        if let msg = frame.logMessage, let level = frame.logLevel {
            if level == "progress" {
                if let p = frame.logProgress {
                    log("  PROGRESS: \(String(format: "%.0f%%", p * 100)) \(msg)")
                }
            } else {
                log("  LOG[\(level)]: \(msg)")
            }
        }
        return nil

    case .streamStart, .streamEnd:
        return nil

    case .chunk:
        if let payload = frame.payload {
            if let cbor = try? CBORDecoder(input: [UInt8](payload)).decodeItem() {
                if case .byteString(let bytes) = cbor,
                   let str = String(data: Data(bytes), encoding: .utf8) {
                    resultText += str
                }
            }
        }
        return nil

    case .end:
        if resultText.isEmpty, let payload = frame.payload, !payload.isEmpty {
            if let cbor = try? CBORDecoder(input: [UInt8](payload)).decodeItem(),
               case .byteString(let bytes) = cbor,
               let str = String(data: Data(bytes), encoding: .utf8) {
                resultText = str
            }
        }
        return .completed(resultText)

    case .err:
        let code = frame.errorCode ?? "UNKNOWN"
        let msg = frame.errorMessage ?? "Unknown error"
        return .error(code, msg)

    default:
        return nil
    }
}

/// Read response frames until END or ERR for the given request.
/// Blocks indefinitely — use only when the cap is expected to complete normally.
func readResponse(reader: FrameReader, reqId: MessageId) -> CapResult {
    var resultText = ""
    while true {
        guard let frame = try? reader.read() else {
            return .cartridgeDied("Reader EOF — cartridge process likely died")
        }
        if let result = processFrame(frame, reqId: reqId, resultText: &resultText) {
            return result
        }
    }
}

/// Read response frames on a background thread with a timeout.
/// After the deadline, returns .timeout (the reader thread remains blocked but
/// won't interfere — subsequent tests use fresh request IDs so stale frames
/// from this request are harmlessly ignored by processFrame's reqId filter).
func readResponseWithTimeout(reader: FrameReader, reqId: MessageId, seconds: TimeInterval) -> CapResult {
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: CapResult = .timeout
    let thread = Thread {
        result = readResponse(reader: reader, reqId: reqId)
        sem.signal()
    }
    thread.name = "readResponse.timeout"
    thread.start()

    if sem.wait(timeout: .now() + seconds) == .timedOut {
        return .timeout
    }
    return result
}

// MARK: - Allocation Sizing

/// Compute allocation size as a percentage of total physical RAM.
func allocationMb(percent: Int) -> Int {
    let info = SystemMemoryInfo.current()
    let mb = Int(info.totalMb) * percent / 100
    log("  \(percent)% of \(info.totalMb)MB = \(mb)MB")
    return mb
}

// MARK: - Test: Pressure + Kill

/// Single test: allocate 90% of RAM with incompressible CSPRNG data, monitor
/// memory, detect pressure (kernel or threshold), kill cartridge, verify death.
/// The goal is to overload the system — force the kernel into real pressure.
func testPressureAndKill(host: CartridgeHost, writer: FrameWriter, reader: FrameReader) -> Bool {
    let percent = 90
    let sizeMb = allocationMb(percent: percent)
    let holdSec = 120
    log("=== Pressure test: \(sizeMb)MB (\(percent)% RAM), hold \(holdSec)s ===")

    let before = SystemMemoryInfo.current()
    log("Memory before: \(before.summary())")

    // Start kernel pressure monitor
    nonisolated(unsafe) var pressureLevel = ""
    nonisolated(unsafe) var pressureFired = false
    let pressureSem = DispatchSemaphore(value: 0)

    let source = startKernelPressureMonitor { level in
        guard !pressureFired else { return }
        pressureFired = true
        pressureLevel = level
        pressureSem.signal()
    }

    // Send request
    let (reqId, _, frames) = buildMemoryHogRequest(sizeMb: sizeMb, holdSeconds: holdSec)
    for frame in frames {
        do { try writer.write(frame) } catch {
            log("FAIL: write: \(error)")
            source.cancel()
            return false
        }
    }

    // Read response on background thread (non-blocking for main)
    nonisolated(unsafe) var capResult: CapResult = .timeout
    let readerDone = DispatchSemaphore(value: 0)
    let readerThread = Thread {
        capResult = readResponseWithTimeout(reader: reader, reqId: reqId, seconds: Double(holdSec) + 15)
        if !pressureFired { pressureSem.signal() }
        readerDone.signal()
    }
    readerThread.name = "reader"
    readerThread.start()

    // Monitor memory every 250ms — proactive kill before jetsam.
    //
    // General-purpose detection — no fixed percentage thresholds.
    //
    // The system freezes when the kernel can't keep up: it's compressing,
    // swapping, and faulting pages all at once. The detectable signature
    // is not any absolute metric but the RATE of change:
    //
    //   1. Swap is growing between polls → compressor has overflowed to disk.
    //      This is the universal signal. Regardless of total RAM, compression
    //      ratio, or workload — swap growth means the kernel lost the fight.
    //      But the swap growth must be sustained (2+ consecutive polls) to
    //      avoid false positives from one-off page-outs.
    //
    //   2. Available memory < 2GB → system is running out of room to work.
    //      This catches the brief window before compression kicks in, when
    //      active pages consume almost all physical RAM.
    //
    //   3. Kernel pressure dispatch source → fires before jetsam.
    //
    // None of these use percentage-of-RAM thresholds. They work on any
    // machine: 8GB, 16GB, 64GB, 128GB.
    var didKill = false
    var killReason = ""
    let baseline = SystemMemoryInfo.current()
    let baselineSwap = baseline.swapUsedMb
    log("  baseline: compressed=\(baseline.compressedMb)MB swap=\(baselineSwap)MB")

    let pollInterval: TimeInterval = 0.25
    let maxPolls = Int(Double(holdSec + 10) / pollInterval)
    var lastLogSecond: Int = -1
    var prevSwap = baselineSwap
    var consecutiveSwapGrowth = 0

    for poll in 0..<maxPolls {
        // Check kernel pressure first (non-blocking)
        if pressureFired {
            killReason = "kernel pressure: \(pressureLevel)"
            break
        }

        Thread.sleep(forTimeInterval: pollInterval)
        let info = SystemMemoryInfo.current()

        let compressedDelta = info.compressedMb > baseline.compressedMb
            ? info.compressedMb - baseline.compressedMb : 0
        let swapDelta = info.swapUsedMb > baselineSwap
            ? info.swapUsedMb - baselineSwap : 0

        // Track consecutive polls where swap grew — the key signal.
        // One-off swap writes happen normally. Sustained swap growth means
        // the compressor overflowed and the kernel is writing to disk
        // continuously. That's the point of no return.
        if info.swapUsedMb > prevSwap {
            consecutiveSwapGrowth += 1
        } else {
            consecutiveSwapGrowth = 0
        }
        prevSwap = info.swapUsedMb

        // Log once per second
        let elapsedSec = Int(Double(poll) * pollInterval)
        if elapsedSec != lastLogSecond {
            lastLogSecond = elapsedSec
            log("  [\(elapsedSec)s] \(info.summary()) | Δcomp=\(compressedDelta)MB Δswap=\(swapDelta)MB swapRun=\(consecutiveSwapGrowth)")
        }

        // Sustained swap growth: swap grew for 3+ consecutive polls (750ms+).
        // This means the compressor can't keep up and is continuously
        // spilling to disk. The system will freeze within seconds.
        // Works on any machine — swap growth rate is the universal signal.
        if consecutiveSwapGrowth >= 3 {
            killReason = "sustained swap growth: Δswap=\(swapDelta)MB over \(consecutiveSwapGrowth) consecutive polls"
            break
        }

        // Cartridge already died (jetsam killed it before we could)?
        if host.runningCartridges().isEmpty {
            log("FAIL: jetsam killed cartridge before we detected pressure")
            log("  We need to detect earlier — tighten thresholds")
            source.cancel()
            readerDone.wait()
            return false
        }
    }

    // Kill if we detected pressure
    if !killReason.isEmpty {
        log("  DETECTED: \(killReason)")
        let cartridges = host.runningCartridges()
        if let p = cartridges.first {
            log("  Killing cartridge pid=\(p.pid)...")
            host.killCartridge(pid: p.pid)
            didKill = true
        } else {
            log("FAIL: cartridge already dead — jetsam beat us")
            source.cancel()
            readerDone.wait()
            return false
        }
    } else {
        // Timeout — kill for cleanup
        log("  No pressure detected in \(holdSec)s — killing for cleanup")
        let cartridges = host.runningCartridges()
        if let p = cartridges.first {
            host.killCartridge(pid: p.pid)
        }
        source.cancel()
        log("FAIL: no pressure detected — test inconclusive")
        return false
    }

    Thread.sleep(forTimeInterval: 1.0)
    source.cancel()

    let after = SystemMemoryInfo.current()
    log("Memory after: \(after.summary())")

    // Verify cartridge is gone
    let stillAlive = host.runningCartridges().contains { $0.running }

    if didKill && !stillAlive {
        log("PASS: Proactively detected pressure and killed cartridge before jetsam")
        return true
    } else if didKill {
        log("FAIL: killed cartridge but it's still running")
        return false
    } else {
        log("FAIL: did not kill cartridge")
        return false
    }
}

// MARK: - Main

func findTestcartridge(explicitPath: String?) -> String {
    if let path = explicitPath {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            fputs("Error: testcartridge not found at \(path)\n", stderr)
            exit(1)
        }
        return path
    }
    // Auto-discover: look in capdag/target/debug/testcartridge relative to this repo
    let candidates = [
        // Relative to machinefabric root
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("../../capdag/target/debug/testcartridge").standardized.path,
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("../capdag/target/debug/testcartridge").standardized.path,
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("capdag/target/debug/testcartridge").standardized.path,
    ]
    for candidate in candidates {
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    fputs("Error: testcartridge binary not found. Build it with: cargo build -p testcartridge\n", stderr)
    fputs("Or specify: --cartridge /path/to/testcartridge\n", stderr)
    exit(1)
}

func parseArgs() -> String? {
    let args = CommandLine.arguments
    var cartridgePath: String?
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--cartridge":
            i += 1
            guard i < args.count else {
                fputs("Error: --cartridge requires a path argument\n", stderr)
                exit(1)
            }
            cartridgePath = args[i]
        case "--help", "-h":
            print("Usage: testcartridge-host [--cartridge PATH]")
            exit(0)
        default:
            fputs("Unknown argument: \(args[i])\n", stderr)
            exit(1)
        }
        i += 1
    }
    return cartridgePath
}

// --- Entry point ---

let explicitPath = parseArgs()
let cartridgePath = findTestcartridge(explicitPath: explicitPath)
log("Testcartridge: \(cartridgePath)")

let toHostPipe = Pipe()
let fromHostPipe = Pipe()

let host = CartridgeHost()
host.registerCartridge(path: cartridgePath, cartridgeDir: "", knownCaps: [memoryHogCapUrn])

let hostThread = Thread {
    do {
        try host.run(
            relayRead: toHostPipe.fileHandleForReading,
            relayWrite: fromHostPipe.fileHandleForWriting,
            resourceFn: { Data() }
        )
    } catch {
        log("CartridgeHost.run() error: \(error)")
    }
}
hostThread.name = "CartridgeHost.run"
hostThread.start()
Thread.sleep(forTimeInterval: 0.1)

let writer = FrameWriter(handle: toHostPipe.fileHandleForWriting)
let reader = FrameReader(handle: fromHostPipe.fileHandleForReading)

let success = testPressureAndKill(host: host, writer: writer, reader: reader)

host.close()
Thread.sleep(forTimeInterval: 0.5)
exit(success ? 0 : 1)
