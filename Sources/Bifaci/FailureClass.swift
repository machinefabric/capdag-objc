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
}

/// A handler failure carrying its FULL identity: the machine-readable code
/// the cartridge's typed error declares (beside its `errorCode`), the
/// failure class it declares (whose problem it is), and the human message.
/// Handlers throw this instead of folding the code into message text; the
/// terminal ERR frame then carries all three fields to the engine.
/// Failures thrown as any other `Error` classify as `.internal` at the
/// frame boundary. (matches Rust `RuntimeError::Classified`)
public struct ClassifiedError: ClassifiedFailure, CustomStringConvertible, Sendable {
    public let code: String
    public let failureClass: FailureClass
    public let message: String

    public init(code: String, failureClass: FailureClass, message: String) {
        self.code = code
        self.failureClass = failureClass
        self.message = message
    }

    public var failureCode: String { code }
    public var failureMessage: String { message }

    public var description: String {
        return "\(code): \(message)"
    }
}

/// Resolve the identity a failed handler's terminal ERR frame declares
/// (docs/failure-taxonomy.md): the code and class from the emit source when
/// the thrown error is classified, HANDLER_ERROR/`.internal` when the
/// handler never declared one. (matches the Rust RuntimeError accessors at
/// the frame-emit boundary)
public func classifyHandlerError(_ error: Error) -> (code: String, failureClass: FailureClass, message: String) {
    if let classified = error as? ClassifiedFailure {
        return (classified.failureCode, classified.failureClass, classified.failureMessage)
    }
    // A classified op-layer failure keeps the identity it declared
    // (matches Rust dispatch_op's OpError → RuntimeError mapping).
    if let opError = error as? OpError, let code = opError.failureCode {
        return (code, opError.failureClass, opError.failureReason)
    }
    // A peer's error propagated as-is keeps the class the PEER's frame
    // declared.
    if let stream = error as? StreamError,
       case .remoteError(let code, let failureClass, let message) = stream {
        return (code, failureClass, message)
    }
    return ("HANDLER_ERROR", .internal, String(describing: error))
}
