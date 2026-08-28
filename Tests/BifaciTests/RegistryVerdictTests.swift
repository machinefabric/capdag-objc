import XCTest
@testable import Bifaci

/// The registry-trust vocabulary, mirrored from Rust
/// `bifaci/registry_verdict.rs`. These tests pin the same facts its Rust and
/// JavaScript twins do — a mirror that drifts stops understanding its own
/// producers, which is the failure this vocabulary exists to make impossible.
final class RegistryVerdictTests: XCTestCase {
    private let url = "https://cartridges.example/v1/manifest"
    private let now: Int64 = 1_700_000_000

    /// TEST8150: the wire vocabulary is closed and matches the other mirrors.
    func test8150_stateWireNamesMatchTheMirrors() {
        let expected = [
            "verified", "pending", "offline", "unreachable",
            "http_error", "malformed", "unsigned", "untrusted", "unverifiable",
        ]
        XCTAssertEqual(RegistryVerdictState.allCases.map(\.rawValue), expected)
        let reasons = [
            "malformed_envelope", "unsupported_envelope_format", "malformed_certificate",
            "unsupported_certificate_format", "empty_certificate_list",
            "insufficient_root_signatures", "expired_certificate", "not_yet_valid_certificate",
            "environment_mismatch", "key_id_mismatch", "no_authorizing_certificate",
            "manifest_signature_invalid",
        ]
        XCTAssertEqual(ChainFailureReason.allCases.map(\.rawValue), reasons)
    }

    /// TEST8151: a format this build cannot read is OUR limitation — never the
    /// registry being untrustworthy, and never a network problem.
    func test8151_unreadableFormatIsUnverifiableAndRejectedKeyIsUntrusted() {
        for unevaluable: ChainFailureReason in [
            .malformedEnvelope, .unsupportedEnvelopeFormat, .malformedCertificate,
            .unsupportedCertificateFormat, .emptyCertificateList,
        ] {
            XCTAssertEqual(
                RegistryVerdictState.forChainFailure(unevaluable), .unverifiable,
                "\(unevaluable.rawValue) could not be judged at all"
            )
        }
        for judged: ChainFailureReason in [
            .insufficientRootSignatures, .expiredCertificate, .notYetValidCertificate,
            .environmentMismatch, .keyIDMismatch, .noAuthorizingCertificate,
            .manifestSignatureInvalid,
        ] {
            XCTAssertEqual(
                RegistryVerdictState.forChainFailure(judged), .untrusted,
                "\(judged.rawValue) is a judgement that WAS reached"
            )
        }
    }

    /// TEST8152: only a verified registry lets a cartridge attach — `.pending`
    /// included, which must never read as permission.
    func test8152_onlyVerifiedPermitsAttachment() {
        for state in RegistryVerdictState.allCases {
            XCTAssertEqual(state.permitsAttachment, state == .verified, state.rawValue)
        }
    }

    /// TEST8153: a refusal never resolves itself, so nothing may present it as
    /// worth retrying.
    func test8153_trustFailuresAreNeverTransient() {
        for state in RegistryVerdictState.allCases {
            XCTAssertFalse(
                state.isTrustFailure && state.isTransient,
                "'\(state.rawValue)' cannot be both a refusal and something a retry could fix"
            )
        }
        XCTAssertTrue(RegistryVerdictState.unverifiable.isTrustFailure)
        XCTAssertTrue(RegistryVerdictState.untrusted.isTrustFailure)
        XCTAssertTrue(RegistryVerdictState.unsigned.isTrustFailure)
        XCTAssertTrue(RegistryVerdictState.unreachable.isTransient)
        XCTAssertTrue(RegistryVerdictState.pending.isTransient)
        // Policy is not transient: it holds until an operator changes it.
        XCTAssertFalse(RegistryVerdictState.offline.isTransient)
        XCTAssertFalse(RegistryVerdictState.offline.isTrustFailure)
    }

    /// TEST8159: the remedy follows from the state, and "check the network" is
    /// reachable from exactly one state. That sentence used to be appended to
    /// every held-cartridge message whatever the cause, which is how a
    /// signature format this build could not read sent operators to their
    /// router.
    func test8159_theRemedyFollowsFromTheState() {
        let network = RegistryVerdictState.allCases.filter { $0.remedy == .checkNetwork }
        XCTAssertEqual(network, [.unreachable],
                       "only a registry we could not reach is a network problem")
        for state in RegistryVerdictState.allCases where state.isTrustFailure {
            XCTAssertTrue(
                state.remedy == .doNotProceed || state.remedy == .updateClient,
                "\(state.rawValue) is a refusal; its remedy must not be a retry"
            )
        }
        // The one that was misclassified: our limitation, so update the client
        // — never distrust the registry, never touch the network.
        XCTAssertEqual(RegistryVerdictState.unverifiable.remedy, .updateClient)
        XCTAssertEqual(RegistryVerdictState.untrusted.remedy, .doNotProceed)
        XCTAssertEqual(RegistryVerdictState.verified.remedy, .none)
        XCTAssertEqual(RegistryVerdictState.pending.remedy, .wait)
        // Policy is the operator's setting, not their router.
        XCTAssertEqual(RegistryVerdictState.offline.remedy, .changeNetworkPolicy)
    }

    /// TEST8154: illegal states are unrepresentable — every contradiction is
    /// refused at construction and again at the wire boundary.
    func test8154_contradictoryVerdictsAreRefused() throws {
        XCTAssertThrowsError(try RegistryVerdict.stated(
            registryURL: url, state: .unreachable, detail: "", checkedAtUnixSeconds: now))
        XCTAssertThrowsError(try RegistryVerdict.stated(
            registryURL: url, state: .verified, detail: "all good", checkedAtUnixSeconds: now))
        XCTAssertThrowsError(try RegistryVerdict.stated(
            registryURL: url, state: .httpError, detail: "500", checkedAtUnixSeconds: now))
        XCTAssertThrowsError(try RegistryVerdict.stated(
            registryURL: url, state: .untrusted, detail: "nope", checkedAtUnixSeconds: now))
        XCTAssertThrowsError(try RegistryVerdict.stated(
            registryURL: "", state: .unreachable, detail: "timeout", checkedAtUnixSeconds: now))

        // A status on a state that never answered, smuggled in over the wire.
        let smuggled = """
        {"registry_url":"\(url)","state":"unreachable","detail":"timeout",
         "http_status":404,"chain_failure":null,"checked_at_unix_seconds":\(now)}
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(RegistryVerdict.self, from: Data(smuggled.utf8)),
            "a verdict that contradicts itself must be refused where the producer can still be named"
        )
        // A reason that contradicts the state it is filed under.
        let contradiction = """
        {"registry_url":"\(url)","state":"untrusted","detail":"x",
         "http_status":null,"chain_failure":"unsupported_envelope_format",
         "checked_at_unix_seconds":\(now)}
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(RegistryVerdict.self, from: Data(contradiction.utf8))
        )
    }

    /// TEST8155: the wire form round-trips with its invariants intact.
    func test8155_wireRoundTripAndRefusals() throws {
        let verdict = try RegistryVerdict.chainFailed(
            registryURL: url,
            reason: .unsupportedEnvelopeFormat,
            detail: "envelope format 'other/1' is not implemented by this build",
            checkedAtUnixSeconds: now
        )
        XCTAssertEqual(verdict.state, .unverifiable)
        let data = try JSONEncoder().encode(verdict)
        let decoded = try JSONDecoder().decode(RegistryVerdict.self, from: data)
        XCTAssertEqual(decoded, verdict)
        XCTAssertFalse(decoded.permitsAttachment)
        XCTAssertEqual(decoded.chainFailure, .unsupportedEnvelopeFormat,
                       "the failing check travels with the verdict, not only in prose")

        let http = try RegistryVerdict.httpError(
            registryURL: url, status: 404, detail: "registry answered HTTP 404",
            checkedAtUnixSeconds: now)
        XCTAssertEqual(http.httpStatus, 404)
        let roundTripped = try JSONDecoder().decode(
            RegistryVerdict.self, from: try JSONEncoder().encode(http))
        XCTAssertEqual(roundTripped.httpStatus, 404)

        // An http_error with no status is a producer bug, refused on the way in.
        let statusless = """
        {"registry_url":"\(url)","state":"http_error","detail":"answered badly",
         "http_status":null,"chain_failure":null,"checked_at_unix_seconds":\(now)}
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(RegistryVerdict.self, from: Data(statusless.utf8)))
        // An unknown state is refused rather than guessed at.
        let unknown = """
        {"registry_url":"\(url)","state":"flaky","detail":"hm",
         "http_status":null,"chain_failure":null,"checked_at_unix_seconds":\(now)}
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(RegistryVerdict.self, from: Data(unknown.utf8)))
    }

    /// TEST8157: the format discriminators are the library's, so no consumer
    /// can hold a divergent copy. A product rename that edits a client's
    /// private constant makes that client verify nothing while every other
    /// implementation keeps working — which is precisely what happened.
    func test8157_signatureFormatDiscriminatorsComeFromTheLibrary() {
        XCTAssertEqual(CSManifestSigFormat, "machinefabric-manifest-sig/1")
        XCTAssertEqual(CSReleaseKeyCertFormat, "machinefabric-release-key-cert/1")
    }
}
