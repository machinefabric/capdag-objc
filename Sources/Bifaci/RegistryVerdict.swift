import Foundation

// What a consumer concluded about a cartridge registry, as a closed vocabulary
// shared by every implementation. Mirrors Rust `bifaci/registry_verdict.rs`.
//
// A REGISTRY IS NOT A CARTRIDGE. A registry verdict is one fact per registry
// URL, shared by every cartridge that claims provenance from it; a cartridge
// attachment error is one fact per cartridge. Squeezing the first through the
// second is how a signature that failed verification came to be reported as a
// network outage, with "check your connection" as the remedy.
//
// The vocabulary separates the two things a consumer can conclude:
//
//   * It could not get an answer — `.offline`, `.unreachable`, `.httpError`,
//     `.malformed`. We do not know what the registry says. Retrying, or
//     changing a setting, may change the answer.
//   * It got an answer and refused it — `.unsigned`, `.untrusted`,
//     `.unverifiable`. We know what the registry says and we will not act on
//     it. Retrying changes nothing.
//
// Those two groups have opposite remedies, which is the whole reason the
// distinction exists.

/// Format discriminator for release-key certificates. Mirrors Rust
/// `RELEASE_KEY_CERT_FORMAT`.
///
/// THE WIRE FORMAT IS NOT A PRODUCT NAME. Every verifier — this library, a
/// client's in-process verifier, the publisher — must compare against THIS
/// constant. A client holding its own copy can be renamed away from the
/// protocol by a search-and-replace, verify nothing, and report the registry as
/// unreachable; that is exactly what happened, and it is why these live here.
public let CSReleaseKeyCertFormat = "machinefabric-release-key-cert/1"

/// Format discriminator for manifest signature envelopes. Mirrors Rust
/// `MANIFEST_SIG_FORMAT`.
public let CSManifestSigFormat = "machinefabric-manifest-sig/1"

/// What a consumer concluded about a registry.
public enum RegistryVerdictState: String, Codable, Hashable, Sendable, CaseIterable {
    /// Fetched, chain-verified and parsed. The only state in which a cartridge
    /// from this registry may attach.
    case verified
    /// No verdict yet — the first check has not run, or is in flight. NOT a
    /// failure: a consumer that renders this as an error tells every operator
    /// their registry is broken for the first seconds of every launch.
    case pending
    /// The consumer's own network policy forbade the request. Nothing was
    /// attempted. The remedy is a setting, not the network, which is why this
    /// is not `.unreachable`.
    case offline
    /// The request could not be completed: DNS, refused, timeout, TLS. The only
    /// state for which "check your connection" is sound advice.
    case unreachable
    /// The registry answered, and the answer was an HTTP error. Carries the
    /// status, because 404 and 5xx are different situations for the operator.
    case httpError = "http_error"
    /// The registry answered with a body this build cannot read as a manifest.
    case malformed
    /// No signature sidecar where one is required. An unsigned registry is
    /// refused rather than trusted.
    case unsigned
    /// The signature chain was evaluated and REJECTED: a certificate no baked
    /// root vouches for, too few root signatures, an expired or not-yet-valid
    /// certificate, a certificate bound to another environment, or a manifest
    /// signature that does not verify. The registry's problem.
    case untrusted
    /// The signature chain could NOT be evaluated: an envelope or certificate
    /// in a format this build does not implement, or one malformed beyond
    /// parsing. This build's problem — most often a client older or newer than
    /// the publisher.
    case unverifiable

    /// Whether a cartridge claiming provenance from a registry in this state
    /// may attach. True for `.verified` alone: every other state, the hopeful
    /// ones included, means the claim is unconfirmed.
    public var permitsAttachment: Bool { self == .verified }

    /// Whether this state is a refusal of an answer we DID get, as opposed to
    /// not having got one. A refusal will not change on retry.
    public var isTrustFailure: Bool {
        switch self {
        case .unsigned, .untrusted, .unverifiable: return true
        case .verified, .pending, .offline, .unreachable, .httpError, .malformed: return false
        }
    }

    /// Whether trying again, unattended, could plausibly reach a different
    /// verdict. A trust failure never can; neither does a policy that forbids
    /// the request, until the policy changes.
    public var isTransient: Bool {
        switch self {
        case .pending, .unreachable, .httpError, .malformed: return true
        case .verified, .offline, .unsigned, .untrusted, .unverifiable: return false
        }
    }
}

/// WHAT TO DO ABOUT A REGISTRY IN A GIVEN STATE. Mirrors Rust
/// `RegistryRemedy`.
///
/// The remedy follows from the state and nothing else. It used to be a sentence
/// glued onto the failure message at the point the record was built — "Check
/// the network connection and try again." — appended whatever the cause, so a
/// signature this build could not read sent operators to their router. A remedy
/// asserted as fact regardless of what failed is worse than none.
///
/// This is the ACTION, not its wording: a CLI prints a line, a desktop client
/// offers a control. Both derive them from here, so neither can invent a remedy
/// the state does not warrant.
public enum RegistryRemedy: String, Codable, Hashable, Sendable, CaseIterable {
    /// Nothing to do — the registry verified.
    case none
    /// A check is in flight and will answer on its own.
    case wait
    /// The machine cannot reach the registry. Check the connection.
    case checkNetwork = "check_network"
    /// This build was told not to go out. Change the network policy.
    case changeNetworkPolicy = "change_network_policy"
    /// The registry answered badly; it is the registry's side to fix.
    case retryLater = "retry_later"
    /// This build cannot read the registry's signature format. Update the
    /// client — the registry is not at fault and the network is not involved.
    case updateClient = "update_client"
    /// The registry's answer was rejected. Do not proceed.
    case doNotProceed = "do_not_proceed"
}

extension RegistryVerdictState {
    /// The one thing to do about a registry in this state.
    ///
    /// Exhaustive by construction: adding a state without deciding its remedy
    /// does not compile, which is the point — a state whose remedy nobody chose
    /// would get whatever sentence was nearest.
    public var remedy: RegistryRemedy {
        switch self {
        case .verified: return .none
        case .pending: return .wait
        case .offline: return .changeNetworkPolicy
        case .unreachable: return .checkNetwork
        case .httpError, .malformed: return .retryLater
        case .unverifiable: return .updateClient
        case .unsigned, .untrusted: return .doNotProceed
        }
    }
}

/// Why a signature chain failed, as a closed vocabulary. Mirrors Rust
/// `ChainFailureReason`.
///
/// Every implementation that verifies a manifest reports one of these, and
/// `RegistryVerdictState.forChainFailure` turns it into a verdict. That is what
/// keeps "unsupported format" from being classified as a network problem in one
/// implementation and a trust problem in another.
public enum ChainFailureReason: String, Codable, Hashable, Sendable, CaseIterable {
    case malformedEnvelope = "malformed_envelope"
    case unsupportedEnvelopeFormat = "unsupported_envelope_format"
    case malformedCertificate = "malformed_certificate"
    case unsupportedCertificateFormat = "unsupported_certificate_format"
    case emptyCertificateList = "empty_certificate_list"
    case insufficientRootSignatures = "insufficient_root_signatures"
    case expiredCertificate = "expired_certificate"
    case notYetValidCertificate = "not_yet_valid_certificate"
    case environmentMismatch = "environment_mismatch"
    case keyIDMismatch = "key_id_mismatch"
    case noAuthorizingCertificate = "no_authorizing_certificate"
    case manifestSignatureInvalid = "manifest_signature_invalid"
}

extension RegistryVerdictState {
    /// The verdict a chain failure produces.
    ///
    /// COULD THE CHAIN BE EVALUATED AT ALL? A format this build does not
    /// implement, or bytes it cannot parse, means no judgement was reached —
    /// `.unverifiable`, remedied by updating the client. Everything else means
    /// the chain WAS judged and found wanting — `.untrusted`, remedied by not
    /// proceeding.
    public static func forChainFailure(_ reason: ChainFailureReason) -> RegistryVerdictState {
        switch reason {
        case .malformedEnvelope, .unsupportedEnvelopeFormat, .malformedCertificate,
             .unsupportedCertificateFormat, .emptyCertificateList:
            return .unverifiable
        case .insufficientRootSignatures, .expiredCertificate, .notYetValidCertificate,
             .environmentMismatch, .keyIDMismatch, .noAuthorizingCertificate,
             .manifestSignatureInvalid:
            return .untrusted
        }
    }
}

/// A verdict that does not describe a possible situation.
public enum RegistryVerdictError: Error, Equatable, CustomStringConvertible {
    case missingRegistryURL
    case missingDetail(RegistryVerdictState)
    case statesNoFailureButCarriesDetail(RegistryVerdictState, String)
    case missingHTTPStatus
    case unexpectedHTTPStatus(RegistryVerdictState)
    case missingChainFailure(RegistryVerdictState)
    case unexpectedChainFailure(RegistryVerdictState)

    public var description: String {
        switch self {
        case .missingRegistryURL:
            return "a registry verdict must name the registry it is about"
        case .missingDetail(let state):
            return "a '\(state.rawValue)' verdict must carry the detail that explains it"
        case .statesNoFailureButCarriesDetail(let state, let detail):
            return "a '\(state.rawValue)' verdict states no failure, so it carries no detail (got \(detail))"
        case .missingHTTPStatus:
            return "an 'http_error' verdict must carry the status the registry answered with"
        case .unexpectedHTTPStatus(let state):
            return "only an 'http_error' verdict carries an HTTP status (got one on '\(state.rawValue)')"
        case .missingChainFailure(let state):
            return "a '\(state.rawValue)' verdict must carry the chain failure reason that produced it"
        case .unexpectedChainFailure(let state):
            return "only a trust failure carries a chain failure reason (got one on '\(state.rawValue)')"
        }
    }
}

/// What a consumer concluded about one registry, and why. Mirrors Rust
/// `RegistryVerdict`.
///
/// Illegal combinations are unrepresentable: the factories take exactly what
/// their state requires, and `validate()` re-checks every invariant on the way
/// in from the wire. A verdict that says "http_error" without a status, or
/// "verified" with a failure detail, is a bug in the producer and is refused at
/// the boundary rather than rendered as a contradiction.
public struct RegistryVerdict: Codable, Hashable, Sendable {
    /// The registry this verdict is about — the verbatim URL a cartridge
    /// declares, which is what consumers join on.
    public let registryURL: String
    public let state: RegistryVerdictState
    /// One operator-visible line saying what happened. Empty exactly when the
    /// state states no failure (`.verified`, `.pending`).
    public let detail: String
    /// The HTTP status the registry answered with. Present exactly on
    /// `.httpError`.
    public let httpStatus: Int?
    /// Which chain check failed. Present exactly on `.untrusted` and
    /// `.unverifiable` — never on `.unsigned`, where there was no chain.
    public let chainFailure: ChainFailureReason?
    /// When this verdict was reached, unix seconds.
    public let checkedAtUnixSeconds: Int64

    private enum CodingKeys: String, CodingKey {
        case registryURL = "registry_url"
        case state
        case detail
        case httpStatus = "http_status"
        case chainFailure = "chain_failure"
        case checkedAtUnixSeconds = "checked_at_unix_seconds"
    }

    private init(
        registryURL: String,
        state: RegistryVerdictState,
        detail: String,
        httpStatus: Int?,
        chainFailure: ChainFailureReason?,
        checkedAtUnixSeconds: Int64
    ) {
        self.registryURL = registryURL
        self.state = state
        self.detail = detail
        self.httpStatus = httpStatus
        self.chainFailure = chainFailure
        self.checkedAtUnixSeconds = checkedAtUnixSeconds
    }

    /// The registry answered, verified and parsed.
    public static func verified(registryURL: String, checkedAtUnixSeconds: Int64) throws -> RegistryVerdict {
        let verdict = RegistryVerdict(
            registryURL: registryURL, state: .verified, detail: "",
            httpStatus: nil, chainFailure: nil, checkedAtUnixSeconds: checkedAtUnixSeconds
        )
        try verdict.validate()
        return verdict
    }

    /// No verdict yet. Carries no time, because nothing has been checked.
    public static func pending(registryURL: String) throws -> RegistryVerdict {
        let verdict = RegistryVerdict(
            registryURL: registryURL, state: .pending, detail: "",
            httpStatus: nil, chainFailure: nil, checkedAtUnixSeconds: 0
        )
        try verdict.validate()
        return verdict
    }

    /// A state that carries only a detail line: `.offline`, `.unreachable`,
    /// `.malformed`, `.unsigned`. The other states have their own factories
    /// because they require more, and this refuses them rather than letting a
    /// caller build a verdict missing what it needs.
    public static func stated(
        registryURL: String,
        state: RegistryVerdictState,
        detail: String,
        checkedAtUnixSeconds: Int64
    ) throws -> RegistryVerdict {
        switch state {
        case .offline, .unreachable, .malformed, .unsigned:
            break
        case .verified, .pending:
            throw RegistryVerdictError.statesNoFailureButCarriesDetail(state, detail)
        case .httpError:
            throw RegistryVerdictError.missingHTTPStatus
        case .untrusted, .unverifiable:
            throw RegistryVerdictError.missingChainFailure(state)
        }
        let verdict = RegistryVerdict(
            registryURL: registryURL, state: state, detail: detail,
            httpStatus: nil, chainFailure: nil, checkedAtUnixSeconds: checkedAtUnixSeconds
        )
        try verdict.validate()
        return verdict
    }

    /// The registry answered with an HTTP error.
    public static func httpError(
        registryURL: String,
        status: Int,
        detail: String,
        checkedAtUnixSeconds: Int64
    ) throws -> RegistryVerdict {
        let verdict = RegistryVerdict(
            registryURL: registryURL, state: .httpError, detail: detail,
            httpStatus: status, chainFailure: nil, checkedAtUnixSeconds: checkedAtUnixSeconds
        )
        try verdict.validate()
        return verdict
    }

    /// A signature chain that failed. The state FOLLOWS from the reason, so a
    /// caller cannot file an unreadable format as a rejected key or the other
    /// way round.
    public static func chainFailed(
        registryURL: String,
        reason: ChainFailureReason,
        detail: String,
        checkedAtUnixSeconds: Int64
    ) throws -> RegistryVerdict {
        let verdict = RegistryVerdict(
            registryURL: registryURL,
            state: RegistryVerdictState.forChainFailure(reason),
            detail: detail,
            httpStatus: nil,
            chainFailure: reason,
            checkedAtUnixSeconds: checkedAtUnixSeconds
        )
        try verdict.validate()
        return verdict
    }

    /// Every invariant this type promises, checked. A verdict that fails this
    /// has no meaning and must not travel.
    public func validate() throws {
        if registryURL.isEmpty { throw RegistryVerdictError.missingRegistryURL }
        switch state {
        case .verified, .pending:
            if !detail.isEmpty {
                throw RegistryVerdictError.statesNoFailureButCarriesDetail(state, detail)
            }
        default:
            if detail.isEmpty { throw RegistryVerdictError.missingDetail(state) }
        }
        if state == .httpError {
            if httpStatus == nil { throw RegistryVerdictError.missingHTTPStatus }
        } else if httpStatus != nil {
            throw RegistryVerdictError.unexpectedHTTPStatus(state)
        }
        if state == .untrusted || state == .unverifiable {
            guard let reason = chainFailure else {
                throw RegistryVerdictError.missingChainFailure(state)
            }
            // The reason must be one that produces THIS state, or the verdict
            // contradicts itself.
            if RegistryVerdictState.forChainFailure(reason) != state {
                throw RegistryVerdictError.unexpectedChainFailure(state)
            }
        } else if chainFailure != nil {
            throw RegistryVerdictError.unexpectedChainFailure(state)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        registryURL = try container.decode(String.self, forKey: .registryURL)
        state = try container.decode(RegistryVerdictState.self, forKey: .state)
        detail = try container.decode(String.self, forKey: .detail)
        httpStatus = try container.decodeIfPresent(Int.self, forKey: .httpStatus)
        chainFailure = try container.decodeIfPresent(ChainFailureReason.self, forKey: .chainFailure)
        checkedAtUnixSeconds = try container.decode(Int64.self, forKey: .checkedAtUnixSeconds)
        // A contradictory verdict is refused ON THE WAY IN, where the producer
        // can still be named, rather than surfacing later as an interface that
        // says two things at once.
        try validate()
    }

    /// Whether a cartridge from this registry may attach.
    public var permitsAttachment: Bool { state.permitsAttachment }
}
