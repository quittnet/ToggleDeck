#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
swift format lint --strict --recursive Sources Tests
bash -n install.sh launch_toggle_deck.sh stop_toggle_deck.sh
swift test -Xswiftc -warnings-as-errors
swift build -c release -Xswiftc -warnings-as-errors
