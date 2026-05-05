//
//  CartridgeAttachmentErrorKindWireTests.swift
//  Bifaci Tests — pin the wire format of `CartridgeAttachmentErrorKind`.
//  This enum crosses three different boundaries:
//    * relay socket (Swift host → Rust engine, JSON over RelayNotify)
//    * gRPC (engine → app, proto enum in cartridge.proto)
//    * XPC (app → main app, NSXPC-bridged dictionary)
//  Every variant's `rawValue` MUST match its proto snake_case name
//  byte-for-byte, otherwise a Swift-side cartridge marked
//  `.disabled` arrives at the engine as an unknown variant and the
//  whole RelayNotify aggregate fails to deserialize.
//
//  These tests pin every variant's raw string and assert JSON
//  round-trip stability. They will fail loudly the moment someone
//  renames a variant without also updating the snake_case mapping
//  or the proto.
//

import XCTest
import Foundation
@testable import Bifaci

final class CartridgeAttachmentErrorKindWireTests: XCTestCase {

    /// TEST1710: Every variant's `rawValue` must be its
    /// snake_case proto name. New variants must be added here AND
    /// to `cartridge.proto`'s `CartridgeAttachmentErrorKind`. This
    /// test fails with a clear "expected X for Y" message rather
    /// than a "unknown enum case" runtime crash if the two sides
    /// drift.
    func test1710_kindRawValuesMatchProtoSnakeCase() {
        let expected: [(CartridgeAttachmentErrorKind, String)] = [
            (.incompatible,        "incompatible"),
            (.manifestInvalid,     "manifest_invalid"),
            (.handshakeFailed,     "handshake_failed"),
            (.identityRejected,    "identity_rejected"),
            (.entryPointMissing,   "entry_point_missing"),
            (.quarantined,         "quarantined"),
            (.badInstallation,     "bad_installation"),
            (.disabled,            "disabled"),
            (.registryUnreachable, "registry_unreachable"),
        ]
        for (kind, expectedRaw) in expected {
            XCTAssertEqual(
                kind.rawValue, expectedRaw,
                "variant '\(kind)' must serialize as '\(expectedRaw)' to match cartridge.proto's CartridgeAttachmentErrorKind"
            )
        }
    }

    /// TEST1711: A `CartridgeAttachmentError` round-trips through
    /// `JSONEncoder` → bytes → `JSONDecoder` unchanged for every
    /// kind. RelayNotify's wire payload is JSON; if any variant
    /// fails to deserialize, the engine's aggregate parse fails
    /// and ALL cartridges from that host disappear from the
    /// inventory — including the healthy ones. This test
    /// covers each variant individually so a single-variant
    /// regression doesn't hide behind a passing healthy-case.
    func test1711_attachmentErrorJSONRoundTripsForEveryKind() throws {
        let cases: [CartridgeAttachmentErrorKind] = [
            .incompatible, .manifestInvalid, .handshakeFailed,
            .identityRejected, .entryPointMissing, .quarantined,
            .badInstallation, .disabled, .registryUnreachable,
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for kind in cases {
            let original = CartridgeAttachmentError.now(
                kind: kind,
                message: "round-trip test for \(kind)"
            )
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(CartridgeAttachmentError.self, from: data)
            XCTAssertEqual(decoded.kind, original.kind,
                "kind must round-trip for variant '\(kind)' (raw='\(kind.rawValue)')")
            XCTAssertEqual(decoded.message, original.message,
                "message must round-trip for variant '\(kind)'")
            XCTAssertEqual(decoded.detectedAtUnixSeconds, original.detectedAtUnixSeconds,
                "detected_at_unix_seconds must round-trip for variant '\(kind)'")
        }
    }

    /// TEST1712: An on-the-wire JSON payload using the snake_case
    /// raw values decodes into the right Swift variant. This is
    /// the engine → Swift path: the engine emits
    /// `{"kind":"bad_installation",...}` and the Swift side must
    /// resolve it to `.badInstallation`. Asserts the lookup table
    /// the decoder synthesises for `String`-backed enums actually
    /// covers the new variants.
    func test1712_decodesWireFormatJSONIntoExpectedVariants() throws {
        let wireExpectations: [(String, CartridgeAttachmentErrorKind)] = [
            ("incompatible",        .incompatible),
            ("manifest_invalid",    .manifestInvalid),
            ("handshake_failed",    .handshakeFailed),
            ("identity_rejected",   .identityRejected),
            ("entry_point_missing", .entryPointMissing),
            ("quarantined",         .quarantined),
            ("bad_installation",    .badInstallation),
            ("disabled",            .disabled),
            ("registry_unreachable",.registryUnreachable),
        ]
        let decoder = JSONDecoder()
        for (raw, expectedKind) in wireExpectations {
            let json = """
            {
                "kind": "\(raw)",
                "message": "decode test for \(raw)",
                "detected_at_unix_seconds": 1700000000
            }
            """
            let data = Data(json.utf8)
            let decoded = try decoder.decode(CartridgeAttachmentError.self, from: data)
            XCTAssertEqual(decoded.kind, expectedKind,
                "wire kind '\(raw)' must decode to .\(expectedKind)")
        }
    }

    /// TEST1713: An unknown wire kind FAILS to decode. The two
    /// new variants are wire-additive — older Swift binaries that
    /// don't know `bad_installation` or `disabled` will see those
    /// strings and reject them, which is correct: silently
    /// coercing an unknown variant to a fallback would hide the
    /// version-skew bug. The fatalError sites in
    /// CartridgeGRPCAdapter and InstalledCartridgesStore rely on
    /// this — they expect decode to throw / produce a known
    /// variant, never silently pick a default.
    func test1713_unknownWireKindFailsToDecode() {
        let json = """
        {
            "kind": "completely_made_up_kind",
            "message": "should not decode",
            "detected_at_unix_seconds": 1700000000
        }
        """
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        XCTAssertThrowsError(
            try decoder.decode(CartridgeAttachmentError.self, from: data),
            "unknown wire kind must throw, not silently coerce"
        )
    }
}
