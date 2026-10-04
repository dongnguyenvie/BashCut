#!/bin/bash
# Tests the shared shell helpers in scripts/lib with the system bash (3.2 on macOS, which the scripts run under).
# Run by scripts/verify.sh test; needs no keychain, network or Xcode.
set -euo pipefail
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failures=0

check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL $name: expected '$expected', got '$actual'" >&2
        failures=$((failures + 1))
    fi
}

# Each case runs in a fresh bash with a scrubbed BASHCUT_* environment, against a throwaway .env.
in_lib() {
    env -i PATH="$PATH" HOME="$HOME" BASHCUT_ENV_FILE="$scratch/.env" ${extra_env[@]+"${extra_env[@]}"} \
        /bin/bash -c "set -euo pipefail; source '$scripts/lib/common.sh'; source '$scripts/lib/signing.sh'; $1"
}
extra_env=()

printf '%s\n' \
    '# comment' \
    'S3_BUCKET=ignored' \
    'BASHCUT_TEAM_ID=TEAM123' \
    'export BASHCUT_APPLE_ID="someone@example.com"' \
    "BASHCUT_NOTARY_PASSWORD='abcd-efgh'" \
    $'BASHCUT_RELEASE_IDENTITY=Developer ID Application: Example (TEAM123)\r' \
    'BASHCUT_EMPTY=' \
    'BASHCUT_INJECT=$(touch '"$scratch"'/ran)' \
    'NOT_BASHCUT_X=1' >"$scratch/.env"
printf 'BASHCUT_LAST=no newline' >>"$scratch/.env"

check "plain value" "TEAM123" "$(in_lib 'echo "$BASHCUT_TEAM_ID"')"
check "export prefix and double quotes" "someone@example.com" "$(in_lib 'echo "$BASHCUT_APPLE_ID"')"
check "single quotes" "abcd-efgh" "$(in_lib 'echo "$BASHCUT_NOTARY_PASSWORD"')"
check "CRLF line" "Developer ID Application: Example (TEAM123)" "$(in_lib 'echo "$BASHCUT_RELEASE_IDENTITY"')"
check "last line without newline" "no newline" "$(in_lib 'echo "$BASHCUT_LAST"')"
check "other keys ignored" "unset unset" "$(in_lib 'echo "${S3_BUCKET:-unset} ${NOT_BASHCUT_X:-unset}"')"
check "values are never executed" "\$(touch $scratch/ran)" "$(in_lib 'echo "$BASHCUT_INJECT"')"
check "no command ran" "absent" "$([[ -e "$scratch/ran" ]] && echo present || echo absent)"
extra_env=(BASHCUT_TEAM_ID=FROMENV)
check "environment wins over .env" "FROMENV" "$(in_lib 'echo "$BASHCUT_TEAM_ID"')"
extra_env=()
check "changes into the repository" "$(cd "$scripts/.." && pwd)" "$(in_lib 'pwd')"

check "require_env lists every missing key" "error: set BASHCUT_EMPTY BASHCUT_MISSING in .env (see .env.example)" \
    "$(in_lib 'require_env BASHCUT_TEAM_ID BASHCUT_EMPTY BASHCUT_MISSING' 2>&1 || true)"
check "require_env passes" "ok" "$(in_lib 'require_env BASHCUT_TEAM_ID && echo ok')"
check "require_tools lists every missing tool" "error: missing required tool(s): nope-a nope-b" \
    "$(in_lib 'require_tools bash nope-a nope-b' 2>&1 || true)"

check "version setting" "$(awk -F' *= *' '$1 == "MARKETING_VERSION" { v = $2 } END { print v }' "$scripts/../Configs/Version.xcconfig")" \
    "$(in_lib 'version_setting MARKETING_VERSION')"
check "valid version" "ok" "$(in_lib 'check_version 1.2.3 7 && echo ok')"
check "two-part version" "ok" "$(in_lib 'check_version 1.2 1 && echo ok')"
check "invalid version" "error: invalid version '1.x'" "$(in_lib 'check_version 1.x 1' 2>&1 || true)"
check "zero build number" "error: invalid build number '0'" "$(in_lib 'check_version 1.0 0' 2>&1 || true)"

identities='  1) AAAA "Apple Development: Someone (PERSON1)"
  2) BBBB "Developer ID Application: Other Team (OTHER99)"
  3) CCCC "Developer ID Application: Example (TEAM123)"
  4) DDDD "Developer ID Installer: Example (TEAM123)"
     4 valid identities found'
check "identity by team" "Developer ID Application: Example (TEAM123)" \
    "$(in_lib "identity_for_team 'Developer ID Application:' TEAM123 <<'EOF'
$identities
EOF")"
check "installer identity by team" "Developer ID Installer: Example (TEAM123)" \
    "$(in_lib "identity_for_team 'Developer ID Installer:' TEAM123 <<'EOF'
$identities
EOF")"
check "another team's identity is never picked" "" \
    "$(in_lib "identity_for_team 'Developer ID Application:' NOPE <<'EOF'
$identities
EOF")"
check "a team ID suffix is not a match" "" \
    "$(in_lib "identity_for_team 'Developer ID Application:' EAM123 <<'EOF'
$identities
EOF")"
extra_env=(BASHCUT_RELEASE_IDENTITY=Chosen)
check "explicit release identity wins" "Chosen" "$(in_lib 'developer_id_identity')"
extra_env=()

for script in "$scripts"/*.sh "$scripts"/lib/*.sh "$scripts"/ci/*.sh; do
    /bin/bash -n "$script" || { echo "FAIL syntax: $script" >&2; failures=$((failures + 1)); }
done

if [[ $failures -gt 0 ]]; then
    echo "$failures script library check(s) failed" >&2
    exit 1
fi
echo "script library checks passed"
