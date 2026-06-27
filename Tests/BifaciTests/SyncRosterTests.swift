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

    // TEST1879: SyncRoster updates the LIVE host inventory in place — the engine sees an added registered-dir cartridge via a fresh RelayNotify without reconnecting, and a subsequent empty sync removes it. This is the macOS-XPC `syncDiscoveryOutcomes` parity path the daemon uses after a registry verdict flips a held cartridge to Listed.
    func test1879_syncRosterAddsAndRemovesRegisteredDirLive() async throws {
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
                    CapDefinition(urn: "cap:effect=none", title: "Identity", command: "identity"),
                    CapDefinition(urn: "cap:in=\"media:void\";late;out=\"media:void\"", title: "Late", command: "late"),
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
}
