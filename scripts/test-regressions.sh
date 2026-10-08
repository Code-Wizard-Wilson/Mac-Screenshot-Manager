#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_DIR="$(mktemp -d /private/tmp/screenshot-manager-tests.XXXXXX)"
swiftc -swift-version 6 -target "$(uname -m)-apple-macosx14.0" -D REGRESSION_TESTING \
  "$ROOT"/ScreenshotManager/*.swift "$ROOT/Tests/RegressionChecks.swift" \
  -o "$CHECK_DIR/RegressionChecks"
"$CHECK_DIR/RegressionChecks"
