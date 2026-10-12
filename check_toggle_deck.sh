#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
swift format lint --strict --recursive Sources Tests
bash -n install.sh launch_toggle_deck.sh stop_toggle_deck.sh
# Some Command Line Tools releases omit the Testing macro search path.
TEST_PLUGIN_ARGS=()
TEST_PLUGIN_DIR="$(dirname "$(xcrun --find swiftc)")/../lib/swift/host/plugins/testing"
if [ -d "$TEST_PLUGIN_DIR" ]; then
    TEST_PLUGIN_ARGS=(-Xswiftc -plugin-path -Xswiftc "$TEST_PLUGIN_DIR")
fi
swift test --enable-swift-testing --disable-xctest "${TEST_PLUGIN_ARGS[@]}" -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
