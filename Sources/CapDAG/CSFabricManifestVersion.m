// The fabric manifest version this build's fabric registry is pinned to.
//
// The same value as `fabric/manifest-version.txt`, which Rust bakes from at
// build time. There is no runtime-environment fallback and no legacy v0 mode.
// A manifest version change commits the new value here with it, and
// `scripts/lib/config.sh` refuses to build while this file says another.
#import <stdint.h>

const uint32_t CSBakedFabricManifestVersion = 8;
