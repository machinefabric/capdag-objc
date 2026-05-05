//
//  CartridgeHostInstalledRecordTests.swift
//  Bifaci Tests — `buildInstalledCartridgeRecord` (CartridgeHost.swift)
//  is the function `rebuildCapabilities` walks every attached
//  cartridge through to refresh the engine-facing identity list.
//  It used to `fatalError` whenever a cartridge's on-disk directory
//  had been deleted between attach time and the rebuild pass —
//  which aborted the entire XPC service whenever the operator
//  uninstalled, an installer was mid-rename, or a registry refresh
//  raced a delete.
//
//  These tests pin down the new contract:
//    - Cartridge identity comes from `cartridge.json` ONLY. There
//      is no layout fallback. A cartridge whose `cartridge.json` is
//      missing or malformed returns nil from
//      `buildInstalledCartridgeRecord` — the cartridge has
//      effectively disappeared from the RelayNotify pass and
//      `buildInstalledCartridgeIdentitiesLocked` filters it out.
//      The discovery scanner owns grace-period delete on a
//      separate code path.
//    - When the manifest is present and parseable, hashing is
//      attempted; a hash failure becomes a per-cartridge
//      `entryPointMissing` attachment record, NOT a process abort.
//    - An upstream attachment error round-trips verbatim when the
//      manifest is still present.
//

import XCTest
import Foundation
@testable import Bifaci

final class CartridgeHostInstalledRecordTests: XCTestCase {

    // MARK: - Helpers

    /// Make a managed-cartridge-shaped on-disk anchor:
    ///   `<root>/dev/nightly/<name>/<version>/`
    /// with a valid `cartridge.json` and a small `entry` binary.
    /// Returns the version directory (the `cartridgeDir` shape the
    /// host's `ManagedCartridge.cartridgeDir` field carries).
    private func makeManagedCartridgeAnchor(
        name: String = "fixturecartridge",
        version: String = "0.0.1"
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartridgeHostInstalledIdentityTests")
            .appendingPathComponent(UUID().uuidString)
        let cartridgeDir = root
            .appendingPathComponent("dev")
            .appendingPathComponent("nightly")
            .appendingPathComponent(name)
            .appendingPathComponent(version)
        try FileManager.default.createDirectory(
            at: cartridgeDir,
            withIntermediateDirectories: true
        )
        let manifest = """
        {
          "name": "\(name)",
          "version": "\(version)",
          "channel": "nightly",
          "registry_url": null,
          "entry": "\(name)",
          "installed_at": "2026-01-01T00:00:00Z"
        }
        """
        try Data(manifest.utf8).write(
            to: cartridgeDir.appendingPathComponent("cartridge.json")
        )
        try Data("entry-binary".utf8).write(
            to: cartridgeDir.appendingPathComponent(name)
        )
        return cartridgeDir
    }

    /// Walk up to the slug-root the helper created so a single
    /// `removeItem` cleans up every test artifact, even when the
    /// individual test mutates the tree mid-run.
    private func slugRoot(of cartridgeDir: URL) -> URL {
        cartridgeDir
            .deletingLastPathComponent()  // version
            .deletingLastPathComponent()  // name
            .deletingLastPathComponent()  // channel
            .deletingLastPathComponent()  // slug
    }

    // MARK: - Tests

    /// TEST1700: A healthy cartridge whose directory exists hashes
    /// successfully and the resulting identity has the same name /
    /// version / channel as the cartridge.json, a non-empty sha256,
    /// and NO attachment error. Pins the happy path so a future
    /// refactor that breaks healthy-case hashing surfaces here.
    func test1700_healthyAnchorHashesAndCarriesNoError() throws {
        let dir = try makeManagedCartridgeAnchor(name: "hctest", version: "1.2.3")
        let root = slugRoot(of: dir)
        defer { try? FileManager.default.removeItem(at: root) }

        guard let identity = buildInstalledCartridgeRecord(
            cartridgeDir: dir.path,
            attachmentError: nil
        ) else {
            XCTFail("healthy cartridge must produce a non-nil identity")
            return
        }
        XCTAssertEqual(identity.id, "hctest")
        XCTAssertEqual(identity.version, "1.2.3")
        XCTAssertEqual(identity.channel, "nightly")
        XCTAssertNil(identity.registryURL,
                     "dev install must surface registryURL=nil from cartridge.json")
        XCTAssertFalse(identity.sha256.isEmpty,
                       "healthy cartridge must produce a non-empty sha256")
        XCTAssertNil(identity.attachmentError,
                     "healthy cartridge must carry no attachment error")
    }

    /// TEST1701: A cartridge whose `cartridge.json` has been
    /// deleted (e.g. the operator uninstalled, or the directory
    /// got swept up by a `dx clear --cartridges`) returns nil from
    /// `buildInstalledCartridgeRecord`. There is no layout
    /// fallback — cartridge.json IS the identity, and a cartridge
    /// without a manifest is considered gone for this RelayNotify
    /// pass. The host stays alive; the discovery scanner picks up
    /// the change on its next scan.
    ///
    /// Regression test for the field crash:
    ///   Bifaci/CartridgeHost.swift:617: Fatal error:
    ///   BUG: healthy installed cartridge directory must be
    ///   hashable at .../pdfcartridge/0.182.450
    /// Before the fix this code path aborted the whole XPC service.
    func test1701_missingManifestReturnsNil() throws {
        let dir = try makeManagedCartridgeAnchor(name: "gonecart", version: "9.9.9")
        let root = slugRoot(of: dir)
        // Delete the cartridge anchor entirely. This mimics the
        // operator running `dx clear --cartridges` or an installer
        // atomically renaming a `.installing-X` staging dir over
        // the previous version mid-discovery.
        try FileManager.default.removeItem(at: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "precondition: anchor must be gone for the test to be meaningful")

        let identity = buildInstalledCartridgeRecord(
            cartridgeDir: dir.path,
            attachmentError: nil
        )
        XCTAssertNil(identity,
                     "missing cartridge.json must produce nil identity (no layout fallback)")
    }

    /// TEST1702: Cartridge.json that's present-but-malformed (e.g.
    /// the file got truncated mid-write) also returns nil. There
    /// is no salvage path — a cartridge whose manifest can't be
    /// parsed is not a cartridge.
    func test1702_malformedManifestReturnsNil() throws {
        let dir = try makeManagedCartridgeAnchor(name: "malformed", version: "0.0.1")
        let root = slugRoot(of: dir)
        defer { try? FileManager.default.removeItem(at: root) }

        // Truncate cartridge.json to invalid JSON.
        try Data("{not even close to JSON".utf8).write(
            to: dir.appendingPathComponent("cartridge.json")
        )

        let identity = buildInstalledCartridgeRecord(
            cartridgeDir: dir.path,
            attachmentError: nil
        )
        XCTAssertNil(identity,
                     "malformed cartridge.json must produce nil identity")
    }

    /// TEST1703: A cartridge.json that omits the required
    /// `registry_url` key (old-schema file) returns nil.
    /// `registry_url` is required-but-nullable in the manifest
    /// schema; absent-key surfaces here as nil identity, surfaces
    /// downstream as the cartridge being filtered out of
    /// RelayNotify, and forces the operator to reinstall on the
    /// new schema.
    func test1703_oldSchemaManifestMissingRegistryUrlReturnsNil() throws {
        let dir = try makeManagedCartridgeAnchor(name: "oldschema", version: "0.0.1")
        let root = slugRoot(of: dir)
        defer { try? FileManager.default.removeItem(at: root) }

        // Overwrite cartridge.json with a manifest that omits
        // `registry_url` entirely (the pre-required-but-nullable
        // shape).
        let oldSchema = """
        {
          "name": "oldschema",
          "version": "0.0.1",
          "channel": "nightly",
          "entry": "oldschema",
          "installed_at": "2026-01-01T00:00:00Z"
        }
        """
        try Data(oldSchema.utf8).write(
            to: dir.appendingPathComponent("cartridge.json")
        )

        let identity = buildInstalledCartridgeRecord(
            cartridgeDir: dir.path,
            attachmentError: nil
        )
        XCTAssertNil(identity,
                     "old-schema cartridge.json (no registry_url key) must produce nil identity")
    }

    /// TEST1704: A cartridge that already carries an attachment
    /// error from upstream (e.g. failed HELLO) round-trips that
    /// error verbatim — the identity-build path does NOT mint a
    /// fresh error or override it. The sha256 is the real hash
    /// because the directory is still healthy; the error
    /// describes a different problem (the failed HELLO) than the
    /// hash function could surface.
    func test1704_existingAttachmentErrorRoundTrips() throws {
        let dir = try makeManagedCartridgeAnchor(name: "brokencart", version: "0.0.1")
        let root = slugRoot(of: dir)
        defer { try? FileManager.default.removeItem(at: root) }

        let upstreamError = CartridgeAttachmentError.now(
            kind: .handshakeFailed,
            message: "HELLO timed out after 10s"
        )

        guard let identity = buildInstalledCartridgeRecord(
            cartridgeDir: dir.path,
            attachmentError: upstreamError
        ) else {
            XCTFail("cartridge with existing attachmentError + present manifest must produce identity")
            return
        }
        XCTAssertEqual(identity.id, "brokencart")
        XCTAssertEqual(identity.version, "0.0.1")
        XCTAssertFalse(identity.sha256.isEmpty,
                       "existing-anchor + upstream-error must still produce a real sha256")

        guard let err = identity.attachmentError else {
            XCTFail("upstream attachmentError must round-trip")
            return
        }
        XCTAssertEqual(err.kind, .handshakeFailed,
                       "upstream error kind must not be overwritten")
        XCTAssertEqual(err.message, "HELLO timed out after 10s",
                       "upstream error message must round-trip verbatim")
    }

    /// TEST1705: An attached cartridge whose manifest has gone
    /// missing returns nil regardless of any prior attachment
    /// error. The contract is "manifest is identity"; a cartridge
    /// without a manifest is gone for this RelayNotify pass —
    /// even if it had a previously-recorded HELLO failure, the
    /// disappeared anchor wins. The discovery scanner removes the
    /// stale tree on its next pass.
    func test1705_missingManifestWinsOverExistingError() throws {
        let dir = try makeManagedCartridgeAnchor(name: "doublybroken", version: "0.0.1")
        let root = slugRoot(of: dir)
        try FileManager.default.removeItem(at: root)

        let upstreamError = CartridgeAttachmentError.now(
            kind: .handshakeFailed,
            message: "the HELLO that started this chain failed"
        )
        let identity = buildInstalledCartridgeRecord(
            cartridgeDir: dir.path,
            attachmentError: upstreamError
        )
        XCTAssertNil(identity,
                     "gone-manifest must win over upstream attachmentError")
    }
}
