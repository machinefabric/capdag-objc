//
//  CSCartridgeRegistryVersion.h
//  CapDAG
//
//  The baked cartridge-registry version — the Objective-C analogue of the Rust
//  engine's compile-time `CARTRIDGE_REGISTRY_VERSION` const (see capdag/build.rs).
//  It is the SINGLE source of the cartridge registry regime version for the ObjC
//  side: there is no runtime-environment fallback and no legacy v0 mode. v0 is
//  the implicit pre-versioning state and is never a valid value here (mirroring
//  build.rs, which fails the build below v1). Cartridge discovery pins its
//  on-disk `{slug}/v<N>/{channel}/…` scan to this value.
//
//  The value lives in `CSCartridgeRegistryVersion.m`, which is regenerated from
//  `schemas/cartridge-registry/registry-version.txt` by `scripts/lib/config.sh`
//  on every dx build (idempotent — only rewritten when the version changes), so
//  it can never silently drift from the registry the engine was built against.
//

#import <Foundation/Foundation.h>

/// The cartridge registry version this build of CapDAG is pinned to. Always >= 1.
extern const uint32_t CSBakedCartridgeRegistryVersion;
