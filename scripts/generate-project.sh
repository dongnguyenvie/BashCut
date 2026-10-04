#!/bin/bash
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
require_tools xcodegen || { echo "       XcodeGen >= 2.46 generates BashCut.xcodeproj from project.yml" >&2; exit 1; }
xcodegen generate
