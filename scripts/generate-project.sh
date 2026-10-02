#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo "XcodeGen >= 2.46 is required; install it to generate the Xcode project."; exit 1; }
xcodegen generate
