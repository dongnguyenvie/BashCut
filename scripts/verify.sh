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
        # AVPlayer, encoders and render contexts compete for native resources across suites. Keep these
        # suites sequential; concurrency regressions still exercise parallel work explicitly inside tests.
        test) swift test --no-parallel "$@" && (cd Packages/BashCutCore && swift test "$@") && {
                  if [ "$#" -eq 0 ]; then python3 scripts/test-mcp-process.py; fi
              } ;;
        lint) command -v swiftlint >/dev/null || { echo "error: SwiftLint is not installed"; return 1; }
              swiftlint lint --strict "$@" ;;
        # Builds the Xcode project generated from project.yml (which links the Package.swift products), so a
        # drift between the two build systems fails here instead of in Xcode.
        xcode) scripts/generate-project.sh && xcodebuild -project BashCut.xcodeproj -scheme BashCut \
                   -configuration Debug -derivedDataPath build/xcode CODE_SIGNING_ALLOWED=NO \
                   -skipPackagePluginValidation "${@:-build}" ;;
        perf) BASHCUT_PERF=1 swift test --filter EngineTests "$@" ;;
        uitest) echo "error: UI automation tests are not implemented in M0"; return 1 ;;
        *) echo "error: usage: scripts/verify.sh build|test|lint|xcode [build|test]|perf|uitest"; return 1 ;;
    esac
}
if run "$@" >"$log" 2>&1; then
    echo "PASS $mode — $log"
else
    echo "FAIL $mode — $log"
    grep -m 10 -E 'error:|failed|Issue recorded' "$log" || tail -10 "$log"
    exit 1
fi
