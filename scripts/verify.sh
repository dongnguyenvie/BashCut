#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-build}"
shift || true
mkdir -p build/logs
log="build/logs/${mode}-$(date +%Y%m%d-%H%M%S).log"
run() {
    case "$mode" in
        build) swift build "$@" ;;
        test) swift test "$@" && (cd Packages/BashCutCore && swift test "$@") ;;
        lint) command -v swiftlint >/dev/null || { echo "error: SwiftLint is not installed"; return 1; }
              swiftlint lint --strict "$@" ;;
        perf) BASHCUT_PERF=1 swift test --filter EngineTests "$@" ;;
        uitest) echo "error: UI automation tests are not implemented in M0"; return 1 ;;
        *) echo "error: usage: scripts/verify.sh build|test|lint|perf|uitest"; return 1 ;;
    esac
}
if run "$@" >"$log" 2>&1; then
    echo "PASS $mode — $log"
else
    echo "FAIL $mode — $log"
    rg -m 10 'error:|failed|Issue recorded' "$log" || tail -10 "$log"
    exit 1
fi
