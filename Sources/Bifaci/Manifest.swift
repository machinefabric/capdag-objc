//
//  Manifest.swift
//  Bifaci
//
//  Build-time manifest/registry-identity helpers. Mirrors the free
//  functions in `capdag/src/bifaci/manifest.rs`.
//

import Foundation

/// Failure raised when a build-time registry-identity value is invalid.
///
/// The single case mirrors the `panic!` in Rust's
/// `registry_url_from_build_env`: an exported-but-empty
/// `MFR_CARTRIDGE_REGISTRY_URL` is neither a dev build nor a valid
/// registry identity, and MUST fail hard so the build can never silently
/// hash the empty string into a fake registry slug. Surfaced as a thrown
/// error (the catchable Swift analog of Rust's compile-time panic) so the
/// exact message is asserted by callers and tests — there is no silent
/// fallback that would paper over the build-script bug.
public enum ManifestBuildEnvError: Error, Equatable, CustomStringConvertible {
    /// `MFR_CARTRIDGE_REGISTRY_URL` was set to the empty string.
    case emptyRegistryURL

    public var message: String {
        switch self {
        case .emptyRegistryURL:
            return "MFR_CARTRIDGE_REGISTRY_URL must be unset for dev builds or set to a non-empty registry URL for published builds; empty string is invalid"
        }
    }

    public var description: String { message }
}

/// Validate a build-time cartridge registry URL, mirroring Rust's
/// `registry_url_from_build_env` (`capdag/src/bifaci/manifest.rs`).
///
/// It encodes the registry-identity contract a cartridge or engine bakes
/// in at build time. The argument is the optional build-env value (mirror
/// of Rust's `option_env!("MFR_CARTRIDGE_REGISTRY_URL")` — Swift's
/// `String?` stands in for `Option<&'static str>`):
///
///   - `nil`            => dev build. Registry identity is absent; the
///                         build uses the on-disk `dev/` slot. Returns nil.
///   - non-empty string => published-registry build. Returns it unchanged.
///   - empty string     => INVALID. The variable was exported with an
///                         empty value — neither a dev build nor a valid
///                         registry identity. This MUST fail hard so the
///                         build cannot silently hash the empty string into
///                         a fake registry slug. Throws
///                         `ManifestBuildEnvError.emptyRegistryURL`.
///
/// Failing hard on the empty-but-set case is deliberate: a fallback that
/// treated `""` as a dev build would hide a real build-script bug. Callers
/// that genuinely mean a dev build pass `nil`, never the empty string.
public func registryURLFromBuildEnv(_ raw: String?) throws -> String? {
    guard let url = raw else {
        return nil
    }
    if url.isEmpty {
        throw ManifestBuildEnvError.emptyRegistryURL
    }
    return url
}
