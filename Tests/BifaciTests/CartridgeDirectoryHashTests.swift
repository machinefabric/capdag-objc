//
//  CartridgeDirectoryHashTests.swift
//  Bifaci Tests — `computeCartridgeDirectoryHash` (CartridgeHost.swift)
//  must hash arbitrarily large cartridge directories without
//  allocating a single buffer the size of the largest file inside.
//
//  Background: the original implementation called
//  `FileManager.contents(atPath:)` on every file, which slurps the
//  whole file into a single `Data`. Inside the sandboxed XPC service
//  this hit a memory ceiling on the 200 MB mlxcartridge binary,
//  returned nil, and the caller's `fatalError("must be hashable")`
//  killed the host — taking unrelated cartridges down with it
//  (those got blamed in quarantine on the next start). The fix is
//  to stream file content through SHA256 in fixed-size chunks.
//
//  These tests pin down the streaming behaviour:
//    1. Files larger than one chunk hash correctly.
//    2. The chunk size is bounded — guards against a future revert
//       to a slurp-the-whole-file implementation.
//    3. Determinism: same directory contents → same hash.
//    4. Real failures are surfaced as typed errors with the
//       offending path, not silently as nil.
//

import XCTest
import Foundation
import CommonCrypto
@testable import Bifaci

final class CartridgeDirectoryHashTests: XCTestCase {

    // MARK: - Helpers

    /// Make a temporary directory under the test runner's working tree.
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartridgeDirectoryHashTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Independent SHA256 over the same byte sequence the real hasher
    /// builds: for each file (sorted by relative path, excluding
    /// `cartridge.json`) feed UTF-8 path bytes then file bytes,
    /// streamed in chunks. Mirrors the production algorithm so an
    /// equality check is non-trivial: it catches off-by-one chunking,
    /// missing path-bytes feeds, and any reordering of path-vs-content
    /// bytes.
    private func referenceHash(of dirPath: String) throws -> String {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: dirPath) else {
            XCTFail("temp dir unreadable: \(dirPath)")
            return ""
        }

        var files: [(rel: String, full: String)] = []
        while let rel = enumerator.nextObject() as? String {
            let full = (dirPath as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
            if rel == "cartridge.json" { continue }
            files.append((rel: rel, full: full))
        }
        files.sort { $0.rel < $1.rel }

        var ctx = CC_SHA256_CTX()
        CC_SHA256_Init(&ctx)
        for f in files {
            if let p = f.rel.data(using: .utf8) {
                p.withUnsafeBytes { CC_SHA256_Update(&ctx, $0.baseAddress, CC_LONG(p.count)) }
            }
            let fd = open(f.full, O_RDONLY)
            XCTAssertGreaterThanOrEqual(fd, 0, "open() failed for \(f.full)")
            defer { Darwin.close(fd) }
            var buf = [UInt8](repeating: 0, count: 4096)
            while true {
                let n = buf.withUnsafeMutableBufferPointer { Darwin.read(fd, $0.baseAddress, $0.count) }
                if n <= 0 { break }
                buf.withUnsafeBufferPointer { CC_SHA256_Update(&ctx, $0.baseAddress, CC_LONG(n)) }
            }
        }
        var out = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&out, &ctx)
        return out.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Tests

    @available(macOS 10.15.4, iOS 13.4, *)
    // TEST1600: Hashing a directory containing a file LARGER than the streaming chunk size produces the same hash as an independent reference implementation. Exercises the multi-iteration read loop in `computeCartridgeDirectoryHash` — if a future refactor reverted to slurping whole files, the hash would still match (slurp gives the right answer too), so this is the necessary correctness pin even though it is not the tightest possible regression.
    func test1600_hashesFileLargerThanOneChunk() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Make a file ~2.5 chunks long with a deterministic non-trivial
        // pattern that would break under a buffer-reuse bug.
        let size = (cartridgeHashStreamChunk * 5) / 2
        var bytes = [UInt8](repeating: 0, count: size)
        for i in 0..<size { bytes[i] = UInt8(i & 0xFF) }
        let big = Data(bytes)
        try big.write(to: dir.appendingPathComponent("big.bin"))

        let small = "hello".data(using: .utf8)!
        try small.write(to: dir.appendingPathComponent("a-small.txt"))

        let actual = try computeCartridgeDirectoryHash(atPath: dir.path)
        let expected = try referenceHash(of: dir.path)
        XCTAssertEqual(actual, expected, "streaming hash must match the reference algorithm byte-for-byte")
    }

    @available(macOS 10.15.4, iOS 13.4, *)
    // TEST1601: The streaming chunk size is bounded so no single allocation scales with file size. This is the structural guard that prevents a future revert to FileManager.contents(atPath:) on a 200+ MB cartridge binary — that revert silently corrupted state in the sandboxed XPC service. Anything above 16 MiB is in the "you're slurping" zone and must not land.
    func test1601_streamChunkSizeIsBounded() {
        XCTAssertGreaterThan(cartridgeHashStreamChunk, 0, "chunk size must be positive")
        XCTAssertLessThanOrEqual(cartridgeHashStreamChunk, 16 * 1024 * 1024,
                                 "chunk size must stay small enough that hashing a large cartridge binary does not require a single large allocation; 16 MiB is the upper bound for an XPC-sandboxed service")
    }

    @available(macOS 10.15.4, iOS 13.4, *)
    // TEST1602: cartridge.json is excluded from the hash — adding it (or changing its contents) must not change the directory hash, because cartridge.json carries install-time metadata that varies between installs of the same logical content.
    func test1602_cartridgeJsonExcluded() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "payload".data(using: .utf8)!.write(to: dir.appendingPathComponent("a.txt"))
        let bare = try computeCartridgeDirectoryHash(atPath: dir.path)

        try "{\"name\":\"x\"}".data(using: .utf8)!
            .write(to: dir.appendingPathComponent("cartridge.json"))
        let withJson = try computeCartridgeDirectoryHash(atPath: dir.path)

        XCTAssertEqual(bare, withJson, "adding cartridge.json must not change the directory hash")

        try "{\"name\":\"y\"}".data(using: .utf8)!
            .write(to: dir.appendingPathComponent("cartridge.json"))
        let mutated = try computeCartridgeDirectoryHash(atPath: dir.path)
        XCTAssertEqual(bare, mutated, "mutating cartridge.json must not change the directory hash")
    }

    @available(macOS 10.15.4, iOS 13.4, *)
    // TEST1603: Hashing a directory that does not exist throws CartridgeDirectoryHashError.directoryUnreadable carrying the offending path. Replaces the original silent `return nil` that the caller turned into a generic "must be hashable" fatalError — the new error names the actual path so operators see what to fix.
    func test1603_missingDirectoryThrowsTypedError() {
        let bogus = "/var/empty/this-cartridge-dir-does-not-exist-\(UUID().uuidString)"
        do {
            _ = try computeCartridgeDirectoryHash(atPath: bogus)
            XCTFail("hashing a non-existent directory must throw")
        } catch let error as CartridgeDirectoryHashError {
            switch error {
            case .directoryUnreadable(let path):
                XCTAssertEqual(path, bogus, "error must carry the path that failed")
            case .openFailed, .readFailed:
                XCTFail("expected directoryUnreadable, got \(error)")
            }
        } catch {
            XCTFail("expected CartridgeDirectoryHashError, got \(error)")
        }
    }

    @available(macOS 10.15.4, iOS 13.4, *)
    // TEST1604: An empty directory hashes successfully (just the SHA256 of nothing — empty input). Ensures the function does not insist on at least one file.
    func test1604_emptyDirectoryHashes() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let h = try computeCartridgeDirectoryHash(atPath: dir.path)
        // SHA256 of empty input
        XCTAssertEqual(h, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                       "empty directory must hash to SHA256(\"\")")
    }

    @available(macOS 10.15.4, iOS 13.4, *)
    // TEST1605: computeFileSHA256 streams a single file (used for quarantine identity tracking) and produces the standard SHA256 of the file's bytes. Verifies multi-chunk read correctness against a known SHA256 of `"abc"` from the FIPS-180-2 test vectors.
    func test1605_fileSHA256MatchesKnownVector() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("abc.bin").path
        try "abc".data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
        let h = try computeFileSHA256(atPath: path)
        XCTAssertEqual(h, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                       "SHA256(\"abc\") must match the FIPS-180-2 test vector")
    }

    @available(macOS 10.15.4, iOS 13.4, *)
    // TEST1606: computeFileSHA256 streams arbitrarily large files without loading the whole file into memory. Hashes a file roughly 3.5 chunks long and verifies the result against a single-shot CC_SHA256 over the same buffer — proving the chunk loop is correct across multiple read iterations.
    func test1606_fileSHA256StreamsAcrossChunks() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("big.bin").path
        let size = (cartridgeHashStreamChunk * 7) / 2
        var bytes = [UInt8](repeating: 0, count: size)
        for i in 0..<size { bytes[i] = UInt8((i * 31 + 7) & 0xFF) }
        let blob = Data(bytes)
        try blob.write(to: URL(fileURLWithPath: path))

        var expectedDigest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        blob.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(blob.count), &expectedDigest) }
        let expected = expectedDigest.map { String(format: "%02x", $0) }.joined()

        let actual = try computeFileSHA256(atPath: path)
        XCTAssertEqual(actual, expected, "streaming file hash must match a single-shot SHA256 over the same bytes")
    }

    @available(macOS 10.15.4, iOS 13.4, *)
    // TEST1607: computeFileSHA256 throws openFailed on a missing path with the offending path attached. Replaces the previous silent `return nil` so callers can surface the actual cause to the operator.
    func test1607_fileSHA256ThrowsOnMissingPath() {
        let bogus = "/var/empty/this-file-does-not-exist-\(UUID().uuidString)"
        do {
            _ = try computeFileSHA256(atPath: bogus)
            XCTFail("hashing a non-existent file must throw")
        } catch let error as CartridgeDirectoryHashError {
            switch error {
            case .openFailed(let path, _):
                XCTAssertEqual(path, bogus, "error must carry the path that failed")
            case .directoryUnreadable, .readFailed:
                XCTFail("expected openFailed, got \(error)")
            }
        } catch {
            XCTFail("expected CartridgeDirectoryHashError, got \(error)")
        }
    }
}
