#!/bin/bash
# Runs the test suite.
#
# With only the Command Line Tools installed (no full Xcode), Swift 6.4's
# build system doesn't reliably find swift-testing's macro plugin: roughly
# every other clean build fails with "plugin for module 'TestingMacros' not
# found", then succeeds on retry. Pointing the compiler at the plugin
# directory explicitly makes it deterministic. Full Xcode resolves the plugin
# itself and needs no flags.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVELOPER_DIR_PATH="$(xcode-select -p 2>/dev/null || true)"
PLUGIN_DIR="${DEVELOPER_DIR_PATH}/usr/lib/swift/host/plugins/testing"

if [[ "${DEVELOPER_DIR_PATH}" == *CommandLineTools* && -d "${PLUGIN_DIR}" ]]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "${PLUGIN_DIR}" "$@"
fi

exec swift test "$@"
