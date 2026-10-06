#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-build}"
shift || true
mkdir -p build/logs
log="build/logs/${mode}-$(date +%Y%m%d-%H%M%S).log"
socket_suites='\.(AutomationTests|AutomationControllerTests)/'
run() {
    case "$mode" in
        build) swift build "$@" ;;
        # Suites run in parallel, except the Unix-socket suites: their latency assertions and client timeouts
        # do not hold while CPU-bound render suites saturate the machine, so they get a quiet second pass.
        # Filtered runs (`verify.sh test --filter X`) stay sequential.
        test) if [ "$#" -eq 0 ]; then
                  swift test --skip "$socket_suites" && swift test --skip-build --no-parallel --filter "$socket_suites" \
                      && (cd Packages/BashCutCore && swift test) && python3 scripts/test-mcp-process.py \
                      && scripts/ci/test-script-lib.sh && scripts/update-acknowledgements.py --check
              else
                  swift test --no-parallel "$@" && (cd Packages/BashCutCore && swift test "$@")
              fi ;;
        lint) command -v swiftlint >/dev/null || { echo "error: SwiftLint is not installed"; return 1; }
              swiftlint lint --strict "$@" ;;
        # Builds the Xcode project generated from project.yml (which links the Package.swift products), so a
        # drift between the two build systems fails here instead of in Xcode.
        xcode) scripts/generate-project.sh && xcodebuild -project BashCut.xcodeproj -scheme BashCut \
                   -configuration Debug -derivedDataPath build/xcode CODE_SIGNING_ALLOWED=NO \
                   -skipPackagePluginValidation "${@:-build}" ;;
        # Only the EngineTests suite, alone: a bare "EngineTests" filter also matched the whole
        # BashCutEngineTests module and timed the 20-clip export against ~100 concurrent tests.
        # Then the plugin catalog refresh with 1000 generated plugins (#103), in release like the shipped app.
        # Plugin views (#390): parsing the largest view and requirement checks, then session round trips.
        perf) BASHCUT_PERF=1 swift test --no-parallel --filter 'BashCutEngineTests\.EngineTests/' "$@" \
                  && (cd Packages/BashCutCore && BASHCUT_PERF=1 swift test -c release \
                      --filter 'PluginCatalogPerfTests|PluginViewPerfTests') \
                  && BASHCUT_PERF=1 swift test -c release --filter PluginViewSessionPerfTests ;;
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
