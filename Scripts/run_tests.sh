#!/bin/bash
# Runs the test suite.
#
# On machines with only the Xcode Command Line Tools installed (no full
# Xcode), swift-testing's framework and its interop dylib live outside the
# default search paths, so they have to be pointed at explicitly. With full
# Xcode installed, a plain `swift test` works too.
set -euo pipefail

cd "$(dirname "$0")/.."

CLT_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
CLT_LIB="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [ -d "${CLT_FRAMEWORKS}/Testing.framework" ]; then
    swift test \
        -Xswiftc -F -Xswiftc "${CLT_FRAMEWORKS}" \
        -Xlinker -rpath -Xlinker "${CLT_FRAMEWORKS}" \
        -Xlinker -rpath -Xlinker "${CLT_LIB}" \
        "$@"
else
    swift test "$@"
fi
