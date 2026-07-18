import Ops

// The failure taxonomy — WHOSE problem a failure is
// (docs/failure-taxonomy.md) — is defined ONCE in `Ops.FailureClass` (the
// leaf package of the error path — Bifaci depends on Ops, exactly like Rust
// capdag depends on ops) and re-exported here as the cartridge-contract
// surface. The bifaci ERR frame carries the class over the wire (meta key
// "class"); all four language runtimes share the same token vocabulary. No
// layer ever infers another layer's class from message text — an error that
// reaches a boundary without a declared class is `.internal` (unclassified
// means "ours", never a guess).

/// Re-export: `Bifaci.FailureClass` IS `Ops.FailureClass` — one type, one
/// vocabulary, matching Rust's `pub use ops::failure::FailureClass`.
public typealias FailureClass = Ops.FailureClass

/// The declaration convention every cartridge's typed error follows (the
/// Swift analog of the Rust `error_code()` + `failure_class()` pair): the
/// code, the class, and the leaf message are declared ON the error type, at
/// its definition site, and the frame boundary reads them structurally.
public protocol ClassifiedFailure: Error {
    /// The machine-readable code (e.g. `CONTEXT_OVERFLOW`).
    var failureCode: String { get }
    /// Whose problem the failure is (docs/failure-taxonomy.md).
    var failureClass: FailureClass { get }
    /// The emit source's own LEAF human message.
    var failureMessage: String { get }
    /// The media URN of the argument the failure is attributed to, declared
    /// at the emit source (docs/failure-taxonomy.md); nil when the failure
    /// has no attribution.
    var failureArgUrn: String? { get }
}

public extension ClassifiedFailure {
    /// A classified failure that declares no argument attribution carries
    /// none — attribution is opt-in at the emit source, never inferred.
    var failureArgUrn: String? { nil }
}

/// A handler failure carrying its FULL identity: the machine-readable code
/// the cartridge's typed error declares (beside its `errorCode`), the
/// failure class it declares (whose problem it is), the human message, and
/// — when the failure is attributed to a specific argument — the media URN
/// of that argument, declared at the emit source. Handlers throw this
/// instead of folding the code into message text; the terminal ERR frame
/// then carries the declared fields to the engine. Failures thrown as any
/// other `Error` classify as `.internal` at the frame boundary.
/// (matches Rust `RuntimeError::Classified`)
public struct ClassifiedError: ClassifiedFailure, CustomStringConvertible, Sendable {
    public let code: String
    public let failureClass: FailureClass
    public let message: String
    /// The media URN of the argument the failure is attributed to, declared
    /// at the emit source alongside the class (docs/failure-taxonomy.md);
    /// nil when the failure has no attribution.
    public let argUrn: String?

    public init(code: String, failureClass: FailureClass, message: String, argUrn: String? = nil) {
        self.code = code
        self.failureClass = failureClass
        self.message = message
        self.argUrn = argUrn
    }

    public var failureCode: String { code }
    public var failureMessage: String { message }
    public var failureArgUrn: String? { argUrn }

    public var description: String {
        return "\(code): \(message)"
    }
}

/// Resolve the identity a failed handler's terminal ERR frame declares
/// (docs/failure-taxonomy.md): the code, class, and argument attribution
/// from the emit source when the thrown error is classified,
/// HANDLER_ERROR/`.internal` without attribution when the handler never
/// declared one. (matches the Rust RuntimeError accessors at the frame-emit
/// boundary)
public func classifyHandlerError(_ error: Error) -> (code: String, failureClass: FailureClass, message: String, argUrn: String?) {
    if let classified = error as? ClassifiedFailure {
        return (classified.failureCode, classified.failureClass, classified.failureMessage, classified.failureArgUrn)
    }
    // A classified op-layer failure keeps the identity it declared
    // (matches Rust dispatch_op's OpError → RuntimeError mapping).
    if let opError = error as? OpError, let code = opError.failureCode {
        return (code, opError.failureClass, opError.failureReason, opError.failureArgUrn)
    }
    // A peer's error propagated as-is keeps the class and attribution the
    // PEER's frame declared.
    if let stream = error as? StreamError,
       case .remoteError(let code, let failureClass, let message, let argUrn) = stream {
        return (code, failureClass, message, argUrn)
    }
    return ("HANDLER_ERROR", .internal, String(describing: error), nil)
}
