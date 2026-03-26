#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAPDAG_DIR="$SCRIPT_DIR/../../capdag"
TESTCARTRIDGE="$CAPDAG_DIR/testcartridge/target/debug/testcartridge"

# Build testcartridge if binary is missing or source is newer
NEEDS_BUILD=0
if [ ! -f "$TESTCARTRIDGE" ]; then
    echo "testcartridge binary not found, building..."
    NEEDS_BUILD=1
else
    # Check if any source file is newer than the binary
    if find "$CAPDAG_DIR/testcartridge/src" -name '*.rs' -newer "$TESTCARTRIDGE" 2>/dev/null | grep -q .; then
        echo "testcartridge source changed, rebuilding..."
        NEEDS_BUILD=1
    fi
fi

if [ "$NEEDS_BUILD" -eq 1 ]; then
    (cd "$CAPDAG_DIR/testcartridge" && cargo build)
fi

# Run
cd "$SCRIPT_DIR"
swift run testcartridge-host --plugin "$TESTCARTRIDGE" "$@"
