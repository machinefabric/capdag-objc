//
//  CSFabricManifestVersion.h
//  CapDAG
//
//  The baked fabric-registry manifest version — the Objective-C analogue of
//  the Rust engine's compile-time `FABRIC_MANIFEST_VERSION` const (see
//  capdag/build.rs). It is the SINGLE source of the manifest version for the
//  ObjC fabric registry: there is no runtime-environment fallback and no
//  legacy v0 / flat-path mode. v0 is the implicit pre-versioning state and is
//  never a valid value here (mirroring build.rs, which fails the build below
//  v1).
//
//  The value lives in `CSFabricManifestVersion.m`, which is regenerated from
//  `fabric/manifest-version.txt` by `scripts/lib/config.sh` on every dx build
//  (idempotent — only rewritten when the version changes), so it can never
//  silently drift from the registry the engine was built against.
//

#import <Foundation/Foundation.h>

/// The fabric manifest version this build of CapDAG is pinned to. Always >= 1.
extern const uint32_t CSBakedFabricManifestVersion;
