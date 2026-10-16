// The cartridge registry version this build speaks: the `/v<N>/` path of the
// registry manifest and the `{slug}/v<N>/{channel}/…` cartridge layout.
//
// The same value as `schemas/cartridge-registry/registry-version.txt`, which
// Rust bakes from at build time; Go and Python hold it as a constant as this
// file does. A registry version change commits the new value here with it,
// and `scripts/lib/config.sh` refuses to build while this file says another.
#import <stdint.h>

const uint32_t CSBakedCartridgeRegistryVersion = 2;
