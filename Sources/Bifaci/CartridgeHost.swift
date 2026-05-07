//
//  CartridgeHost.swift
//  Bifaci
//
//  Multi-cartridge host runtime — manages N cartridge binaries with frame routing.
//
//  The CartridgeHost sits between the relay connection (to the engine) and
//  individual cartridge processes. It handles:
//
//  - HELLO handshake and limit negotiation per cartridge
//  - Cap-based routing (REQ by cap_urn, continuation frames by req_id)
//  - Heartbeat health monitoring per cartridge
//  - Cartridge death detection and ERR propagation
//  - Aggregate capability advertisement
//
//  Architecture:
//
//    Relay (engine) <-> CartridgeHost <-> Cartridge A (stdin/stdout)
//                                      <-> Cartridge B (stdin/stdout)
//                                      <-> Cartridge C (stdin/stdout)
//
//  Frame Routing:
//
//  Engine -> Cartridge:
//  - REQ: route by cap_urn to the cartridge that handles it
//  - STREAM_START/CHUNK/STREAM_END/END/ERR: route by req_id to the mapped cartridge
//
//  Cartridge -> Engine:
//  - HEARTBEAT: handled locally, never forwarded
//  - REQ (peer invoke): registered in routing table, forwarded to relay
//  - Everything else: forwarded to relay (pass-through)

import Foundation
import CommonCrypto
import os
@preconcurrency import SwiftCBOR
import CapDAG

// MARK: - CartridgeHostObserver

/// Lifecycle observer for `CartridgeHost`. Mirrors the Rust
/// `CartridgeHostObserver` trait in `capdag/src/bifaci/host_runtime.rs`.
///
/// The host invokes the registered observer's callbacks at the
/// moments a cartridge becomes runnable (`spawned`) and at the moment
/// it has stopped running (`died`). All callbacks fire synchronously
/// from the host's internal threads — implementations MUST NOT block
/// or take long-held locks: the host's `stateLock` is **not** held
/// during the call, but the call still runs on the run loop / reader
/// thread that produced the event.
///
/// Used by `CartridgeXPCService` to forward lifecycle into reverse-XPC
/// callbacks; not used by the engine or in-process tests (they leave
/// the observer unset).
public protocol CartridgeHostObserver: AnyObject {
    /// A cartridge has just transitioned to running (handshake
    /// completed, caps extracted, reader thread started).
    /// - Parameters:
    ///   - cartridgeIndex: stable index assigned by the host
    ///   - pid: OS process id, or `nil` for in-process attached cartridges
    ///   - name: derived from the cartridge binary path's last component,
    ///     or empty for attached cartridges with no path
    ///   - caps: cap URN strings declared by the cartridge's manifest
    func cartridgeSpawned(cartridgeIndex: Int, pid: pid_t?, name: String, caps: [String])

    /// A cartridge has just transitioned to not-running (reader thread
    /// observed EOF, process reaped, OOM-kill, or clean shutdown).
    /// - Parameters:
    ///   - cartridgeIndex: stable index assigned by the host
    ///   - pid: OS process id at time of death, or `nil`
    ///   - name: derived from the cartridge binary path's last component
    func cartridgeDied(cartridgeIndex: Int, pid: pid_t?, name: String)
}

private func sha256Hex(for data: Data) -> String {
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    data.withUnsafeBytes { bytes in
        _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}

/// Errors raised by `computeCartridgeDirectoryHash` and
/// `computeFileSHA256`. Each variant names the operation and the path
/// that failed so the caller can surface the real cause instead of a
/// generic "unhashable" message.
public enum CartridgeDirectoryHashError: Error, CustomStringConvertible {
    /// `FileManager.enumerator(atPath:)` returned nil — the directory
    /// itself is unreadable (does not exist, no permission, mid-rename).
    case directoryUnreadable(path: String)
    /// `open(2)` failed for a file inside the directory.
    case openFailed(path: String, errno: Int32)
    /// `read(2)` returned -1 partway through hashing a file.
    case readFailed(path: String, errno: Int32)

    public var description: String {
        switch self {
        case .directoryUnreadable(let path):
            return "cartridge directory unreadable at \(path)"
        case .openFailed(let path, let err):
            return "open() failed for \(path): \(String(cString: strerror(err)))"
        case .readFailed(let path, let err):
            return "read() failed for \(path): \(String(cString: strerror(err)))"
        }
    }
}

/// SHA256 chunk size for streaming file content into the hash context.
/// Chosen to fit comfortably under any plausible sandbox memory ceiling
/// (XPC services have tighter limits than full apps) while still
/// amortising the per-call syscall overhead. 1 MiB is large enough that
/// a 200 MB cartridge binary takes ~200 reads — negligible — and small
/// enough that we never need a Data allocation that approaches the
/// sandbox memory budget.
public let cartridgeHashStreamChunk: Int = 1 << 20

/// Compute a deterministic SHA256 hash of a cartridge directory tree.
///
/// Walks all files recursively, sorts by relative path, then for each
/// file feeds its UTF-8 relative path and its byte content into a
/// single SHA256 context. Excludes `cartridge.json` (install-time
/// metadata that varies between installs).
///
/// File content is streamed through `read(2)` in fixed-size chunks
/// rather than slurped into memory with `FileManager.contents(atPath:)`.
/// The slurp form was the original failure mode: a 200+ MB cartridge
/// binary inside the sandboxed XPC service hit a memory ceiling and
/// `contents(atPath:)` returned nil, which the caller turned into a
/// generic `fatalError`. Streamed chunks make the function's memory
/// footprint constant in file size, so any cartridge directory — no
/// matter how big its binary or asset bundles — hashes successfully
/// as long as the files are readable.
///
/// On real failure (directory missing, permission denied, read I/O
/// error mid-walk) this throws a `CartridgeDirectoryHashError` whose
/// message names the offending path and underlying errno. Callers must
/// not paper over those with `try?`/`?? ""` in the healthy path —
/// surface the error so operators see what's actually wrong.
public func computeCartridgeDirectoryHash(atPath dirPath: String) throws -> String {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(atPath: dirPath) else {
        throw CartridgeDirectoryHashError.directoryUnreadable(path: dirPath)
    }

    var files: [(relativePath: String, fullPath: String)] = []

    while let relativePath = enumerator.nextObject() as? String {
        let fullPath = (dirPath as NSString).appendingPathComponent(relativePath)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir),
              !isDir.boolValue else {
            continue
        }
        if relativePath == "cartridge.json" {
            continue
        }
        files.append((relativePath: relativePath, fullPath: fullPath))
    }

    files.sort { $0.relativePath < $1.relativePath }

    var context = CC_SHA256_CTX()
    CC_SHA256_Init(&context)

    var chunk = [UInt8](repeating: 0, count: cartridgeHashStreamChunk)

    for file in files {
        if let pathData = file.relativePath.data(using: .utf8) {
            pathData.withUnsafeBytes { bytes in
                CC_SHA256_Update(&context, bytes.baseAddress, CC_LONG(pathData.count))
            }
        }

        let fd = open(file.fullPath, O_RDONLY)
        if fd < 0 {
            throw CartridgeDirectoryHashError.openFailed(path: file.fullPath, errno: errno)
        }
        defer { Darwin.close(fd) }

        while true {
            let bytesRead = chunk.withUnsafeMutableBufferPointer { buf -> ssize_t in
                Darwin.read(fd, buf.baseAddress, buf.count)
            }
            if bytesRead < 0 {
                throw CartridgeDirectoryHashError.readFailed(path: file.fullPath, errno: errno)
            }
            if bytesRead == 0 {
                break
            }
            chunk.withUnsafeBufferPointer { buf in
                CC_SHA256_Update(&context, buf.baseAddress, CC_LONG(bytesRead))
            }
        }
    }

    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256_Final(&hash, &context)

    return hash.map { String(format: "%02x", $0) }.joined()
}

/// Compute SHA256 of a single file by streaming its content through
/// `read(2)` in `cartridgeHashStreamChunk`-sized chunks. Used for
/// quarantine identity tracking (the hash of a cartridge binary is
/// what tells the host whether a quarantined cartridge has been
/// replaced by a new build) and for any other place where we need the
/// hash of a single on-disk file without loading it whole into memory.
///
/// Throws `CartridgeDirectoryHashError.openFailed` / `.readFailed`
/// with the path and errno on real I/O failure. Callers that have
/// good reason to swallow the error (e.g. already-failing recovery
/// paths where the binary may be gone) can `try?` it to a sentinel
/// string, but healthy paths must propagate the error so operators
/// see the actual cause.
public func computeFileSHA256(atPath path: String) throws -> String {
    let fd = open(path, O_RDONLY)
    if fd < 0 {
        throw CartridgeDirectoryHashError.openFailed(path: path, errno: errno)
    }
    defer { Darwin.close(fd) }

    var ctx = CC_SHA256_CTX()
    CC_SHA256_Init(&ctx)

    var chunk = [UInt8](repeating: 0, count: cartridgeHashStreamChunk)
    while true {
        let bytesRead = chunk.withUnsafeMutableBufferPointer { buf -> ssize_t in
            Darwin.read(fd, buf.baseAddress, buf.count)
        }
        if bytesRead < 0 {
            throw CartridgeDirectoryHashError.readFailed(path: path, errno: errno)
        }
        if bytesRead == 0 {
            break
        }
        chunk.withUnsafeBufferPointer { buf in
            CC_SHA256_Update(&ctx, buf.baseAddress, CC_LONG(bytesRead))
        }
    }

    var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    CC_SHA256_Final(&hash, &ctx)
    return hash.map { String(format: "%02x", $0) }.joined()
}

// ---------------------------------------------------------------------------
// Installed-cartridge identity assembly
// ---------------------------------------------------------------------------

/// Identity tuple parsed from a cartridge's `cartridge.json`.
/// `internal` so unit tests can drive `resolveLocalCartridgeRecord`
/// directly without standing up a host.
struct LocalCartridgeRecord {
    let registryURL: String?
    let id: String
    let channel: String
    let version: String
}

/// Read `(registryURL, id, channel, version)` from a cartridge's
/// `cartridge.json`. Returns nil when the file is missing,
/// malformed, or omits a required field.
///
/// **No layout fallback.** Cartridge identity comes from
/// `cartridge.json` only — the directory tree is a placement
/// convention, not an identity source. A cartridge whose
/// `cartridge.json` doesn't parse is treated as broken: the host
/// returns nil here, and the discovery scanner is expected to
/// grace-period-delete the directory on a separate code path. Any
/// mismatch between `cartridge.json` and the on-disk slug/channel/
/// name/version is the scanner's job to detect, not this function's.
internal func resolveLocalCartridgeRecord(cartridgeDir: String) -> LocalCartridgeRecord? {
    let cartridgeJsonPath = (cartridgeDir as NSString).appendingPathComponent("cartridge.json")
    guard let data = FileManager.default.contents(atPath: cartridgeJsonPath),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let name = json["name"] as? String,
          let channel = json["channel"] as? String,
          let version = json["version"] as? String,
          channel == "release" || channel == "nightly",
          json.keys.contains("registry_url") else {
        return nil
    }
    let registryURL: String?
    if json["registry_url"] is NSNull {
        registryURL = nil
    } else if let s = json["registry_url"] as? String {
        registryURL = s
    } else {
        return nil
    }
    return LocalCartridgeRecord(
        registryURL: registryURL,
        id: name.lowercased(),
        channel: channel,
        version: version
    )
}

/// Build the `InstalledCartridgeRecord` (sans live runtime stats)
/// for a managed cartridge whose on-disk anchor is `cartridgeDir`.
/// Pure function over the inputs + the file system; no host or
/// cartridge-instance state. Hoisted out of `ManagedCartridge` so
/// unit tests can drive every branch.
///
/// Returns nil when `cartridge.json` is missing or malformed —
/// cartridge identity is sourced from the manifest only, and a
/// cartridge whose manifest can't be read is treated as gone for
/// the purposes of this RelayNotify pass. The discovery scanner
/// owns the grace-period delete on a separate code path.
///
/// Behaviour matrix (when cartridge.json IS readable):
///   * `attachmentError != nil` → identity carries the existing
///     error verbatim; sha256 is best-effort (empty on hash
///     failure), since the cartridge is already broken and an
///     unhashable anchor here is a corollary, not a new problem.
///   * `attachmentError == nil`, hash succeeds → identity with the
///     real sha256 and no error.
///   * `attachmentError == nil`, hash throws
///     `CartridgeDirectoryHashError` → identity with sha256 = ""
///     and a freshly-minted `entryPointMissing` attachment error.
///     This is the "directory disappeared after attach" path that
///     used to `fatalError` the host (CartridgeHost.swift original
///     line 617). Now it surfaces as a per-cartridge failure
///     record: the host stays alive and the engine sees the
///     cartridge as broken until the next discovery scan corrects
///     the inventory.
///   * Hash throws something other than `CartridgeDirectoryHashError`
///     → fatalError. The hash function's error type is part of its
///     contract; an unknown variant here means the function evolved
///     and this site didn't keep up — a programmer-broken
///     invariant we want to surface.
internal func buildInstalledCartridgeRecord(
    cartridgeDir: String,
    attachmentError: CartridgeAttachmentError?
) -> InstalledCartridgeRecord? {
    guard let identity = resolveLocalCartridgeRecord(cartridgeDir: cartridgeDir) else {
        return nil
    }

    if let error = attachmentError {
        let sha256 = (try? computeCartridgeDirectoryHash(atPath: cartridgeDir)) ?? ""
        return InstalledCartridgeRecord(
            registryURL: identity.registryURL,
            id: identity.id,
            channel: identity.channel,
            version: identity.version,
            sha256: sha256,
            attachmentError: error,
            // Failed-state record: lifecycle is irrelevant per the
            // mutual-exclusivity contract. Use `.discovered` as the
            // safe sentinel (never `.operational`).
            lifecycle: .discovered
        )
    }

    let sha256: String
    do {
        sha256 = try computeCartridgeDirectoryHash(atPath: cartridgeDir)
    } catch let error as CartridgeDirectoryHashError {
        return InstalledCartridgeRecord(
            registryURL: identity.registryURL,
            id: identity.id,
            channel: identity.channel,
            version: identity.version,
            sha256: "",
            attachmentError: .now(
                kind: .entryPointMissing,
                message: "cartridge directory at \(cartridgeDir) is no longer hashable: \(error)"
            ),
            lifecycle: .discovered
        )
    } catch {
        fatalError(
            "BUG: unexpected error type from computeCartridgeDirectoryHash at \(cartridgeDir): \(error)"
        )
    }

    // Hash succeeded; the engine-side host has not yet attached
    // (HELLO etc.), and the registry has not been verified.
    // Engine treats this record as "registered, not yet
    // dispatchable"; the XPC service overrides the lifecycle to
    // `.inspecting` / `.verifying` / `.operational` as it works.
    return InstalledCartridgeRecord(
        registryURL: identity.registryURL,
        id: identity.id,
        channel: identity.channel,
        version: identity.version,
        sha256: sha256,
        attachmentError: nil,
        lifecycle: .discovered
    )
}

// MARK: - Activity Timeout Constants

/// Default timeout (seconds) for inactivity during cap execution.
/// If a cartridge sends no frames for this duration, the cap is aborted.
public let DEFAULT_ACTIVITY_TIMEOUT_SECS: UInt64 = 120

/// Cap metadata key for per-cap activity timeout override.
/// If present, its value (seconds) replaces the default timeout.
public let ACTIVITY_TIMEOUT_METADATA_KEY: String = "activity_timeout_secs"

// MARK: - Error Types

/// Errors that can occur in the cartridge host
public enum CartridgeHostError: Error, LocalizedError, Sendable {
    case handshakeFailed(String)
    case sendFailed(String)
    case receiveFailed(String)
    case cartridgeError(code: String, message: String)
    case unexpectedFrameType(FrameType)
    case protocolError(String)
    case processExited
    case closed
    case noHandler(String)
    case cartridgeDied(String)
    case peerInvokeNotSupported(String)
    // Protocol violation errors (per-request)
    case duplicateStreamId(String)
    case chunkAfterStreamEnd(String)
    case unknownStreamId(String)
    case chunkMissingStreamId
    case streamAfterRequestEnd

    public var errorDescription: String? {
        switch self {
        case .handshakeFailed(let msg): return "Handshake failed: \(msg)"
        case .sendFailed(let msg): return "Send failed: \(msg)"
        case .receiveFailed(let msg): return "Receive failed: \(msg)"
        case .cartridgeError(let code, let message): return "Cartridge error [\(code)]: \(message)"
        case .unexpectedFrameType(let t): return "Unexpected frame type: \(t)"
        case .protocolError(let msg): return "Protocol error: \(msg)"
        case .processExited: return "Cartridge process exited unexpectedly"
        case .closed: return "Host is closed"
        case .noHandler(let cap): return "No handler found for cap: \(cap)"
        case .cartridgeDied(let msg): return "Cartridge died: \(msg)"
        case .duplicateStreamId(let streamId): return "Duplicate stream ID: \(streamId)"
        case .chunkAfterStreamEnd(let streamId): return "Chunk after stream end: \(streamId)"
        case .unknownStreamId(let streamId): return "Unknown stream ID: \(streamId)"
        case .chunkMissingStreamId: return "Chunk missing stream ID"
        case .streamAfterRequestEnd: return "Stream after request end"
        case .peerInvokeNotSupported(let cap): return "Peer invoke not supported for cap: \(cap)"
        }
    }
}

/// A response chunk from a cartridge
public struct ResponseChunk: Sendable {
    public let payload: Data
    public let seq: UInt64
    public let offset: UInt64?
    public let len: UInt64?
    public let isEof: Bool

    public init(payload: Data, seq: UInt64, offset: UInt64?, len: UInt64?, isEof: Bool) {
        self.payload = payload
        self.seq = seq
        self.offset = offset
        self.len = len
        self.isEof = isEof
    }
}

/// Response from a cartridge request (for convenience call() method)
public enum CartridgeResponse: Sendable {
    case single(Data)
    case streaming([ResponseChunk])

    public var finalPayload: Data? {
        switch self {
        case .single(let data): return data
        case .streaming(let chunks): return chunks.last?.payload
        }
    }

    public func concatenated() -> Data {
        switch self {
        case .single(let data): return data
        case .streaming(let chunks):
            var result = Data()
            for chunk in chunks {
                result.append(chunk.payload)
            }
            return result
        }
    }
}

// MARK: - Cartridge Process Info

/// Snapshot of a managed cartridge process, used for external monitoring
/// (e.g., memory pressure management).
public struct CartridgeProcessInfo: Sendable {
    /// Index of the cartridge in the host's cartridge list.
    public let cartridgeIndex: Int
    /// OS process ID.
    public let pid: pid_t
    /// Binary name (e.g. "ggufcartridge", "modelcartridge").
    public let name: String
    /// Whether the cartridge is currently running and responsive.
    public let running: Bool
    /// Cap URN strings this cartridge handles.
    public let caps: [String]
    /// Physical memory footprint in MB (self-reported by cartridge via heartbeat).
    /// This is `ri_phys_footprint` — the metric macOS jetsam uses for kill decisions.
    /// Updated every 30s when the cartridge responds to a heartbeat probe.
    public let memoryFootprintMb: UInt64
    /// Resident set size in MB (self-reported by cartridge via heartbeat).
    public let memoryRssMb: UInt64
}

// MARK: - Internal Types

/// Events from reader threads, delivered to the main run() loop.
private enum CartridgeEvent {
    case frame(cartridgeIdx: Int, frame: Frame)
    case death(cartridgeIdx: Int)
    case relayFrame(Frame)
    case relayClosed
    /// Periodic wakeup to republish runtime stats via RelayNotify.
    case statsRefresh
}

/// Composite routing key: (XID, RID) — uniquely identifies a request flow from relay.
/// XID is assigned by RelaySwitch, RID is the request's MessageId.
// Internal (not private) so the routing-GC contract test can
// construct keys for the seed helper. Production callers outside
// this file have no use for this type — it's still effectively
// host-internal — but `@testable import` requires non-private
// access for symbols a test uses through public/internal helpers.
internal struct RxidKey: Hashable {
    let xid: MessageId
    let rid: MessageId
}

/// Interval between heartbeat probes (seconds).
private let HEARTBEAT_INTERVAL: TimeInterval = 30.0

/// Maximum time to wait for a heartbeat response (seconds).
private let HEARTBEAT_TIMEOUT: TimeInterval = 10.0

/// A managed cartridge binary.
@available(macOS 10.15.4, iOS 13.4, *)
/// Why a cartridge was killed. Determines whether pending requests get ERR frames.
enum ShutdownReason {
    /// App is exiting or cartridge binary removed. No ERR frames — relay connection
    /// is closing anyway and there are no callers left to notify.
    case appExit
    /// OOM watchdog killed the cartridge while it was actively processing requests.
    /// Pending requests MUST get ERR frames with code "OOM_KILLED" so callers
    /// can fail fast instead of hanging forever.
    case oomKill
    /// Request was cancelled. Pending requests get ERR frames with code "CANCELLED".
    case cancelled
    /// Operator disabled this cartridge through the host UI. The
    /// process is killed immediately (yanked out of the system),
    /// pending requests get ERR frames with code "DISABLED" so
    /// callers can fail fast with an operator-recognisable reason
    /// (distinct from a request cancel and from an unexpected
    /// crash). Re-enabling requires a UI-driven operator action.
    case disabled
}

private class ManagedCartridge {
    /// Absolute path to the entry point binary (resolved from cartridge.json).
    let path: String
    /// Absolute path to the version directory containing cartridge.json.
    /// This is the anchor — the entry point is relative to this directory.
    let cartridgeDir: String
    var pid: pid_t?
    var stdoutHandle: FileHandle?
    var stderrHandle: FileHandle?
    /// Writer over the cartridge's stdin pipe. Sole owner of the
    /// stdin FileHandle's lifetime — no other field references that
    /// handle. Mutations of this property MUST happen under
    /// `writerLock`, and teardown MUST go through `writer.close()`
    /// before nil-ing the property; closing the underlying pipe by
    /// any other route would race a concurrent `writer.write(...)`
    /// onto a closed/recycled fd.
    var writer: FrameWriter?
    let writerLock = NSLock()
    var manifest: Data
    var limits: Limits
    /// Cap groups parsed from the cartridge's manifest. Single source
    /// of truth for what caps this cartridge handles — populated at
    /// discovery time (probe HELLO) and refreshed at spawn/HELLO. The
    /// per-group `adapterUrns` are also needed by the engine to
    /// register content-inspection adapters.
    var capGroups: [CapGroup]
    /// Flat de-duplicated cap-URN view derived from `capGroups`.
    /// Computed each call so the host never carries a parallel
    /// representation that can drift from the structural source.
    var capUrns: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for group in capGroups {
            for cap in group.caps {
                if seen.insert(cap.urn).inserted {
                    out.append(cap.urn)
                }
            }
        }
        return out
    }
    var running: Bool
    var helloFailed: Bool
    /// Positive lifecycle phase. Distinct from `attachmentError`:
    /// when `attachmentError != nil` this field is irrelevant
    /// (consumers must check the error first). When
    /// `attachmentError == nil`, the cartridge is dispatchable iff
    /// `lifecycle == .operational`. Defaults to `.discovered`
    /// (the safe sentinel — the host has not yet inspected /
    /// verified / attached this cartridge).
    var lifecycle: CartridgeLifecycle
    var readerThread: Thread?
    var pendingHeartbeats: [MessageId: Date]
    /// Last death error message (includes stderr if available). Used for ERR frames
    /// sent when attempting to write to a dead cartridge.
    var lastDeathMessage: String?
    /// Set before calling killProcess() to signal why the death occurred.
    /// `handleCartridgeDeath` checks this to determine ERR frame behavior:
    /// - `nil` → unexpected crash → ERR "CARTRIDGE_DIED"
    /// - `.oomKill` → OOM watchdog kill → ERR "OOM_KILLED"
    /// - `.appExit` → clean shutdown → no ERR frames
    var shutdownReason: ShutdownReason?
    /// Physical memory footprint in MB (self-reported via heartbeat response meta).
    var memoryFootprintMb: UInt64
    /// Resident set size in MB (self-reported via heartbeat response meta).
    var memoryRssMb: UInt64
    /// Unix timestamp seconds of the last heartbeat response. `nil` until
    /// the first successful heartbeat round-trip completes.
    var lastHeartbeatUnixSeconds: Int64?
    /// Number of times this cartridge has been respawned after death.
    var restartCount: UInt64

    init(path: String, cartridgeDir: String, capGroups: [CapGroup], lifecycle: CartridgeLifecycle = .discovered) {
        self.path = path
        self.cartridgeDir = cartridgeDir
        self.manifest = Data()
        self.limits = Limits()
        self.capGroups = capGroups
        self.running = false
        self.helloFailed = false
        self.lifecycle = lifecycle
        self.pendingHeartbeats = [:]
        self.lastDeathMessage = nil
        self.shutdownReason = nil
        self.memoryFootprintMb = 0
        self.memoryRssMb = 0
        self.lastHeartbeatUnixSeconds = nil
        self.restartCount = 0
        self.attachmentError = nil
    }

    /// Per-cartridge attachment failure, if any. Set by `recordAttachmentError` at
    /// the HELLO / identity / spawn failure sites, surfaced up through
    /// `installedCartridgeRecord()` into RelayNotify.
    var attachmentError: CartridgeAttachmentError?

    func installedCartridgeRecord() -> InstalledCartridgeRecord? {
        // Attached cartridges (no on-disk anchor) are pre-connected for
        // in-process / test use — they never hold an attachment error in
        // production. If a caller tags one with an attachment error it's a
        // programming mistake upstream, so fail hard rather than
        // manufacturing a placeholder id.
        guard !cartridgeDir.isEmpty else {
            if attachmentError != nil {
                fatalError("BUG: attached cartridge (no cartridgeDir) carries an attachment error — this code path has no resolvable identity")
            }
            return nil
        }
        guard var record = buildInstalledCartridgeRecord(
            cartridgeDir: cartridgeDir,
            attachmentError: attachmentError
        ) else {
            return nil
        }
        // Override the builder's default lifecycle (which is
        // `.discovered`, the safe sentinel) with the per-cartridge
        // tracked phase. The builder doesn't know about the host's
        // `ManagedCartridge` state — so we layer the host-side
        // truth on top here.
        record = InstalledCartridgeRecord(
            registryURL: record.registryURL,
            id: record.id,
            channel: record.channel,
            version: record.version,
            sha256: record.sha256,
            capGroups: record.capGroups,
            attachmentError: record.attachmentError,
            runtimeStats: record.runtimeStats,
            lifecycle: lifecycle
        )
        return record
    }

    /// Record a per-cartridge attachment failure and mark the cartridge as
    /// permanently broken (no on-demand respawn).
    ///
    /// Callers are expected to hold the host's `stateLock`.
    func recordAttachmentError(kind: CartridgeAttachmentErrorKind, message: String) {
        helloFailed = true
        attachmentError = CartridgeAttachmentError.now(kind: kind, message: message)
    }

    static func attached(manifest: Data, limits: Limits, capGroups: [CapGroup]) -> ManagedCartridge {
        let cartridge = ManagedCartridge(path: "", cartridgeDir: "", capGroups: capGroups)
        cartridge.manifest = manifest
        cartridge.limits = limits
        cartridge.running = true
        return cartridge
    }

    /// Kill the cartridge process if running. Waits for exit.
    func killProcess() {
        guard let p = pid else { return }
        kill(p, SIGTERM)
        var status: Int32 = 0
        let result = waitpid(p, &status, WNOHANG)
        if result == 0 {
            // Still running after SIGTERM
            Thread.sleep(forTimeInterval: 0.5)
            let result2 = waitpid(p, &status, WNOHANG)
            if result2 == 0 {
                kill(p, SIGKILL)
                _ = waitpid(p, &status, 0)
            }
        }
        pid = nil
    }

    /// Write a frame to this cartridge's stdin (thread-safe).
    /// Returns false if the cartridge is dead or write fails.
    @discardableResult
    func writeFrame(_ frame: Frame) -> Bool {
        writerLock.lock()
        defer { writerLock.unlock() }
        guard let w = writer else { return false }
        do {
            try w.write(frame)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - CartridgeHost

/// Multi-cartridge host runtime managing N cartridge processes.
///
/// Routes CBOR protocol frames between a relay connection (engine) and
/// individual cartridge processes. Handles HELLO handshake, heartbeat health
/// monitoring, and capability advertisement.
///
/// Usage:
/// ```swift
/// let host = CartridgeHost()
/// try host.attachCartridge(stdinHandle: cartridgeStdin, stdoutHandle: cartridgeStdout)
/// try host.run(relayRead: relayReadHandle, relayWrite: relayWriteHandle) { Data() }
/// ```
@available(macOS 10.15.4, iOS 13.4, *)
public final class CartridgeHost: @unchecked Sendable {

    // MARK: - Properties

    private static let log = OSLog(subsystem: "com.machinefabric.bifaci", category: "CartridgeHost")

    /// Managed cartridge binaries.
    private var cartridges: [ManagedCartridge] = []

    /// Routing: cap_urn -> cartridge index.
    private var capTable: [(String, Int)] = []

    /// List 1: OUTGOING_RIDS — tracks peer requests sent BY cartridges (RID → cartridge_idx).
    /// Used for death cleanup (ERR all pending peer requests when cartridge dies).
    /// Cleaned up only on cartridge death, never on terminal frames.
    /// Entries also drop on routing-table GC (see `gcRoutingTablesIfNeededLocked`).
    private var outgoingRids: [MessageId: Int] = [:]
    /// Parallel touched-at clock for `outgoingRids`. Same key set;
    /// values are `mach_absolute_time` ticks. Read by the GC to
    /// pick the oldest 25 % of entries when the table exceeds the
    /// soft watermark. Updated on insert and on every read that
    /// matches the entry (so a flow that's still seeing
    /// continuations stays "fresh"). Never read by the routing
    /// fast path — only the GC sees it.
    private var outgoingRidsTouched: [MessageId: UInt64] = [:]

    /// List 2: INCOMING_RXIDS — tracks incoming requests FROM relay ((XID, RID) → cartridge_idx).
    /// Routes continuation frames (STREAM_START/CHUNK/STREAM_END/END/ERR) to the correct cartridge.
    /// NEVER cleaned up on terminal frames — intentionally leaked until cartridge death.
    /// This avoids premature cleanup in self-loop peer request scenarios where the same RID
    /// appears in both outgoing and incoming maps.
    /// Bounded by `routingTableHardCap`; the GC evicts the
    /// least-recently-touched entries when the table exceeds the
    /// soft watermark.
    private var incomingRxids: [RxidKey: Int] = [:]
    private var incomingRxidsTouched: [RxidKey: UInt64] = [:]

    /// Tracks which incoming request spawned which outgoing peer RIDs.
    /// Maps parent (xid, rid) → list of child peer RIDs. Used for cancel cascade.
    /// Same GC discipline as `incomingRxids` — eviction here is
    /// keyed off the parent's touched-at, not the children's.
    private var incomingToPeerRids: [RxidKey: [MessageId]] = [:]
    private var incomingToPeerRidsTouched: [RxidKey: UInt64] = [:]

    /// Aggregate capabilities (serialized JSON manifest of all cartridge caps).
    private var _capabilities: Data = Data()

    /// State lock — protects cartridges, capTable, outgoingRids, incomingRxids, capabilities, closed.
    private let stateLock = NSLock()

    /// Outbound writer — writes frames to the relay (toward engine).
    private var outboundWriter: FrameWriter?
    private let outboundLock = NSLock()

    /// Max-seen seq per flow for cartridge-originated frames.
    /// Used to set seq on host-generated ERR frames (max_seen + 1).
    /// Protected by stateLock (same as outgoingRids/incomingRxids).
    /// Bounded by `routingTableHardCap` like the routing tables;
    /// stale entries (whose flow died without a terminal frame the
    /// cleanup path could see) are evicted oldest-first by the
    /// touched-at clock recorded in `outgoingMaxSeqTouched`.
    private var outgoingMaxSeq: [FlowKey: UInt64] = [:]
    private var outgoingMaxSeqTouched: [FlowKey: UInt64] = [:]

    /// Generous cap on the per-host routing tables. The
    /// "intentionally leaked until cartridge death" semantics on
    /// `incomingRxids` (and the parallel structure on
    /// `outgoingRids` / `incomingToPeerRids` / `outgoingMaxSeq`)
    /// means a cartridge that creates many distinct request IDs
    /// without dying will accumulate entries forever. In normal
    /// use we observed ~568 entries across a long session; 8192
    /// gives ~14× headroom before the GC fires, which is enough to
    /// cover bursts (PDF disbind→ForEach×N→LLM-call patterns) while
    /// still catching a runaway producer well before it grows
    /// memory by megabytes.
    private static let routingTableHardCap = 8192
    /// Soft watermark — when an insertion would push a table at or
    /// above this size, the GC fires and evicts the oldest 25% by
    /// `touchedAt`. Set to ~80 % of `hardCap` so the GC runs ahead
    /// of the cap rather than spinning right at it.
    private static let routingTableSoftWatermark = 6553
    /// Fraction of entries to drop in one GC pass. Lower values
    /// re-fire the GC more often (more log noise, more lock churn);
    /// higher values discard entries that may still be live (more
    /// likely to drop a continuation frame). 25 % is a balance —
    /// matches the watermark distance so two consecutive GC passes
    /// can carry the table back down to half-full if traffic
    /// briefly stays above the watermark.
    private static let routingTableGcEvictionFraction = 0.25

    /// Diagnostic counts for the routing-table GC. Reset to zero
    /// only when the host is constructed; expose via `os_log` each
    /// time the GC fires so a runaway producer is visible in the
    /// unified log without needing a custom subscriber.
    private var routingTableGcRunsTotal: UInt64 = 0
    private var routingTableGcEvictedTotal: UInt64 = 0

    /// Mark an entry in `incomingRxids` as touched right now.
    /// Caller MUST hold `stateLock`. Called both on insert and on
    /// every read that hits an existing key, so a still-streaming
    /// flow stays "fresh" for the GC.
    private func touchIncomingRxidLocked(_ key: RxidKey) {
        incomingRxidsTouched[key] = mach_absolute_time()
    }

    private func touchOutgoingRidLocked(_ rid: MessageId) {
        outgoingRidsTouched[rid] = mach_absolute_time()
    }

    private func touchIncomingToPeerRidsLocked(_ key: RxidKey) {
        incomingToPeerRidsTouched[key] = mach_absolute_time()
    }

    private func touchOutgoingMaxSeqLocked(_ key: FlowKey) {
        outgoingMaxSeqTouched[key] = mach_absolute_time()
    }

    /// Run the GC if any routing table has crossed its soft
    /// watermark. Caller MUST hold `stateLock`. Logs at `.error`
    /// (this is unusual enough that we want it visible by default
    /// in `log show --predicate 'subsystem == "com.machinefabric.bifaci"'`,
    /// even when the user hasn't enabled info-level capture).
    ///
    /// Each table is GC'd independently — they share the soft
    /// watermark and eviction fraction, but their key sets don't
    /// overlap so there's no benefit to ganging them. Eviction
    /// drops the parallel `*Touched` entry too, so the touched
    /// maps cannot grow past their primary tables.
    private func gcRoutingTablesIfNeededLocked() {
        if incomingRxids.count >= Self.routingTableSoftWatermark {
            gcRoutingTableLocked(
                tableName: "incomingRxids",
                primary: &incomingRxids,
                touched: &incomingRxidsTouched
            )
        }
        if outgoingRids.count >= Self.routingTableSoftWatermark {
            gcRoutingTableLocked(
                tableName: "outgoingRids",
                primary: &outgoingRids,
                touched: &outgoingRidsTouched
            )
        }
        if incomingToPeerRids.count >= Self.routingTableSoftWatermark {
            gcRoutingTableLocked(
                tableName: "incomingToPeerRids",
                primary: &incomingToPeerRids,
                touched: &incomingToPeerRidsTouched
            )
        }
        if outgoingMaxSeq.count >= Self.routingTableSoftWatermark {
            gcRoutingTableLocked(
                tableName: "outgoingMaxSeq",
                primary: &outgoingMaxSeq,
                touched: &outgoingMaxSeqTouched
            )
        }
    }

    /// Generic GC pass: drop the oldest
    /// `routingTableGcEvictionFraction` of `primary` (and its
    /// matching `touched` entries) by `touchedAt` ascending. Keys
    /// missing from `touched` are treated as oldest (touchedAt = 0)
    /// — they're either pre-touch state or buggy non-touched
    /// inserts; either way, evicting them is safer than letting
    /// them linger.
    private func gcRoutingTableLocked<K, V>(
        tableName: String,
        primary: inout [K: V],
        touched: inout [K: UInt64]
    ) {
        let beforeCount = primary.count
        let evictCount = max(1, Int(Double(beforeCount) * Self.routingTableGcEvictionFraction))
        // Build (key, touchedAt) pairs and pick the oldest N.
        // O(n log n) sort over `n = beforeCount`; with the cap at
        // 8192 this is < 100 µs even on a low-end Mac. Acceptable
        // for an event that should fire only when something is
        // genuinely off-the-rails.
        let candidates: [(K, UInt64)] = primary.keys.map { key in
            (key, touched[key] ?? 0)
        }
        let sorted = candidates.sorted { $0.1 < $1.1 }
        let victims = sorted.prefix(evictCount)
        for (key, _) in victims {
            primary.removeValue(forKey: key)
            touched.removeValue(forKey: key)
        }
        routingTableGcRunsTotal &+= 1
        routingTableGcEvictedTotal &+= UInt64(evictCount)

        os_log(.error, log: Self.log,
               "[routing-gc] table=%{public}@ before=%{public}d evicted=%{public}d after=%{public}d total_runs=%{public}llu total_evicted=%{public}llu — least-recently-touched entries dropped to keep the table under %{public}d. If this fires repeatedly, a cartridge or relay path is producing request IDs without ever terminating their flows.",
               tableName, beforeCount, evictCount, primary.count,
               routingTableGcRunsTotal, routingTableGcEvictedTotal,
               Self.routingTableHardCap)

        // If the primary still exceeds the hard cap after this
        // pass (extreme runaway), evict more aggressively until
        // we're back under the watermark. This is a guard, not a
        // hot path — the loop runs at most 1-2 times even at
        // pathological growth rates.
        while primary.count >= Self.routingTableHardCap {
            let extraEvict = max(1, primary.count - Self.routingTableSoftWatermark)
            let extras: [(K, UInt64)] = primary.keys.map { ($0, touched[$0] ?? 0) }
            let extrasSorted = extras.sorted { $0.1 < $1.1 }
            for (key, _) in extrasSorted.prefix(extraEvict) {
                primary.removeValue(forKey: key)
                touched.removeValue(forKey: key)
            }
            routingTableGcEvictedTotal &+= UInt64(extraEvict)
            os_log(.error, log: Self.log,
                   "[routing-gc] table=%{public}@ HARD CAP secondary pass evicted=%{public}d new_size=%{public}d",
                   tableName, extraEvict, primary.count)
        }
    }

    /// Cartridge events from reader threads.
    private var eventQueue: [CartridgeEvent] = []
    private let eventLock = NSLock()
    private let eventSemaphore = DispatchSemaphore(value: 0)

    /// Whether the host is closed.
    private var closed = false

    /// One-shot run() guard. Mirrors the Rust reference's
    /// `event_rx.take().expect("run() must only be called once")`
    /// (capdag/src/bifaci/host_runtime.rs:875). A `CartridgeHost` is
    /// scoped to a single relay session — callers that need a new
    /// session must construct a new host.
    private var hasRun = false
    private let hasRunLock = NSLock()

    /// Lifecycle observer. Set by callers that want to be notified
    /// when a cartridge transitions in/out of the running state
    /// (typically `CartridgeXPCService` to forward to its Mac-app
    /// client via reverse-XPC). Held weakly so the observer's
    /// lifecycle is owned by its real holder. Mirrors
    /// `CartridgeHostRuntime::observer` in the Rust reference.
    private weak var _observer: CartridgeHostObserver?
    private let observerLock = NSLock()

    public func setObserver(_ observer: CartridgeHostObserver?) {
        observerLock.lock()
        _observer = observer
        observerLock.unlock()
    }

    private var observer: CartridgeHostObserver? {
        observerLock.lock()
        let o = _observer
        observerLock.unlock()
        return o
    }

    // MARK: - Initialization

    /// Create a new cartridge host runtime.
    ///
    /// After creation, register cartridges with `registerCartridge()` or
    /// attach pre-connected cartridges with `attachCartridge()`, then call `run()`.
    public init() {}

    // MARK: - Cartridge Management

    /// Register a cartridge for on-demand spawning.
    ///
    /// The cartridge is NOT spawned immediately. It will be spawned on demand when
    /// a REQ arrives for one of its known caps.
    ///
    /// - Parameters:
    ///   - path: Path to the entry point binary (resolved from cartridge.json)
    ///   - cartridgeDir: Path to the version directory containing cartridge.json
    ///   - capGroups: Cap groups parsed from the cartridge's HELLO
    ///     manifest at discovery time. The flat cap-URN list is
    ///     derived from these groups when the host needs it (cap_table,
    ///     RelayNotify); we don't carry a parallel `knownCaps` field
    ///     that could drift.
    public func registerCartridge(path: String, cartridgeDir: String, capGroups: [CapGroup]) {
        stateLock.lock()
        let cartridge = ManagedCartridge(path: path, cartridgeDir: cartridgeDir, capGroups: capGroups)
        let idx = cartridges.count
        cartridges.append(cartridge)
        for cap in cartridge.capUrns {
            capTable.append((cap, idx))
        }
        rebuildCapabilities()
        stateLock.unlock()
    }

    /// Outcome of probing one cartridge directory during discovery.
    ///
    /// - `.inProgress`: cartridge is mid-lifecycle (`.inspecting`,
    ///   `.verifying`). No caps registered with the engine; UI shows
    ///   the in-progress badge. The host keeps an entry so the next
    ///   `syncDiscoveryOutcomes` call doesn't drop the cartridge as
    ///   "removed from disk".
    /// - `.discovered`: HELLO + manifest-parse succeeded; the host can
    ///   spawn it on demand. Lifecycle is `.operational` from the
    ///   moment this outcome is published.
    /// - `.failed`: Discovery-time probe failed (manifest invalid, HELLO
    ///   timed out, entry point missing, quarantined, etc.). The
    ///   cartridge is kept as a non-spawnable entry so the attachment
    ///   error surfaces through `RelayNotify`.
    public enum DiscoveredCartridgeOutcome {
        /// Cartridge is still progressing through the lifecycle —
        /// hash being computed, registry verdict pending, etc. No
        /// caps are registered with the engine while in this state;
        /// the host's `installed_cartridges` snapshot includes the
        /// cartridge with its current `lifecycle` so the UI can
        /// render the in-progress badge.
        case inProgress(
            path: String,
            cartridgeDir: String,
            lifecycle: CartridgeLifecycle
        )
        /// Discovery probe succeeded. `capGroups` carries the
        /// cartridge's full manifest structure (parsed from HELLO at
        /// probe time). The host derives the flat cap-URN list from
        /// these groups when needed (cap-table / RelayNotify).
        /// Lifecycle is implicitly `.operational`.
        case discovered(
            path: String,
            cartridgeDir: String,
            capGroups: [CapGroup]
        )
        case failed(
            path: String,
            cartridgeDir: String,
            kind: CartridgeAttachmentErrorKind,
            message: String
        )

        var path: String {
            switch self {
            case .inProgress(let path, _, _): return path
            case .discovered(let path, _, _): return path
            case .failed(let path, _, _, _): return path
            }
        }

        var cartridgeDir: String {
            switch self {
            case .inProgress(_, let dir, _): return dir
            case .discovered(_, let dir, _): return dir
            case .failed(_, let dir, _, _): return dir
            }
        }
    }

    /// Reconcile the host's cartridge state with the current on-disk truth,
    /// accepting both successfully discovered cartridges and discovery failures.
    ///
    /// After a rescan, the XPC service calls this with one outcome per
    /// cartridge version directory it walked. Failed outcomes are kept as
    /// non-spawnable entries so their attachment errors propagate through
    /// `RelayNotify` — the UI then knows *which* cartridge broke and *why*.
    ///
    /// Semantics:
    /// - **Same path, now discovered**: keep, update capGroups, clear any prior
    ///   attachment error.
    /// - **Same path, still failed**: update the attachment-error record with
    ///   the latest classification/message.
    /// - **Path gone**: kill the process if running and **remove** the
    ///   cartridge from the host's list entirely. The scan is authoritative
    ///   about what exists on disk; a cartridge absent from the scan is
    ///   uninstalled, not "failing attachment", so we drop it rather than
    ///   report a permanent error.
    /// - **New path**: append a fresh entry (spawnable or failed-record).
    ///
    /// Matches by **path**, not by cap set — URN strings are not stable across
    /// rescans (quoting and tag order may differ), but the binary path is.
    public func syncDiscoveryOutcomes(_ outcomes: [DiscoveredCartridgeOutcome]) {
        stateLock.lock()
        defer {
            rebuildCapabilities()
            stateLock.unlock()
        }

        // Build a lookup: path → index in `outcomes`.
        let outcomeByPath: [String: Int] = {
            var map = [String: Int]()
            for (i, outcome) in outcomes.enumerated() {
                map[outcome.path] = i
            }
            return map
        }()

        var matchedOutcomeIndices = Set<Int>()

        // Walk existing cartridges and reconcile with the new outcomes.
        // Collect "still present" cartridges; cartridges whose paths are
        // gone from the scan are dropped entirely (see doc comment).
        var retained: [ManagedCartridge] = []
        retained.reserveCapacity(cartridges.count)
        for cartridge in cartridges {
            if let outcomeIdx = outcomeByPath[cartridge.path] {
                matchedOutcomeIndices.insert(outcomeIdx)
                switch outcomes[outcomeIdx] {
                case .inProgress(_, _, let lifecycle):
                    // Mid-lifecycle update: cartridge is now in
                    // `.inspecting` / `.verifying` etc. Don't
                    // touch capGroups (they may already be empty
                    // — they will be populated when the host
                    // promotes this cartridge to `.discovered` /
                    // operational). Don't set helloFailed —
                    // in-progress is not a failure state. Clear
                    // any stale attachment error from a prior
                    // pass so the UI doesn't show the old reason
                    // alongside the in-progress badge.
                    cartridge.capGroups = []
                    cartridge.helloFailed = false
                    cartridge.attachmentError = nil
                    cartridge.lifecycle = lifecycle
                case .discovered(_, _, let capGroups):
                    // Clear any prior attachment error — the probe succeeded
                    // this time around. Update cap_groups so the host's
                    // RelayNotify carries them on the wire even before the
                    // cartridge is spawned for a real REQ. The flat
                    // cap-URN list rebuilds from these via `capUrns`.
                    cartridge.capGroups = capGroups
                    cartridge.helloFailed = false
                    cartridge.attachmentError = nil
                    cartridge.lifecycle = .operational
                case .failed(_, _, let kind, let message):
                    // Still broken on this pass — refresh the error so the
                    // latest detected reason propagates. Lifecycle is
                    // irrelevant per the mutual-exclusivity contract;
                    // keep the safe sentinel.
                    cartridge.capGroups = []
                    cartridge.recordAttachmentError(kind: kind, message: message)
                    cartridge.lifecycle = .discovered
                }
                retained.append(cartridge)
            } else {
                // Cartridge path no longer on disk — uninstalled or replaced.
                // Tear down any running process and drop the entry.
                cartridge.shutdownReason = .appExit
                cartridge.killProcess()
                cartridge.writerLock.lock()
                cartridge.writer?.close()
                cartridge.writer = nil
                cartridge.writerLock.unlock()
                cartridge.stdoutHandle = nil
                cartridge.stderrHandle = nil
                // Do NOT append to `retained` — this cartridge is gone.
            }
        }
        cartridges = retained

        // Append genuinely new outcomes (path not yet tracked by the host).
        for (i, outcome) in outcomes.enumerated() where !matchedOutcomeIndices.contains(i) {
            switch outcome {
            case .inProgress(let path, let dir, let lifecycle):
                let cartridge = ManagedCartridge(
                    path: path, cartridgeDir: dir, capGroups: [], lifecycle: lifecycle
                )
                cartridges.append(cartridge)
            case .discovered(let path, let dir, let capGroups):
                let cartridge = ManagedCartridge(
                    path: path, cartridgeDir: dir, capGroups: capGroups, lifecycle: .operational
                )
                cartridges.append(cartridge)
            case .failed(let path, let dir, let kind, let message):
                let cartridge = ManagedCartridge(
                    path: path, cartridgeDir: dir, capGroups: []
                )
                cartridge.recordAttachmentError(kind: kind, message: message)
                cartridges.append(cartridge)
            }
        }

        // Rebuild capTable from scratch — covers new, updated, and removed
        // cartridges. Only `.operational` cartridges contribute caps;
        // `.discovered` / `.inspecting` / `.verifying` cartridges have
        // capGroups == [] anyway (the host populates capGroups only on
        // `.discovered`/`.operational` outcomes), but we filter
        // explicitly so a future code path that pre-populates capGroups
        // can't accidentally expose an un-verified cartridge for
        // dispatch. Failed cartridges (helloFailed) also contribute no
        // caps. The flat cap-URN list comes from each cartridge's
        // `capUrns` view over its `capGroups` (the source of truth).
        capTable.removeAll()
        for (idx, cartridge) in cartridges.enumerated()
            where !cartridge.helloFailed && cartridge.lifecycle == .operational
        {
            for cap in cartridge.capUrns {
                capTable.append((cap, idx))
            }
        }
    }

    /// Attach a pre-connected cartridge (already running, ready for handshake).
    ///
    /// Performs HELLO handshake synchronously. Extracts manifest and caps.
    /// Starts a reader thread for this cartridge.
    ///
    /// - Parameters:
    ///   - stdinHandle: FileHandle to write to the cartridge's stdin
    ///   - stdoutHandle: FileHandle to read from the cartridge's stdout
    /// - Returns: Cartridge index
    /// - Throws: CartridgeHostError if handshake fails
    @discardableResult
    public func attachCartridge(stdinHandle: FileHandle, stdoutHandle: FileHandle) throws -> Int {
        let reader = FrameReader(handle: stdoutHandle)
        let writer = FrameWriter(handle: stdinHandle)

        // Perform HELLO handshake
        let ourLimits = Limits()
        let ourHello = Frame.hello(limits: ourLimits)
        try writer.write(ourHello)

        guard let theirHello = try reader.read() else {
            throw CartridgeHostError.handshakeFailed("Cartridge closed connection before HELLO")
        }
        guard theirHello.frameType == .hello else {
            throw CartridgeHostError.handshakeFailed("Expected HELLO, got \(theirHello.frameType)")
        }
        guard let manifest = theirHello.helloManifest else {
            throw CartridgeHostError.handshakeFailed("Cartridge HELLO missing required manifest")
        }

        // Protocol v2: All three limit fields are REQUIRED
        guard let theirMaxFrame = theirHello.helloMaxFrame else {
            throw CartridgeHostError.handshakeFailed("Protocol violation: HELLO missing max_frame")
        }
        guard let theirMaxChunk = theirHello.helloMaxChunk else {
            throw CartridgeHostError.handshakeFailed("Protocol violation: HELLO missing max_chunk")
        }
        guard let theirMaxReorderBuffer = theirHello.helloMaxReorderBuffer else {
            throw CartridgeHostError.handshakeFailed("Protocol violation: HELLO missing max_reorder_buffer (required in protocol v2)")
        }

        let negotiatedLimits = Limits(
            maxFrame: min(ourLimits.maxFrame, theirMaxFrame),
            maxChunk: min(ourLimits.maxChunk, theirMaxChunk),
            maxReorderBuffer: min(ourLimits.maxReorderBuffer, theirMaxReorderBuffer)
        )
        writer.setLimits(negotiatedLimits)
        reader.setLimits(negotiatedLimits)

        // Parse cap groups from manifest (validates CAP_IDENTITY presence)
        let capGroups = try Self.extractCapGroups(from: manifest)
        let capUrns = capGroups.flatMap { $0.caps.map { $0.urn } }

        // Perform identity verification - send nonce, expect echo
        try Self.verifyCartridgeIdentity(reader: reader, writer: writer)

        // Create managed cartridge. The writer is the sole owner of
        // the stdin handle from this point — nothing else holds a
        // reference to it.
        let cartridge = ManagedCartridge.attached(manifest: manifest, limits: negotiatedLimits, capGroups: capGroups)
        cartridge.stdoutHandle = stdoutHandle
        cartridge.writerLock.lock()
        cartridge.writer = writer
        cartridge.writerLock.unlock()

        stateLock.lock()
        let idx = cartridges.count
        cartridges.append(cartridge)
        for cap in capUrns {
            capTable.append((cap, idx))
        }
        rebuildCapabilities()
        let observerPid = cartridge.pid
        let observerName = (cartridge.path as NSString).lastPathComponent
        let observerCaps = capUrns
        stateLock.unlock()

        // Start reader thread for this cartridge
        startCartridgeReaderThread(cartridgeIdx: idx, reader: reader)

        // Notify lifecycle observer (XPC reverse-callback bridge, etc.).
        observer?.cartridgeSpawned(
            cartridgeIndex: idx,
            pid: observerPid,
            name: observerName,
            caps: observerCaps
        )

        return idx
    }

    /// Get the aggregate capabilities manifest (JSON-encoded list of all cartridge caps).
    public var capabilities: Data {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _capabilities
    }

    /// Find which cartridge handles a given cap URN.
    ///
    /// Uses exact string match first, then URN-level accepts() for semantic matching.
    ///
    /// - Parameter capUrn: The cap URN to look up
    /// - Returns: Cartridge index, or nil if no cartridge handles this cap
    public func findCartridgeForCap(_ capUrn: String) -> Int? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return findCartridgeForCapLocked(capUrn)
    }

    /// Internal: find cartridge for cap (must hold stateLock).
    ///
    /// Uses `isDispatchable(provider, request)` to find cartridges that can
    /// legally handle the request, then ranks by specificity.
    ///
    /// Ranking prefers:
    /// 1. Equivalent matches (distance 0)
    /// 2. More specific providers (positive distance) - refinements
    /// 3. More generic providers (negative distance) - fallbacks
    private func findCartridgeForCapLocked(_ capUrn: String) -> Int? {
        guard let requestUrn = try? CSCapUrn.fromString(capUrn) else { return nil }

        let requestSpecificity = Int(requestUrn.specificity())
        var matches: [(cartridgeIdx: Int, signedDistance: Int)] = []

        for (registeredCap, cartridgeIdx) in capTable {
            if let registeredUrn = try? CSCapUrn.fromString(registeredCap) {
                if registeredUrn.isDispatchable(requestUrn) {
                    let specificity = Int(registeredUrn.specificity())
                    let signedDistance = specificity - requestSpecificity
                    matches.append((cartridgeIdx, signedDistance))
                }
            }
        }

        guard !matches.isEmpty else { return nil }

        // Ranking: prefer equivalent (0), then more specific (+), then more generic (-)
        matches.sort { a, b in
            let (_, distA) = a
            let (_, distB) = b
            if distA >= 0 && distB < 0 { return true }
            if distA < 0 && distB >= 0 { return false }
            return abs(distA) < abs(distB)
        }

        return matches.first?.cartridgeIdx
    }

    // MARK: - Main Run Loop

    /// Main run loop. Reads frames from the relay, routes to cartridges.
    /// Cartridge reader threads forward cartridge frames to the relay.
    ///
    /// Blocks until the relay closes or a fatal error occurs.
    ///
    /// - Parameters:
    ///   - relayRead: FileHandle to read frames from (relay/engine side)
    ///   - relayWrite: FileHandle to write frames to (relay/engine side)
    ///   - resourceFn: Callback to get current system resource state
    /// - Throws: CartridgeHostError on fatal errors
    public func run(
        relayRead: FileHandle,
        relayWrite: FileHandle,
        resourceFn: @escaping () -> Data
    ) throws {
        // One-shot enforcement — mirrors the Rust reference. A
        // second invocation would race with the first on
        // `eventQueue`/`outboundWriter`/`statsTimer` and silently
        // accumulate orphaned frames; we'd rather crash loud at the
        // misuse site than leak GBs of NSConcreteData.
        hasRunLock.lock()
        precondition(!hasRun, "CartridgeHost.run() may only be called once per host instance — construct a new CartridgeHost for a new relay session")
        hasRun = true
        hasRunLock.unlock()

        outboundLock.lock()
        outboundWriter = FrameWriter(handle: relayWrite)
        outboundLock.unlock()

        // Send initial RelayNotify with capabilities from any already-attached cartridges.
        // Cartridges attached before run() was called won't have sent their RelayNotify yet.
        stateLock.lock()
        rebuildCapabilities()
        stateLock.unlock()

        // Start relay reader thread — feeds into the same event queue as cartridge readers
        let relayReader = FrameReader(handle: relayRead)
        let relayThread = Thread { [weak self] in
            // See startCartridgeReaderThread for why we wrap each
            // iteration in an autoreleasepool — same root cause:
            // NSConcreteFileHandle.readDataOfLength returns
            // autoreleased NSConcreteData and a bare Thread {}
            // closure does not provide an outer pool to drain them.
            while true {
                let shouldBreak: Bool = autoreleasepool {
                    do {
                        guard let frame = try relayReader.read() else {
                            self?.pushEvent(.relayClosed)
                            return true
                        }
                        self?.pushEvent(.relayFrame(frame))
                        return false
                    } catch {
                        os_log(.error, log: Self.log, "[run.relayReader] read error: %{public}@ — pushing relayClosed", String(describing: error))
                        self?.pushEvent(.relayClosed)
                        return true
                    }
                }
                if shouldBreak { break }
            }
        }
        relayThread.name = "CartridgeHost.relay"
        relayThread.start()

        // Runtime-stats refresh cadence. Request counts and memory change
        // continuously; structural changes (spawn/death) already trigger a
        // RelayNotify synchronously via `rebuildCapabilities`, so this timer
        // only needs to cover the continuous signals. The relay peer's
        // watch-channel drops no-op frames when no stat actually changed.
        let statsTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        statsTimer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2))
        statsTimer.setEventHandler { [weak self] in
            self?.pushEvent(.statsRefresh)
        }
        statsTimer.resume()

        // Heartbeat probe timer — sends a heartbeat REQ to every
        // running cartridge every 10s. Each cartridge replies with
        // a heartbeat carrying its self-reported memory footprint
        // in `meta` (footprint_mb / rss_mb). The host's
        // .heartbeat handler stores those into
        // `cartridge.memoryFootprintMb` / `memoryRssMb`. Without
        // this timer no heartbeats ever fire, leaving the
        // self-report channel dormant — which was why the cartridge
        // detail view's resident/CPU columns stayed at zero even
        // after the autoreleasepool fix.
        //
        // 10s cadence is shorter than the Rust reference's 30s
        // because we're using the same heartbeat for live UI stats,
        // not just liveness. Cost per probe: one frame in, one
        // frame out, both ~64 B + meta — negligible compared to
        // the 2s statsRefresh rebuild.
        let heartbeatTimer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        heartbeatTimer.schedule(deadline: .now() + .seconds(10), repeating: .seconds(10))
        heartbeatTimer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.stateLock.lock()
            let snapshot: [(idx: Int, writer: FrameWriter)] = self.cartridges.enumerated().compactMap { (idx, c) in
                guard c.running, let writer = c.writer else { return nil }
                return (idx, writer)
            }
            self.stateLock.unlock()
            for entry in snapshot {
                let probeId = MessageId.newUUID()
                self.stateLock.lock()
                self.cartridges[entry.idx].pendingHeartbeats[probeId] = Date()
                self.stateLock.unlock()
                let frame = Frame.heartbeat(id: probeId)
                do {
                    try entry.writer.write(frame)
                } catch {
                    os_log(.error, log: Self.log,
                           "Failed to write heartbeat probe to cartridge %{public}d: %{public}@",
                           entry.idx, String(describing: error))
                    self.stateLock.lock()
                    self.cartridges[entry.idx].pendingHeartbeats.removeValue(forKey: probeId)
                    self.stateLock.unlock()
                }
            }
        }
        heartbeatTimer.resume()

        // On exit (clean or via thrown error), match the Rust
        // reference (capdag/src/bifaci/host_runtime.rs:989
        // `self.kill_all_cartridges().await`): kill every managed
        // cartridge so processes don't outlive the relay session,
        // and drop the per-session outboundWriter so any late frame
        // pushed by an in-flight cartridge reader thread fails fast
        // (visible at sendToRelay's nil-writer log) instead of being
        // silently buffered against a stale FD.
        defer {
            statsTimer.cancel()
            heartbeatTimer.cancel()
            killAllCartridgesOnRunExit()
            // Close the per-session outbound writer atomically with
            // dropping the reference. This transitions the writer to
            // its closed state so any late frame pushed by an
            // in-flight cartridge reader thread fails fast with
            // `FrameError.ioError("writer closed")` instead of being
            // silently buffered (or worse, written into the recycled
            // FD of a different relay session).
            outboundLock.lock()
            outboundWriter?.close()
            outboundWriter = nil
            outboundLock.unlock()
        }

        // Main loop: wait for events from any source (relay or cartridges).
        //
        // Per-iteration `autoreleasepool` is essential here: this loop
        // runs on a bare `Thread { }` started from
        // `CartridgeXPCServiceImplementation.handleEngineConnection`,
        // and the dispatch into handleRelayFrame / handleCartridgeFrame
        // / sendToRelay touches Foundation calls (FileHandle writes,
        // CBOR encode allocations) that emit autoreleased objects.
        // Without an inner pool those would pile up for the lifetime
        // of the relay session and produce the same multi-GB heap
        // growth we saw in the cartridge stdout reader. Same fix
        // class as the reader threads.
        while true {
            eventSemaphore.wait()

            eventLock.lock()
            guard !eventQueue.isEmpty else {
                eventLock.unlock()
                continue
            }
            let event = eventQueue.removeFirst()
            eventLock.unlock()

            let shouldExit: Bool = autoreleasepool {
                switch event {
                case .relayFrame(let frame):
                    handleRelayFrame(frame)
                    return false
                case .relayClosed:
                    // Clean shutdown
                    stateLock.lock()
                    closed = true
                    stateLock.unlock()
                    return true
                case .frame(let cartridgeIdx, let frame):
                    handleCartridgeFrame(cartridgeIdx: cartridgeIdx, frame: frame)
                    return false
                case .death(let cartridgeIdx):
                    handleCartridgeDeath(cartridgeIdx: cartridgeIdx)
                    return false
                case .statsRefresh:
                    // Re-emit RelayNotify only when at least one cartridge is
                    // running, so an idle host doesn't burn bandwidth. Runtime
                    // stats for non-running cartridges change only at
                    // spawn/death boundaries which already trigger a rebuild.
                    stateLock.lock()
                    let anyRunning = cartridges.contains { $0.running }
                    stateLock.unlock()
                    if anyRunning {
                        stateLock.lock()
                        rebuildCapabilities()
                        stateLock.unlock()
                    }
                    return false
                }
            }
            if shouldExit { return }
        }
    }

    /// Kill every managed cartridge on `run()` exit.
    ///
    /// Mirrors the Rust reference's `kill_all_cartridges` invoked at
    /// the end of `run()`. Distinct from `close()` (which sets the
    /// host's `closed` flag and pushes a `relayClosed` event to wake
    /// the loop) — by the time we get here the loop has already
    /// returned, so we only need to terminate the child processes
    /// and tear down their I/O. Idempotent.
    private func killAllCartridgesOnRunExit() {
        var deathNotifications: [(idx: Int, pid: pid_t?, name: String)] = []
        stateLock.lock()
        for (idx, cartridge) in cartridges.enumerated() {
            // Close the writer first — that closes the stdin handle
            // and atomically transitions the writer to the closed
            // state, so any racing `writeFrame()` returns
            // `FrameError.ioError("writer closed")` cleanly instead
            // of writing into a recycled fd.
            cartridge.writerLock.lock()
            cartridge.writer?.close()
            cartridge.writer = nil
            cartridge.writerLock.unlock()

            if let stderr = cartridge.stderrHandle {
                try? stderr.close()
                cartridge.stderrHandle = nil
            }
            let wasRunning = cartridge.running
            let pidAtDeath = cartridge.pid
            let name = (cartridge.path as NSString).lastPathComponent
            cartridge.shutdownReason = .appExit
            cartridge.killProcess()
            cartridge.running = false
            if wasRunning {
                deathNotifications.append((idx: idx, pid: pidAtDeath, name: name))
            }
        }
        stateLock.unlock()

        if let obs = observer {
            for note in deathNotifications {
                obs.cartridgeDied(cartridgeIndex: note.idx, pid: note.pid, name: note.name)
            }
        }
    }

    // MARK: - Relay Frame Handling (Engine -> Cartridge)

    /// Handle a frame received from the relay (engine side).
    ///
    /// All relay frames MUST have XID (assigned by RelaySwitch).
    /// Routes incoming REQs to cartridges by cap URN, continuation frames by (XID, RID).
    /// NEVER cleans up incomingRxids on terminal frames — intentionally leaked until cartridge death.
    private func handleRelayFrame(_ frame: Frame) {
        if frame.frameType != .log {
            os_log(.debug, log: Self.log, "[handleRelayFrame] %{public}@ id=%{public}@ xid=%{public}@", String(describing: frame.frameType), String(describing: frame.id), String(describing: frame.routingId))
        }
        switch frame.frameType {
        case .req:
            // REQ from relay MUST have XID
            guard let xid = frame.routingId else {
                sendToRelay(Frame.err(id: frame.id, code: "PROTOCOL_ERROR", message: "REQ from relay missing XID"))
                return
            }

            guard let capUrn = frame.cap else {
                var err = Frame.err(id: frame.id, code: "INVALID_REQUEST", message: "REQ missing cap URN")
                err.routingId = xid
                sendToRelay(err)
                return
            }

            // Check for target_cartridge in meta — if present, route directly
            let targetCartridgeId: String? = frame.meta.flatMap { meta in
                if case let .utf8String(s) = meta["target_cartridge"] {
                    return s
                }
                return nil
            }

            stateLock.lock()
            let cartridgeIdx: Int
            if let targetId = targetCartridgeId {
                // Direct routing by cartridge identity
                if let foundIdx = cartridges.firstIndex(where: {
                    $0.installedCartridgeRecord()?.id == targetId
                }) {
                    if cartridges[foundIdx].helloFailed {
                        stateLock.unlock()
                        var err = Frame.err(id: frame.id, code: "CARTRIDGE_UNAVAILABLE",
                                           message: "Cartridge '\(targetId)' failed handshake and cannot be spawned")
                        err.routingId = xid
                        sendToRelay(err)
                        return
                    }
                    cartridgeIdx = foundIdx
                } else {
                    stateLock.unlock()
                    var err = Frame.err(id: frame.id, code: "CARTRIDGE_NOT_FOUND",
                                       message: "Cartridge '\(targetId)' not found on this host")
                    err.routingId = xid
                    sendToRelay(err)
                    return
                }
            } else {
                // Standard cap-based dispatch
                guard let foundIdx = findCartridgeForCapLocked(capUrn) else {
                    stateLock.unlock()
                    var err = Frame.err(id: frame.id, code: "NO_HANDLER", message: "No cartridge handles cap: \(capUrn)")
                    err.routingId = xid
                    sendToRelay(err)
                    return
                }
                cartridgeIdx = foundIdx
            }
            let needsSpawn = !cartridges[cartridgeIdx].running && !cartridges[cartridgeIdx].helloFailed
            stateLock.unlock()

            // Spawn on demand if registered but not running
            if needsSpawn {
                do {
                    try spawnCartridge(at: cartridgeIdx)
                } catch {
                    var err = Frame.err(id: frame.id, code: "SPAWN_FAILED", message: "Failed to spawn cartridge: \(error.localizedDescription)")
                    err.routingId = xid
                    sendToRelay(err)
                    return
                }
            }

            // Record in INCOMING_RXIDS: (XID, RID) → cartridge_idx
            let key = RxidKey(xid: xid, rid: frame.id)
            stateLock.lock()
            incomingRxids[key] = cartridgeIdx
            touchIncomingRxidLocked(key)
            gcRoutingTablesIfNeededLocked()
            let cartridge = cartridges[cartridgeIdx]
            stateLock.unlock()

            os_log(.debug, log: Self.log, "[handleRelayFrame] REQ dispatched to cartridge %d cap=%{public}@ xid=%{public}@ rid=%{public}@", cartridgeIdx, String(describing: frame.cap), String(describing: xid), String(describing: frame.id))
            if !cartridge.writeFrame(frame) {
                // Cartridge is dead — send ERR with XID and clean up
                let deathMsg = cartridge.lastDeathMessage ?? "Cartridge exited while processing request"
                var err = Frame.err(id: frame.id, code: "CARTRIDGE_DIED", message: deathMsg)
                err.routingId = xid
                sendToRelay(err)
                stateLock.lock()
                incomingRxids.removeValue(forKey: key)
                incomingRxidsTouched.removeValue(forKey: key)
                stateLock.unlock()
            }

        case .streamStart, .chunk, .streamEnd, .end, .err:
            // Continuation from relay MUST have XID
            guard let xid = frame.routingId else {
                fputs("[CartridgeHost] Protocol error: continuation from relay missing XID\n", stderr)
                return
            }

            let key = RxidKey(xid: xid, rid: frame.id)

            // Route by (XID, RID) to the mapped cartridge
            stateLock.lock()
            var cartridgeIdx = incomingRxids[key]
            if cartridgeIdx != nil {
                // Hit on incoming side — keep this entry "fresh" so
                // the GC doesn't evict it while continuations are
                // still arriving.
                touchIncomingRxidLocked(key)
            } else {
                // Not an incoming engine request — check if it's a peer response.
                // outgoingRids[RID] tracks which cartridge made a peer request with this RID.
                cartridgeIdx = outgoingRids[frame.id]
                if cartridgeIdx != nil {
                    touchOutgoingRidLocked(frame.id)
                }
            }
            guard let resolvedIdx = cartridgeIdx else {
                stateLock.unlock()
                // Already cleaned up (e.g., cartridge died, death handler sent ERR)
                return
            }
            let cartridge = cartridges[resolvedIdx]
            stateLock.unlock()

            // If the cartridge is dead, send ERR to engine with XID and clean up
            if !cartridge.writeFrame(frame) {
                let flowKey = FlowKey(rid: frame.id, xid: xid)
                stateLock.lock()
                let nextSeq = (outgoingMaxSeq.removeValue(forKey: flowKey) ?? 0) + 1
                outgoingMaxSeqTouched.removeValue(forKey: flowKey)
                outgoingRids.removeValue(forKey: frame.id)
                outgoingRidsTouched.removeValue(forKey: frame.id)
                incomingRxids.removeValue(forKey: key)
                incomingRxidsTouched.removeValue(forKey: key)
                stateLock.unlock()
                let deathMsg = cartridge.lastDeathMessage ?? "Cartridge exited while processing request"
                var err = Frame.err(id: frame.id, code: "CARTRIDGE_DIED", message: deathMsg)
                err.routingId = xid
                err.seq = nextSeq
                sendToRelay(err)
                return
            }

            // NOTE: Do NOT cleanup incomingRxids here!
            // Frames arrive asynchronously — END can arrive before StreamStart/Chunk.
            // We can't know when "all frames for (XID, RID) have arrived" without full stream tracking.
            // Accept the leak: entries cleaned up on cartridge death.

        case .log:
            // LOG frames from peer responses — route back to the cartridge that
            // made the peer request. Identified by outgoingRids[RID].
            stateLock.lock()
            let cartridgeIdx = outgoingRids[frame.id]
            if cartridgeIdx != nil {
                touchOutgoingRidLocked(frame.id)
            }
            stateLock.unlock()

            if let idx = cartridgeIdx {
                let cartridge = cartridges[idx]
                let _ = cartridge.writeFrame(frame)
            }
            // If not a peer response LOG, ignore silently (e.g., stale routing)

        case .hello, .heartbeat:
            // These should never arrive from the engine through the relay
            fputs("[CartridgeHost] Protocol error: \(frame.frameType) from relay\n", stderr)

        case .cancel:
            // Cancel from relay — route to the cartridge handling this request.
            guard let xid = frame.routingId else {
                fputs("[CartridgeHost] Cancel frame missing XID — ignoring\n", stderr)
                return
            }
            let rid = frame.id
            let key = RxidKey(xid: xid, rid: rid)
            let forceKill = frame.forceKill ?? false

            stateLock.lock()
            guard let cartridgeIdx = incomingRxids[key] else {
                stateLock.unlock()
                fputs("[CartridgeHost] Cancel for unknown request (\(xid), \(rid)) — ignoring\n", stderr)
                return
            }
            // Touch on cancel-route too — the cancel itself is
            // routing activity for this entry, and the cooperative
            // cancel below may cause more frames to flow on this
            // (XID, RID) before the cartridge actually exits.
            touchIncomingRxidLocked(key)

            if forceKill {
                // Force kill: set shutdown reason and kill the process
                fputs("[CartridgeHost] Cancel force_kill=true for cartridge \(cartridgeIdx) rid=\(rid)\n", stderr)
                cartridges[cartridgeIdx].shutdownReason = .cancelled
                let pid = cartridges[cartridgeIdx].pid
                stateLock.unlock()
                if let pid = pid {
                    kill(pid, SIGKILL)
                }
            } else {
                // Cooperative cancel: forward Cancel frame to the cartridge
                fputs("[CartridgeHost] Cancel cooperative for cartridge \(cartridgeIdx) rid=\(rid)\n", stderr)
                let cartridge = cartridges[cartridgeIdx]
                stateLock.unlock()
                let _ = cartridge.writeFrame(frame)

                // Also cascade: send Cancel to relay for each peer call spawned by this request
                stateLock.lock()
                if let peerRids = incomingToPeerRids[key] {
                    touchIncomingToPeerRidsLocked(key)
                    stateLock.unlock()
                    for peerRid in peerRids {
                        fputs("[CartridgeHost] Cascading Cancel to peer call rid=\(peerRid)\n", stderr)
                        let cancel = Frame.cancel(targetRid: peerRid, forceKill: false)
                        sendToRelay(cancel)
                    }
                } else {
                    stateLock.unlock()
                }
            }

        case .relayNotify, .relayState:
            // Relay frames should be intercepted by the relay layer, never reach here
            fputs("[CartridgeHost] Protocol error: relay frame \(frame.frameType) reached host\n", stderr)
        }
    }

    // MARK: - Cartridge Frame Handling (Cartridge -> Engine)

    /// Handle a frame received from a cartridge.
    ///
    /// REQ frames register in outgoingRids (peer invoke tracking).
    /// All frames track max-seen seq per FlowKey for host-generated ERR frames.
    /// All other frames are forwarded to relay as-is — no routing decisions needed
    /// (there's only one relay destination).
    private func handleCartridgeFrame(cartridgeIdx: Int, frame: Frame) {
        if frame.frameType != .log {
            os_log(.debug, log: Self.log, "[handleCartridgeFrame] cartridge=%d %{public}@ id=%{public}@ xid=%{public}@", cartridgeIdx, String(describing: frame.frameType), String(describing: frame.id), String(describing: frame.routingId))
        }
        switch frame.frameType {
        case .hello:
            // HELLO should be consumed during handshake, never during run
            fputs("[CartridgeHost] Protocol error: HELLO from cartridge \(cartridgeIdx) during run\n", stderr)

        case .heartbeat:
            // Handle heartbeat locally, never forward
            stateLock.lock()
            let cartridge = cartridges[cartridgeIdx]
            let wasOurs = cartridge.pendingHeartbeats.removeValue(forKey: frame.id) != nil

            if wasOurs {
                // Response to our health probe — cartridge is alive.
                // Extract self-reported memory from heartbeat response meta.
                if let meta = frame.meta {
                    if case .unsignedInt(let v) = meta["footprint_mb"] {
                        cartridge.memoryFootprintMb = v
                    }
                    if case .unsignedInt(let v) = meta["rss_mb"] {
                        cartridge.memoryRssMb = v
                    }
                }
                // Stamp the round-trip completion timestamp so runtime-stats
                // snapshots can surface heartbeat age to the UI.
                cartridge.lastHeartbeatUnixSeconds = Int64(Date().timeIntervalSince1970)
            }
            stateLock.unlock()

            if !wasOurs {
                // Cartridge-initiated heartbeat — respond
                cartridge.writeFrame(Frame.heartbeat(id: frame.id))
            }

        case .relayNotify, .relayState:
            // Cartridges must never send relay frames
            fputs("[CartridgeHost] Protocol error: relay frame \(frame.frameType) from cartridge \(cartridgeIdx)\n", stderr)

        case .req:
            // Cartridge peer invoke — record in OUTGOING_RIDS and track max-seen seq.
            // Cartridges MUST NOT send XID (that's a relay-level concept).
            stateLock.lock()
            outgoingRids[frame.id] = cartridgeIdx
            touchOutgoingRidLocked(frame.id)
            let flowKey = FlowKey.fromFrame(frame)
            outgoingMaxSeq[flowKey] = frame.seq
            touchOutgoingMaxSeqLocked(flowKey)

            // Track parent→child peer call mapping for cancel cascade
            if let meta = frame.meta, let parentRidCbor = meta["parent_rid"] {
                let parentRid: MessageId?
                switch parentRidCbor {
                case .byteString(let bytes) where bytes.count == 16:
                    parentRid = .uuid(Data(bytes))
                case .unsignedInt(let n):
                    parentRid = .uint(n)
                default:
                    parentRid = nil
                }
                if let parentRid = parentRid {
                    // Find the parent's incoming key
                    let parentKey = incomingRxids.first(where: { $0.key.rid == parentRid })?.key
                    if let pk = parentKey {
                        incomingToPeerRids[pk, default: []].append(frame.id)
                        touchIncomingToPeerRidsLocked(pk)
                    }
                }
            }
            // Run the GC after recording — covers all four
            // tables touched in this branch.
            gcRoutingTablesIfNeededLocked()
            stateLock.unlock()
            sendToRelay(frame)

        default:
            // Everything else: forward as-is to relay.
            // Track max-seen seq for flow, clean up on terminal.
            if frame.isFlowFrame() {
                let flowKey = FlowKey.fromFrame(frame)
                stateLock.lock()
                let isTerminal = frame.frameType == .end || frame.frameType == .err
                if isTerminal {
                    outgoingMaxSeq.removeValue(forKey: flowKey)
                    outgoingMaxSeqTouched.removeValue(forKey: flowKey)
                } else {
                    outgoingMaxSeq[flowKey] = frame.seq
                    touchOutgoingMaxSeqLocked(flowKey)
                    gcRoutingTablesIfNeededLocked()
                }
                stateLock.unlock()
            }
            sendToRelay(frame)
        }
    }

    // MARK: - Cartridge Death Handling

    /// Handle a cartridge death (reader thread detected EOF/error).
    ///
    /// Three cases based on `shutdownReason`:
    /// 1. **`nil`** (unexpected death): Genuine crash. Send ERR "CARTRIDGE_DIED"
    ///    for all pending requests, store death message.
    /// 2. **`.oomKill`**: OOM watchdog killed the cartridge while it was
    ///    actively processing. Send ERR "OOM_KILLED" for all pending requests
    ///    so callers fail fast instead of hanging.
    /// 3. **`.appExit`**: Clean shutdown. No ERR frames — the relay
    ///    connection is closing anyway.
    private func handleCartridgeDeath(cartridgeIdx: Int) {
        stateLock.lock()
        let cartridge = cartridges[cartridgeIdx]
        // Capture observer payload before any state mutation: pid is
        // about to be cleared, and the name needs to reflect the
        // process that actually died (path is stable, but cache the
        // derived `lastPathComponent` once for the callback below).
        let observerPidAtDeath = cartridge.pid
        let observerName = (cartridge.path as NSString).lastPathComponent
        cartridge.running = false
        // Close the writer atomically with nil-ing the property:
        // `writeFrame()` (CartridgeHost.ManagedCartridge.writeFrame)
        // takes `writerLock` and calls into the writer, so this race
        // window must be sealed. `writer.close()` also closes the
        // underlying stdin pipe, so no separate handle close is
        // needed.
        cartridge.writerLock.lock()
        cartridge.writer?.close()
        cartridge.writer = nil
        cartridge.writerLock.unlock()
        // One completed death (any reason) counts as one restart cycle.
        // The next on-demand spawn increments it again with a fresh process.
        cartridge.restartCount &+= 1
        let reason = cartridge.shutdownReason
        cartridge.shutdownReason = nil  // Reset for potential respawn

        // Check process status and kill if still running.
        // The reader thread got EOF on stdout, but the process may still be alive
        // (e.g. if a library closed stdout). We must kill before reading stderr,
        // because readToEnd blocks until the pipe's write end closes.
        var exitInfo = ""
        if let p = cartridge.pid {
            var status: Int32 = 0
            var wpid = waitpid(p, &status, WNOHANG)
            if wpid == 0 {
                // Process still running — stdout closed but process alive.
                // Kill it so we can collect stderr.
                kill(p, SIGTERM)
                Thread.sleep(forTimeInterval: 0.1)
                wpid = waitpid(p, &status, WNOHANG)
                if wpid == 0 {
                    kill(p, SIGKILL)
                    wpid = waitpid(p, &status, 0)  // blocking wait
                }
                exitInfo = "stdout closed while process still running"
            }
            if wpid > 0 {
                if (status & 0x7F) != 0 {
                    let sig = status & 0x7F
                    let info = "killed by signal \(sig)"
                    exitInfo = exitInfo.isEmpty ? info : "\(exitInfo), \(info)"
                } else {
                    let code = (status >> 8) & 0xFF
                    let info = "exit code \(code)"
                    exitInfo = exitInfo.isEmpty ? info : "\(exitInfo), \(info)"
                }
            } else if wpid < 0 {
                exitInfo = "waitpid failed (errno=\(errno))"
            }
            cartridge.pid = nil
        }

        // Now that the process is dead, read stderr — readToEnd will get
        // EOF immediately since the write end is closed.
        var stderrContent = ""
        if let stderrHandle = cartridge.stderrHandle {
            var allData = Data()
            if let data = try? stderrHandle.readToEnd(), !data.isEmpty {
                allData = data
            }
            if !allData.isEmpty {
                if let text = String(data: allData, encoding: .utf8) {
                    let maxLen = 2000
                    if text.count > maxLen {
                        stderrContent = String(text.prefix(maxLen)) + "... [truncated]"
                    } else {
                        stderrContent = text
                    }
                }
            }
            try? stderrHandle.close()
            cartridge.stderrHandle = nil
        }

        // stdin handle is owned by `cartridge.writer` and was already
        // closed in lockstep above when we transitioned the writer to
        // the closed state.

        // Clean up routing tables regardless of death cause.
        // outgoingRids: peer requests the cartridge initiated
        var failedOutgoing: [(rid: MessageId, nextSeq: UInt64)] = []
        for (rid, idx) in outgoingRids {
            if idx == cartridgeIdx {
                let flowKey = FlowKey(rid: rid, xid: nil)
                let nextSeq = (outgoingMaxSeq.removeValue(forKey: flowKey) ?? 0) + 1
                outgoingMaxSeqTouched.removeValue(forKey: flowKey)
                failedOutgoing.append((rid: rid, nextSeq: nextSeq))
            }
        }
        for entry in failedOutgoing {
            outgoingRids.removeValue(forKey: entry.rid)
            outgoingRidsTouched.removeValue(forKey: entry.rid)
        }

        // incomingRxids: requests routed to this cartridge (intentionally leaked)
        var failedIncoming: [(key: RxidKey, xid: MessageId, rid: MessageId, nextSeq: UInt64)] = []
        for (key, idx) in incomingRxids {
            if idx == cartridgeIdx {
                let flowKey = FlowKey(rid: key.rid, xid: key.xid)
                let nextSeq = (outgoingMaxSeq.removeValue(forKey: flowKey) ?? 0) + 1
                outgoingMaxSeqTouched.removeValue(forKey: flowKey)
                failedIncoming.append((key: key, xid: key.xid, rid: key.rid, nextSeq: nextSeq))
            }
        }
        for entry in failedIncoming {
            incomingRxids.removeValue(forKey: entry.key)
            incomingRxidsTouched.removeValue(forKey: entry.key)
            incomingToPeerRids.removeValue(forKey: entry.key)
            incomingToPeerRidsTouched.removeValue(forKey: entry.key)
        }

        // Determine error code and message based on shutdown reason.
        // Both unexpected deaths and OOM kills send ERR frames for pending work.
        // Only appExit suppresses ERR frames (relay is closing, no callers left).
        let cartridgePath = cartridge.path

        let errInfo: (code: String, message: String)?
        switch reason {
        case nil:
            // Unexpected death — genuine crash mid-flight
            let exitSuffix = exitInfo.isEmpty ? "" : " (\(exitInfo))"
            let msg = stderrContent.isEmpty
                ? "Cartridge \(cartridgePath) exited unexpectedly\(exitSuffix)."
                : "Cartridge \(cartridgePath) exited unexpectedly\(exitSuffix). stderr:\n\(stderrContent)"
            errInfo = (code: "CARTRIDGE_DIED", message: msg)
            cartridge.lastDeathMessage = msg
        case .oomKill:
            // OOM watchdog killed the cartridge — callers must be notified
            let exitSuffix = exitInfo.isEmpty ? "" : " (\(exitInfo))"
            let msg = stderrContent.isEmpty
                ? "Cartridge \(cartridgePath) killed by OOM watchdog\(exitSuffix)."
                : "Cartridge \(cartridgePath) killed by OOM watchdog\(exitSuffix). stderr:\n\(stderrContent)"
            errInfo = (code: "OOM_KILLED", message: msg)
            cartridge.lastDeathMessage = msg
        case .cancelled:
            // Cancel-triggered kill — ERR "CANCELLED" for all pending work
            let msg = "Cartridge \(cartridgePath) killed by cancel request."
            errInfo = (code: "CANCELLED", message: msg)
            cartridge.lastDeathMessage = msg
        case .disabled:
            // Operator-disabled kill — ERR "DISABLED" for all
            // pending work. Distinct from CANCELLED so operators
            // can tell "I cancelled this request" from "the
            // cartridge handling this request was disabled out
            // from under me." The XPC service triggers a fresh
            // discovery scan after the disable, so the next
            // dispatch will see no provider for the affected
            // caps and refuse new requests at the cap-table
            // layer rather than spawning the cartridge again.
            let msg = "Cartridge \(cartridgePath) killed because the operator disabled it."
            errInfo = (code: "DISABLED", message: msg)
            cartridge.lastDeathMessage = msg
        case .appExit:
            // Clean shutdown — no ERR frames, relay is closing
            errInfo = nil
            cartridge.lastDeathMessage = nil
        }

        // Rebuild capTable for on-demand respawn routing — driven by
        // the cartridge's `capUrns` view over its (still-known) cap
        // groups. The cartridge's manifest persists past death so
        // on-demand spawn knows which caps to advertise.
        capTable.removeAll { $0.1 == cartridgeIdx }
        if !cartridge.helloFailed {
            for cap in cartridge.capUrns {
                capTable.append((cap, cartridgeIdx))
            }
        }
        rebuildCapabilities()
        stateLock.unlock()

        // Notify lifecycle observer outside the lock.
        observer?.cartridgeDied(
            cartridgeIndex: cartridgeIdx,
            pid: observerPidAtDeath,
            name: observerName
        )

        // Send ERR frames for all pending work (unexpected death and OOM kill).
        if let info = errInfo {
            for entry in failedOutgoing {
                var err = Frame.err(id: entry.rid, code: info.code, message: info.message)
                err.seq = entry.nextSeq
                sendToRelay(err)
            }
            for entry in failedIncoming {
                var err = Frame.err(id: entry.rid, code: info.code, message: info.message)
                err.routingId = entry.xid
                err.seq = entry.nextSeq
                sendToRelay(err)
            }
        }
    }

    // MARK: - Cartridge Reader Thread

    /// Start a background reader thread for a cartridge.
    private func startCartridgeReaderThread(cartridgeIdx: Int, reader: FrameReader) {
        let thread = Thread { [weak self] in
            // Foundation reads (NSConcreteFileHandle.readDataOfLength)
            // return autoreleased NSConcreteData. A bare `Thread { }`
            // closure does NOT get an outer autorelease pool — the
            // autoreleased payloads accumulate forever as the loop
            // spins. With cartridges streaming MB-sized chunks this
            // turns into multi-GB heap growth that no Swift ARC
            // release path can touch (root cause confirmed via mfmon
            // diag counters: 15 KB total Frame.payload bytes flowed
            // through the queue while heap held GBs of
            // NSConcreteData).  Per-iteration pool keeps each read's
            // autoreleased objects scoped to one frame.
            while true {
                let shouldBreak: Bool = autoreleasepool {
                    do {
                        guard let frame = try reader.read() else {
                            // EOF — cartridge closed stdout
                            self?.pushEvent(.death(cartridgeIdx: cartridgeIdx))
                            return true
                        }
                        self?.pushEvent(.frame(cartridgeIdx: cartridgeIdx, frame: frame))
                        return false
                    } catch {
                        // Read error — treat as death
                        self?.pushEvent(.death(cartridgeIdx: cartridgeIdx))
                        return true
                    }
                }
                if shouldBreak { break }
            }
        }
        thread.name = "CartridgeHost.cartridge[\(cartridgeIdx)]"

        stateLock.lock()
        cartridges[cartridgeIdx].readerThread = thread
        stateLock.unlock()

        thread.start()
    }

    // MARK: - Event Queue

    /// Push an event from a cartridge reader thread.
    private func pushEvent(_ event: CartridgeEvent) {
        eventLock.lock()
        eventQueue.append(event)
        eventLock.unlock()
        eventSemaphore.signal()
    }

    /// Drain and process all pending events (used internally).
    private func processEvents() {
        eventLock.lock()
        let events = eventQueue
        eventQueue.removeAll()
        eventLock.unlock()

        for event in events {
            switch event {
            case .frame(let cartridgeIdx, let frame):
                handleCartridgeFrame(cartridgeIdx: cartridgeIdx, frame: frame)
            case .death(let cartridgeIdx):
                handleCartridgeDeath(cartridgeIdx: cartridgeIdx)
            case .relayFrame(let frame):
                handleRelayFrame(frame)
            case .relayClosed:
                break // Handled in run() loop
            case .statsRefresh:
                // Only the run() loop does the actual RelayNotify push to
                // avoid double-work. This drain path is test-only.
                break
            }
        }
    }

    // MARK: - Outbound Writing

    /// Write a frame to the relay (toward engine). Thread-safe.
    /// Frames arrive with seq already assigned by CartridgeRuntime — no modification needed.
    private func sendToRelay(_ frame: Frame) {
        if frame.frameType != .log {
            os_log(.debug, log: Self.log, "[sendToRelay] %{public}@ id=%{public}@ xid=%{public}@", String(describing: frame.frameType), String(describing: frame.id), String(describing: frame.routingId))
        }
        outboundLock.lock()
        defer { outboundLock.unlock() }
        guard let w = outboundWriter else {
            os_log(.error, log: Self.log, "[sendToRelay] outboundWriter is nil — frame dropped: %{public}@ id=%{public}@", String(describing: frame.frameType), String(describing: frame.id))
            return
        }
        try? w.write(frame)
    }

    // MARK: - Internal Helpers

    /// Build the `installedCartridges` list for a RelayNotify payload,
    /// injecting live runtime stats derived from the routing tables and
    /// cartridge process state. Must be called with stateLock held. One
    /// source of truth: the engine sees what the host sees, with no time
    /// skew beyond the send itself.
    private func buildInstalledCartridgeRecordsLocked() -> [InstalledCartridgeRecord] {
        var activeCounts: [Int: UInt64] = [:]
        for idx in incomingRxids.values {
            activeCounts[idx, default: 0] += 1
        }
        var peerCounts: [Int: UInt64] = [:]
        for idx in outgoingRids.values {
            peerCounts[idx, default: 0] += 1
        }

        var result: [InstalledCartridgeRecord] = []
        result.reserveCapacity(cartridges.count)
        for (idx, cartridge) in cartridges.enumerated() {
            // Match Rust: cartridges that have permanently failed
            // HELLO are not advertised, even if they have a resolvable
            // identity record.
            if cartridge.helloFailed {
                continue
            }
            guard let base = cartridge.installedCartridgeRecord() else { continue }
            let pid = cartridge.pid.map { UInt32($0) }
            let stats = CartridgeRuntimeStats(
                running: cartridge.running,
                pid: pid,
                activeRequestCount: activeCounts[idx, default: 0],
                peerRequestCount: peerCounts[idx, default: 0],
                memoryFootprintMb: cartridge.memoryFootprintMb,
                memoryRssMb: cartridge.memoryRssMb,
                lastHeartbeatUnixSeconds: cartridge.lastHeartbeatUnixSeconds,
                restartCount: cartridge.restartCount
            )
            result.append(InstalledCartridgeRecord(
                registryURL: base.registryURL,
                id: base.id,
                channel: base.channel,
                version: base.version,
                sha256: base.sha256,
                capGroups: cartridge.capGroups,
                attachmentError: base.attachmentError,
                runtimeStats: stats,
                lifecycle: base.lifecycle
            ))
        }
        return result
    }

    /// Rebuild aggregate capabilities from all known/discovered cartridges.
    /// Must hold stateLock when calling.
    /// Creates a JSON array of URN strings (not objects).
    ///
    /// Includes caps from ALL registered cartridges that haven't permanently failed HELLO.
    /// Each cartridge's `capGroups` is the single source of truth — the wire payload
    /// embeds them inside `installed_cartridges[*].cap_groups`, and the engine
    /// derives the flat cap-URN list itself.
    /// This ensures the relay always advertises all caps that CAN be handled, regardless
    /// of whether the cartridge process is currently alive (on-demand spawn handles restarts).
    ///
    /// If running in relay mode (outboundWriter is set), sends a RelayNotify frame
    /// to the relay interface with the updated capabilities.
    private func rebuildCapabilities() {
        // Collect caps contributed by healthy cartridges. CAP_IDENTITY is
        // advertised only when at least one healthy cartridge exists — the
        // mandatory CAP_IDENTITY declaration in every cartridge manifest is
        // what makes it answerable end-to-end, so an empty host must not
        // claim to answer identity. This matches the engine-side
        // `add_master` invariant: the identity probe traverses the pipeline
        // to a real cartridge; if no cartridge is available, there is no
        // pipeline to probe.
        // The wire payload now lives entirely inside
        // `installedCartridges[*].capGroups` — the engine derives the
        // flat cap-urn list with `RelayNotifyCapabilitiesPayload.capUrns()`.
        // `_capabilities` is the host's own process-local snapshot for
        // callers (e.g. `capabilities()`) that want the flat list
        // without re-decoding the wire bytes; we compute it the same way
        // the engine would.
        let installedCartridges = buildInstalledCartridgeRecordsLocked()
        let payload = RelayNotifyCapabilitiesPayload(installedCartridges: installedCartridges)
        let capsData: Data
        do {
            capsData = try JSONEncoder().encode(payload)
            _capabilities = capsData
        } catch {
            fatalError("BUG: failed to serialize RelayNotify capabilities payload: \(error)")
        }

        // Send RelayNotify to relay if in relay mode
        outboundLock.lock()
        if let writer = outboundWriter {
            let notify = Frame.relayNotify(manifest: capsData, limits: Limits())
            try? writer.write(notify) // Ignore error if relay closed
        }
        outboundLock.unlock()
    }

    /// Reason a manifest was rejected by `extractCaps`. Mirrors Rust's
    /// `ParseCapsError` so callers can pick the matching
    /// `CartridgeAttachmentErrorKind`:
    ///   * `.invalidJson` → `.manifestInvalid`
    ///   * `.incompatible` → `.incompatible`
    enum ManifestExtractError: Error, CustomStringConvertible {
        /// Manifest blob did not parse as JSON or was missing the
        /// `cap_groups` array (top-level structural failure).
        case invalidJson(String)
        /// Manifest parsed but violated the cartridge schema (missing
        /// CAP_IDENTITY, etc.).
        case incompatible(String)

        var description: String {
            switch self {
            case .invalidJson(let m), .incompatible(let m): return m
            }
        }

        var attachmentKind: CartridgeAttachmentErrorKind {
            switch self {
            case .invalidJson: return .manifestInvalid
            case .incompatible: return .incompatible
            }
        }
    }

    /// Extract cap URN strings from a manifest JSON blob.
    /// Throws `ManifestExtractError` so the caller can classify the failure
    /// for `recordAttachmentError`.
    private static func extractCapGroups(from manifest: Data) throws -> [CapGroup] {
        let decoded: Manifest
        do {
            decoded = try JSONDecoder().decode(Manifest.self, from: manifest)
        } catch {
            throw ManifestExtractError.invalidJson("Invalid CapManifest JSON: \(error)")
        }

        guard let identityUrn = try? CSCapUrn.fromString(CSCapIdentity) else {
            fatalError("BUG: CAP_IDENTITY constant '\(CSCapIdentity)' is invalid")
        }

        let hasIdentity = decoded.capGroups
            .flatMap { $0.caps }
            .contains { capDef in
                guard let capUrn = try? CSCapUrn.fromString(capDef.urn) else { return false }
                return identityUrn.conforms(to: capUrn)
            }

        guard hasIdentity else {
            throw ManifestExtractError.incompatible(
                "Cartridge manifest missing required CAP_IDENTITY (\(CSCapIdentity))"
            )
        }

        return decoded.capGroups
    }

    /// Generate identity verification nonce — CBOR-encoded "bifaci" text.
    private static func identityNonce() -> Data {
        return Data(CBOR.utf8String("bifaci").encode())
    }

    /// Verify cartridge identity by sending nonce and expecting echo response.
    ///
    /// This proves the transport works end-to-end and the cartridge correctly
    /// implements the identity capability (echo behavior).
    ///
    /// - Parameters:
    ///   - reader: FrameReader for cartridge stdout
    ///   - writer: FrameWriter for cartridge stdin
    /// - Throws: CartridgeHostError if verification fails
    private static func verifyCartridgeIdentity(reader: FrameReader, writer: FrameWriter) throws {
        let nonce = identityNonce()
        let reqId = MessageId.newUUID()
        let streamId = "identity-verify"

        // Send REQ with CAP_IDENTITY
        let req = Frame.req(id: reqId, capUrn: CSCapIdentity as String, payload: Data(), contentType: "application/cbor")
        try writer.write(req)

        // Send STREAM_START
        let ss = Frame.streamStart(reqId: reqId, streamId: streamId, mediaUrn: "media:")
        try writer.write(ss)

        // Send CHUNK with nonce
        let checksum = Frame.computeChecksum(nonce)
        let chunk = Frame.chunk(reqId: reqId, streamId: streamId, seq: 0, payload: nonce, chunkIndex: 0, checksum: checksum)
        try writer.write(chunk)

        // Send STREAM_END
        let se = Frame.streamEnd(reqId: reqId, streamId: streamId, chunkCount: 1)
        try writer.write(se)

        // Send END
        let end = Frame.end(id: reqId)
        try writer.write(end)

        // Read response - expect STREAM_START → CHUNK(s) → STREAM_END → END
        var accumulated = Data()
        while true {
            guard let frame = try reader.read() else {
                throw CartridgeHostError.handshakeFailed("Cartridge closed connection during identity verification")
            }

            switch frame.frameType {
            case .streamStart:
                break // Expected, no action needed
            case .chunk:
                if let payload = frame.payload {
                    accumulated.append(payload)
                }
            case .streamEnd:
                break // Expected, no action needed
            case .end:
                // Verify nonce matches
                if accumulated != nonce {
                    throw CartridgeHostError.handshakeFailed(
                        "Identity verification payload mismatch (expected \(nonce.count) bytes, got \(accumulated.count))")
                }
                return // Success
            case .err:
                let code = frame.errorCode ?? "UNKNOWN"
                let msg = frame.errorMessage ?? "no message"
                throw CartridgeHostError.handshakeFailed("Identity verification failed: [\(code)] \(msg)")
            default:
                throw CartridgeHostError.handshakeFailed("Identity verification: unexpected frame type \(frame.frameType)")
            }
        }
    }

    // MARK: - Spawn On Demand

    /// Spawn a registered cartridge binary on demand.
    ///
    /// Performs posix_spawn + HELLO handshake + starts reader thread.
    /// Does NOT hold stateLock during blocking operations (handshake).
    ///
    /// - Parameter idx: Cartridge index in the cartridges array
    /// - Throws: CartridgeHostError if spawn or handshake fails
    private func spawnCartridge(at idx: Int) throws {
        // Read cartridge info without holding lock during blocking ops
        stateLock.lock()
        let path = cartridges[idx].path
        let alreadyRunning = cartridges[idx].running
        let alreadyFailed = cartridges[idx].helloFailed
        stateLock.unlock()

        guard !path.isEmpty else {
            throw CartridgeHostError.handshakeFailed("No binary path for cartridge \(idx)")
        }
        guard !alreadyRunning else { return }
        guard !alreadyFailed else {
            throw CartridgeHostError.handshakeFailed("Cartridge previously failed HELLO — permanently removed")
        }

        // Setup pipes
        let inputPipe = Pipe()   // host writes → cartridge reads (stdin)
        let outputPipe = Pipe()  // cartridge writes → host reads (stdout)
        let errorPipe = Pipe()   // cartridge writes → host reads (stderr)

        var pid: pid_t = 0

        // Build argv (null-terminated for posix_spawn)
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup(path), nil]
        defer { argv.compactMap { $0 }.forEach { free($0) } }

        // File actions for pipe redirection
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        posix_spawn_file_actions_adddup2(&fileActions, inputPipe.fileHandleForReading.fileDescriptor, STDIN_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, outputPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, errorPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        // Close all pipe descriptors in child
        posix_spawn_file_actions_addclose(&fileActions, inputPipe.fileHandleForReading.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, inputPipe.fileHandleForWriting.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, outputPipe.fileHandleForReading.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, outputPipe.fileHandleForWriting.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, errorPipe.fileHandleForReading.fileDescriptor)
        posix_spawn_file_actions_addclose(&fileActions, errorPipe.fileHandleForWriting.fileDescriptor)

        // Spawn
        let spawnResult = posix_spawn(&pid, path, &fileActions, nil, argv, nil)
        guard spawnResult == 0 else {
            let desc = String(cString: strerror(spawnResult))
            let msg = "posix_spawn failed for \(path): \(desc)"
            stateLock.lock()
            cartridges[idx].recordAttachmentError(kind: .entryPointMissing, message: msg)
            capTable.removeAll { $0.1 == idx }
            rebuildCapabilities()
            stateLock.unlock()
            throw CartridgeHostError.handshakeFailed(msg)
        }

        // Close child's ends in parent
        inputPipe.fileHandleForReading.closeFile()
        outputPipe.fileHandleForWriting.closeFile()
        errorPipe.fileHandleForWriting.closeFile()

        let stdinHandle = inputPipe.fileHandleForWriting
        let stdoutHandle = outputPipe.fileHandleForReading
        let stderrHandle = errorPipe.fileHandleForReading

        // HELLO handshake (blocking — stateLock NOT held).
        // From this point on, `writer` owns `stdinHandle`'s lifetime.
        // All teardown paths must go through `writer.close()`, never
        // through `stdinHandle.closeFile()` directly, otherwise the
        // writer's cached fd outlives the open handle and a concurrent
        // write would target a closed/recycled descriptor.
        let reader = FrameReader(handle: stdoutHandle)
        let writer = FrameWriter(handle: stdinHandle)

        let handshakeResult: HandshakeResult
        do {
            handshakeResult = try performHandshakeWithManifest(reader: reader, writer: writer)
        } catch {
            // HELLO failure → permanent removal (binary is broken)
            kill(pid, SIGKILL)
            _ = waitpid(pid, nil, 0)
            writer.close()
            stdoutHandle.closeFile()
            stderrHandle.closeFile()

            let msg = "HELLO failed for \(path): \(error.localizedDescription)"
            stateLock.lock()
            cartridges[idx].recordAttachmentError(kind: .handshakeFailed, message: msg)
            capTable.removeAll { $0.1 == idx }
            rebuildCapabilities()
            stateLock.unlock()

            throw CartridgeHostError.handshakeFailed(msg)
        }

        // Parse cap groups from manifest — failure here means the manifest parsed
        // as JSON but doesn't declare CAP_IDENTITY or uses an old schema.
        let capGroups: [CapGroup]
        do {
            capGroups = try Self.extractCapGroups(from: handshakeResult.manifest ?? Data())
        } catch let extractErr as ManifestExtractError {
            kill(pid, SIGKILL)
            _ = waitpid(pid, nil, 0)
            writer.close()
            stdoutHandle.closeFile()
            stderrHandle.closeFile()

            // Classify by extract-error variant — keep parity with Rust:
            // JSON-level failures are `.manifestInvalid`; schema-rejection
            // (e.g. missing CAP_IDENTITY) is `.incompatible`.
            let kind = extractErr.attachmentKind
            let label = kind == .manifestInvalid ? "manifest invalid" : "manifest incompatible"
            let msg = "Cartridge \(label) for \(path): \(extractErr)"
            stateLock.lock()
            cartridges[idx].recordAttachmentError(kind: kind, message: msg)
            capTable.removeAll { $0.1 == idx }
            rebuildCapabilities()
            stateLock.unlock()

            throw CartridgeHostError.handshakeFailed(msg)
        }

        // Identity verification: send nonce, expect echo. Mirrors the Rust
        // host_runtime identity check and proves the protocol stack works
        // end-to-end for this cartridge.
        do {
            try Self.verifyCartridgeIdentity(reader: reader, writer: writer)
        } catch {
            kill(pid, SIGKILL)
            _ = waitpid(pid, nil, 0)
            writer.close()
            stdoutHandle.closeFile()
            stderrHandle.closeFile()

            let msg = "Identity verification failed for \(path): \(error.localizedDescription)"
            stateLock.lock()
            cartridges[idx].recordAttachmentError(kind: .identityRejected, message: msg)
            capTable.removeAll { $0.1 == idx }
            rebuildCapabilities()
            stateLock.unlock()

            throw CartridgeHostError.handshakeFailed(msg)
        }

        // Flatten cap-urns out of the groups for routing.
        let capUrns = capGroups.flatMap { $0.caps.map { $0.urn } }

        // Update cartridge state under lock. The writer is the sole
        // owner of stdin; we don't store the handle separately.
        stateLock.lock()
        let cartridge = cartridges[idx]
        cartridge.pid = pid
        cartridge.stdoutHandle = stdoutHandle
        cartridge.stderrHandle = stderrHandle
        cartridge.writerLock.lock()
        cartridge.writer = writer
        cartridge.writerLock.unlock()
        cartridge.manifest = handshakeResult.manifest ?? Data()
        cartridge.limits = handshakeResult.limits
        cartridge.capGroups = capGroups
        cartridge.running = true
        // Successful attach — clear any lingering attachment error from a
        // prior failed attempt (e.g. after a binary replacement).
        cartridge.attachmentError = nil

        // Update capTable with actual caps from manifest
        capTable.removeAll { $0.1 == idx }
        for cap in capUrns {
            capTable.append((cap, idx))
        }
        rebuildCapabilities()
        // Capture observer payload while we still hold the lock so the
        // values match the running=true state above. Fire the callback
        // outside the lock to avoid handing observer code a held lock.
        let observerPid = cartridge.pid
        let observerName = (cartridge.path as NSString).lastPathComponent
        let observerCaps = capUrns
        stateLock.unlock()

        // Start reader thread
        startCartridgeReaderThread(cartridgeIdx: idx, reader: reader)

        // Notify lifecycle observer (XPC reverse-callback bridge, etc.).
        // No-op when no observer is registered.
        observer?.cartridgeSpawned(
            cartridgeIndex: idx,
            pid: observerPid,
            name: observerName,
            caps: observerCaps
        )
    }

    // MARK: - Test-only Hooks

    /// Register a stub managed cartridge slot with no real
    /// process or I/O, already marked `running`. Test-only —
    /// production code brings a cartridge to running state via
    /// spawn + HELLO handshake. Exposed so the session-lifecycle
    /// test can verify that run() exit fires `cartridgeDied` for
    /// every running cartridge (the leak-class regression we
    /// guard against would drop these callbacks because
    /// cartridges would survive the session).
    ///
    /// Returns the assigned cartridge index.
    @discardableResult
    internal func attachStubCartridgeForTest() -> Int {
        let cartridge = ManagedCartridge.attached(
            manifest: Data(),
            limits: Limits(),
            capGroups: []
        )
        stateLock.lock()
        let idx = cartridges.count
        cartridges.append(cartridge)
        stateLock.unlock()
        return idx
    }

    /// Test-only inspection of the per-session outbound writer.
    /// `nil` after run() exits — used by the session-lifecycle
    /// test to assert that the writer is dropped on exit so late
    /// frames fail loud instead of silently buffering against a
    /// closed FD.
    internal var outboundWriterForTest: FrameWriter? {
        outboundLock.lock()
        defer { outboundLock.unlock() }
        return outboundWriter
    }

    /// Test-only snapshot of the four routing tables' current
    /// sizes plus the GC's monotonic counters. Used by routing-GC
    /// contract tests to assert the cap is enforced and that
    /// eviction fires when expected.
    internal struct RoutingTableSnapshotForTest: Equatable {
        let incomingRxids: Int
        let outgoingRids: Int
        let incomingToPeerRids: Int
        let outgoingMaxSeq: Int
        let gcRunsTotal: UInt64
        let gcEvictedTotal: UInt64
    }

    internal func routingTableSnapshotForTest() -> RoutingTableSnapshotForTest {
        stateLock.lock()
        defer { stateLock.unlock() }
        return RoutingTableSnapshotForTest(
            incomingRxids: incomingRxids.count,
            outgoingRids: outgoingRids.count,
            incomingToPeerRids: incomingToPeerRids.count,
            outgoingMaxSeq: outgoingMaxSeq.count,
            gcRunsTotal: routingTableGcRunsTotal,
            gcEvictedTotal: routingTableGcEvictedTotal
        )
    }

    /// Test-only direct insert into `incomingRxids` with a
    /// caller-supplied `touchedAt`. Lets the GC contract test seed
    /// a deterministic age distribution so it can verify that the
    /// oldest entries are the ones evicted (not arbitrary keys
    /// chosen by dictionary iteration order).
    internal func seedIncomingRxidForTest(
        key: RxidKey,
        cartridgeIdx: Int,
        touchedAt: UInt64
    ) {
        stateLock.lock()
        incomingRxids[key] = cartridgeIdx
        incomingRxidsTouched[key] = touchedAt
        // NB: the test seeds beyond the cap intentionally to fire
        // the GC in a follow-up call — do NOT run the GC here.
        stateLock.unlock()
    }

    /// Test-only invocation of the GC. Mirrors the production path
    /// (which fires from within stateLock-held insert sites) by
    /// taking the lock for the duration of the GC pass.
    internal func runRoutingTableGcForTest() {
        stateLock.lock()
        gcRoutingTablesIfNeededLocked()
        stateLock.unlock()
    }

    /// Expose the cap constants so tests can compute expected
    /// post-GC sizes without hardcoding magic numbers that would
    /// silently desync if the cap is later tuned.
    internal static var routingTableHardCapForTest: Int { routingTableHardCap }
    internal static var routingTableSoftWatermarkForTest: Int { routingTableSoftWatermark }
    internal static var routingTableGcEvictionFractionForTest: Double { routingTableGcEvictionFraction }

    // MARK: - Lifecycle

    /// Close the host, killing all managed cartridge processes.
    ///
    /// After close(), the run() loop will exit. Any pending requests get ERR frames.
    public func close() {
        stateLock.lock()
        guard !closed else {
            stateLock.unlock()
            return
        }
        closed = true

        // Collect death notifications under lock so the observer
        // payload reflects the state at the time of transition.
        // Fire callbacks after releasing the lock.
        var deathNotifications: [(idx: Int, pid: pid_t?, name: String)] = []

        // Kill all running cartridges. Close each cartridge's writer
        // (which closes stdin) under writerLock atomically with
        // nil-ing it, so any concurrent `writeFrame()` either
        // completes before the close or fails cleanly with
        // `FrameError.ioError("writer closed")`.
        for (idx, cartridge) in cartridges.enumerated() {
            cartridge.writerLock.lock()
            cartridge.writer?.close()
            cartridge.writer = nil
            cartridge.writerLock.unlock()

            if let stderr = cartridge.stderrHandle {
                try? stderr.close()
                cartridge.stderrHandle = nil
            }
            let wasRunning = cartridge.running
            let pidAtDeath = cartridge.pid
            let name = (cartridge.path as NSString).lastPathComponent
            cartridge.shutdownReason = .appExit
            cartridge.killProcess()
            cartridge.running = false
            if wasRunning {
                deathNotifications.append((idx: idx, pid: pidAtDeath, name: name))
            }
        }
        stateLock.unlock()

        // Notify observer for each cartridge that was actually
        // running at the moment close() was called.
        if let obs = observer {
            for note in deathNotifications {
                obs.cartridgeDied(cartridgeIndex: note.idx, pid: note.pid, name: note.name)
            }
        }

        // Signal the event loop to wake up and exit
        pushEvent(.relayClosed)
    }

    // MARK: - Cartridge Process Monitoring

    /// Get a snapshot of all running cartridge processes.
    /// Thread-safe — can be called from any thread while `run()` is active.
    public func runningCartridges() -> [CartridgeProcessInfo] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return cartridges.enumerated().compactMap { (idx, cartridge) in
            guard let pid = cartridge.pid, cartridge.running else { return nil }
            let name = (cartridge.path as NSString).lastPathComponent
            return CartridgeProcessInfo(
                cartridgeIndex: idx,
                pid: pid,
                name: name,
                running: cartridge.running,
                caps: cartridge.capGroups.flatMap { $0.caps.map { $0.urn } },
                memoryFootprintMb: cartridge.memoryFootprintMb,
                memoryRssMb: cartridge.memoryRssMb
            )
        }
    }

    /// Kill a specific cartridge process by PID for memory pressure.
    /// Sets `shutdownReason = .oomKill` so the death handler sends ERR frames
    /// with "OOM_KILLED" for all pending requests, allowing callers to fail
    /// fast instead of hanging forever.
    /// Thread-safe — can be called from any thread while `run()` is active.
    /// Returns `true` if the cartridge was found and killed.
    @discardableResult
    public func killCartridge(pid: pid_t) -> Bool {
        stateLock.lock()
        guard let cartridge = cartridges.first(where: { $0.pid == pid && $0.running }) else {
            stateLock.unlock()
            return false
        }
        cartridge.shutdownReason = .oomKill
        stateLock.unlock()
        cartridge.killProcess()
        return true
    }

    /// Kill any cartridge whose on-disk anchor (`cartridgeDir`,
    /// the version directory) matches `versionDir`. Used by the
    /// XPC service to "yank" a cartridge when the operator
    /// disables it: pending requests targeted at this cartridge
    /// fail hard with `CARTRIDGE_DIED` (the matching shutdownReason
    /// branch), giving the caller a clear failure rather than a
    /// silent hang.
    ///
    /// `cartridgeDir` is the unique identity for an installed
    /// cartridge within one host — the XPC service indexes by it
    /// throughout the discovery scan. Path comparison is
    /// byte-equal: callers MUST pass the same canonical form the
    /// host registered (typically the absolute path the
    /// `register_cartridge_dir` call used).
    ///
    /// Returns `true` if any matching cartridge was found and
    /// killed. Best-effort: a cartridge that isn't currently
    /// running (never spawned, already exited, mid-spawn) is a
    /// no-op for that entry.
    @discardableResult
    public func killCartridgesAtCartridgeDir(_ versionDir: String) -> Bool {
        stateLock.lock()
        let matching = cartridges.filter { $0.cartridgeDir == versionDir && $0.running }
        for cartridge in matching {
            // `.disabled` shutdownReason → death handler emits ERR
            // "DISABLED" for every pending request. Distinct from
            // `.cancelled` (which is "the caller cancelled their
            // request") and from `.oomKill` (watchdog event) and
            // `.appExit` (clean shutdown — no ERR frames). Gives
            // the caller an operator-recognisable reason to
            // surface in the UI / logs.
            cartridge.shutdownReason = .disabled
        }
        stateLock.unlock()
        for cartridge in matching {
            cartridge.killProcess()
        }
        return !matching.isEmpty
    }
}
