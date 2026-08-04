import XCTest
import Foundation
@testable import Bifaci
import CapDAG

// =============================================================================
// SyncRoster Tests
//
// Mirrors `capdag/src/bifaci/host_runtime.rs` TEST1879. The Rust daemon
// runtime exposes a `SyncRoster` host command + `sync_registered_roster`; the
// macOS/ObjC mirror's architectural analog is `CartridgeHost.run()` (which
// emits RelayNotify to the engine) combined with `syncDiscoveryOutcomes`,
// which updates the LIVE host inventory in place and re-publishes RelayNotify.
// =============================================================================

@available(macOS 10.15.4, iOS 13.4, *)
final class CborSyncRosterTests: XCTestCase {

    /// Read the next RelayNotify frame from the engine side and return the
    /// installed-cartridge ids it advertises. Returns an empty array if the
    /// relay closes first.
    private func readNotifyIDs(_ reader: FrameReader) -> [String] {
        while true {
            guard let frame = (try? reader.read()) ?? nil else { return [] }
            if frame.frameType == .relayNotify {
                let bytes = frame.relayNotifyManifest ?? Data()
                guard let payload = try? JSONDecoder().decode(RelayNotifyCapabilitiesPayload.self, from: bytes) else {
                    return []
                }
                return payload.installedCartridges.map { $0.id }
            }
        }
    }

    // TEST1871: SyncRoster updates the LIVE host inventory in place — the engine sees an added registered-dir cartridge via a fresh RelayNotify without reconnecting, and a subsequent empty sync removes it. This is the macOS-XPC `syncDiscoveryOutcomes` parity path the daemon uses after a registry verdict flips a held cartridge to Listed.
    func test1871_syncRosterAddsAndRemovesRegisteredDirLive() async throws {
        // A valid registered-dir cartridge (hashable dir + cartridge.json).
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncRosterTests")
            .appendingPathComponent(UUID().uuidString)
        // Managed layout: <root>/dev/release/latejoiner/1.0.0/
        let versionDir = root
            .appendingPathComponent("dev")
            .appendingPathComponent("release")
            .appendingPathComponent("latejoiner")
            .appendingPathComponent("1.0.0")
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = """
        {"name":"latejoiner","version":"1.0.0","channel":"release","registry_url":null,"entry":"bin","installed_at":"2026-01-01T00:00:00Z","installed_from":"dev"}
        """
        try Data(manifest.utf8).write(to: versionDir.appendingPathComponent("cartridge.json"))
        let entry = versionDir.appendingPathComponent("bin")
        try Data("#!/bin/sh\n".utf8).write(to: entry)

        // Relay pipes (engine <-> host).
        let engineToHost = Pipe()
        let hostToEngine = Pipe()

        let host = CartridgeHost()

        // Drive the host run loop. It emits the initial RelayNotify, then a
        // fresh one on every `syncDiscoveryOutcomes` call.
        let hostTask = Task.detached { @Sendable in
            try? host.run(
                relayRead: engineToHost.fileHandleForReading,
                relayWrite: hostToEngine.fileHandleForWriting
            ) { Data() }
        }

        let engineReader = FrameReader(handle: hostToEngine.fileHandleForReading)

        // Initial RelayNotify (empty roster).
        let initial = readNotifyIDs(engineReader)

        // Add the cartridge live — the registered-dir analog of SyncRoster's
        // added spec. capGroups carries a CAP_IDENTITY so the record is a fully
        // formed discovered cartridge.
        let capGroups = [
            CapGroup(
                name: "default",
                caps: [
                    CapDefinition(urn: "cap:effect=none", title: "Identity", aliases: ["identity"]),
                    CapDefinition(urn: "cap:in=\"media:void\";late;out=\"media:void\"", title: "Late", aliases: ["late"]),
                ],
                adapterUrns: []
            )
        ]
        host.syncDiscoveryOutcomes([
            .discovered(path: entry.path, cartridgeDir: versionDir.path, capGroups: capGroups)
        ])
        let afterAdd = readNotifyIDs(engineReader)

        // Remove it again (empty roster).
        host.syncDiscoveryOutcomes([])
        let afterRemove = readNotifyIDs(engineReader)

        // Let run() exit by closing the relay.
        engineToHost.fileHandleForWriting.closeFile()
        _ = await hostTask.value

        XCTAssertFalse(initial.contains("latejoiner"),
                       "cartridge must be absent before the sync; got \(initial)")
        XCTAssertTrue(afterAdd.contains("latejoiner"),
                      "SyncRoster must add the cartridge to the live inventory; got \(afterAdd)")
        XCTAssertFalse(afterRemove.contains("latejoiner"),
                       "an empty SyncRoster must retire the cartridge; got \(afterRemove)")
    }

    // =========================================================================
    // Roster retirement: drain, not kill
    // =========================================================================

    /// A registered cartridge on disk, registered with the host and marked
    /// running, for roster-retire tests. Mirrors the reference test fixture.
    private func retireFixture() throws -> (host: CartridgeHost, root: URL, path: String, dir: String) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RetireTests")
            .appendingPathComponent(UUID().uuidString)
        let versionDir = root
            .appendingPathComponent("dev")
            .appendingPathComponent("release")
            .appendingPathComponent("retiring")
            .appendingPathComponent("1.0.0")
        try FileManager.default.createDirectory(at: versionDir, withIntermediateDirectories: true)
        let manifest = """
        {"name":"retiring","version":"1.0.0","channel":"release","registry_url":null,"entry":"bin","installed_at":"2026-01-01T00:00:00Z","installed_from":"dev"}
        """
        try Data(manifest.utf8).write(to: versionDir.appendingPathComponent("cartridge.json"))
        let entry = versionDir.appendingPathComponent("bin")
        try Data("#!/bin/sh\n".utf8).write(to: entry)

        let host = CartridgeHost()
        host.registerCartridge(path: entry.path, cartridgeDir: versionDir.path, capGroups: [])
        // Pretend it started: retirement only has to make a decision about a
        // LIVE process.
        host.markCartridgeRunningForTest(cartridgeIdx: 0)
        return (host, root, entry.path, versionDir.path)
    }

    // TEST1945: a roster retire DRAINS a busy cartridge instead of killing it. The incident this pins: a transient registry outage shrank the roster and the host killed three cartridges outright, ERRing every request they were serving. Retirement means "no NEW work" — the process must survive until the requests it is already handling terminate.
    func test1945_rosterRetireDrainsABusyCartridgeBeforeKillingIt() throws {
        let fixture = try retireFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        // One request in flight on this cartridge.
        let key = RxidKey(xid: MessageId.uint(1), rid: MessageId.uint(2))
        fixture.host.seedIncomingRxidForTest(key: key, cartridgeIdx: 0, touchedAt: 1)

        // An empty outcome set is the discovery sync saying "this install is
        // no longer wanted".
        fixture.host.syncDiscoveryOutcomes([])

        var state = fixture.host.cartridgeRetirementStateForTest(cartridgeIdx: 0)
        XCTAssertTrue(state.isRemoved, "a retired cartridge must leave the inventory immediately")
        XCTAssertTrue(state.isDraining, "a busy retired cartridge must be marked draining")
        XCTAssertTrue(state.running, "a cartridge mid-request must not be killed by a roster change")

        // Still busy → still alive.
        fixture.host.reapDrainedCartridgesForTest()
        state = fixture.host.cartridgeRetirementStateForTest(cartridgeIdx: 0)
        XCTAssertTrue(state.running)

        // The request terminates; the next reap collects it.
        fixture.host.removeIncomingRxidForTest(key: key)
        fixture.host.reapDrainedCartridgesForTest()
        state = fixture.host.cartridgeRetirementStateForTest(cartridgeIdx: 0)
        XCTAssertFalse(state.running, "a drained cartridge must be shut down once its last request ends")
        XCTAssertFalse(state.isDraining)
    }

    // TEST1946: an IDLE cartridge is retired immediately (no reason to keep a process nothing routes to).
    func test1946_rosterRetireKillsAnIdleCartridgeAsRetired() throws {
        let fixture = try retireFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        fixture.host.syncDiscoveryOutcomes([])

        let state = fixture.host.cartridgeRetirementStateForTest(cartridgeIdx: 0)
        XCTAssertFalse(state.isDraining)
        XCTAssertFalse(state.running)
        XCTAssertTrue(state.isRemoved)
    }

    // TEST1947: a roster that flaps — retire then restore the same identity — keeps the SAME live process. This is the incident's shape end to end: the registry became unreachable, the roster shrank, and 26 seconds later it came back. Nothing about that sequence should cost a running cartridge, its warm model, or the work queued on it.
    func test1947_rosterFlapCancelsRetirementInsteadOfRespawning() throws {
        let fixture = try retireFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        // Busy, so the outage puts it into a drain rather than killing it.
        let key = RxidKey(xid: MessageId.uint(1), rid: MessageId.uint(2))
        fixture.host.seedIncomingRxidForTest(key: key, cartridgeIdx: 0, touchedAt: 1)
        fixture.host.syncDiscoveryOutcomes([])
        XCTAssertTrue(fixture.host.cartridgeRetirementStateForTest(cartridgeIdx: 0).isDraining)

        // The registry answers again and the roster is restored.
        fixture.host.syncDiscoveryOutcomes([
            .discovered(path: fixture.path, cartridgeDir: fixture.dir, capGroups: [])
        ])

        XCTAssertEqual(
            fixture.host.cartridgeCountForTest, 1,
            "the restored identity must reuse the draining process, not spawn a second one"
        )
        var state = fixture.host.cartridgeRetirementStateForTest(cartridgeIdx: 0)
        XCTAssertFalse(state.isDraining)
        XCTAssertFalse(state.isRemoved)
        XCTAssertTrue(state.running, "the process must never have been killed")

        // And it is not reaped afterwards.
        fixture.host.removeIncomingRxidForTest(key: key)
        fixture.host.reapDrainedCartridgesForTest()
        state = fixture.host.cartridgeRetirementStateForTest(cartridgeIdx: 0)
        XCTAssertTrue(state.running)
    }
}
