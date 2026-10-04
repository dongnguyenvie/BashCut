# Shared helpers for the scripts in scripts/. Sourced, never executed:
#
#     source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
#
# Sets REPO_ROOT and changes into it, and exports the BASHCUT_* keys of the repository's .env (git-ignored; keys in
# .env.example). Account details (team ID, Apple ID, passwords) live only there, never in tracked files.
#
# shellcheck shell=bash

[[ -n "${BASHCUT_LIB_COMMON_SOURCED:-}" ]] && return 0
BASHCUT_LIB_COMMON_SOURCED=1

BASHCUT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BASHCUT_LIB_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Exports BASHCUT_* keys from an env file without executing it. Values already in the environment win, so a
# one-off `BASHCUT_RELEASE_IDENTITY=... scripts/build-release.sh` overrides the file.
load_env() {
    local file="$1" line key value
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?(BASHCUT_[A-Z0-9_]+)=(.*)$ ]] || continue
        key="${BASH_REMATCH[2]}"
        value="${BASH_REMATCH[3]%$'\r'}"
        if [[ "$value" =~ ^\"(.*)\"$ || "$value" =~ ^\'(.*)\'$ ]]; then
            value="${BASH_REMATCH[1]}"
        fi
        [[ -n "${!key:-}" ]] || export "$key=$value"
    done <"$file"
}
load_env "${BASHCUT_ENV_FILE:-$REPO_ROOT/.env}"

# Fails with one message naming every missing key, not just the first.
require_env() {
    local key missing=()
    for key in "$@"; do
        [[ -n "${!key:-}" ]] || missing+=("$key")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "error: set ${missing[*]} in .env (see .env.example)" >&2
        return 1
    fi
}

require_tools() {
    local tool missing=()
    for tool in "$@"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "error: missing required tool(s): ${missing[*]}" >&2
        return 1
    fi
}

# A setting from Configs/Version.xcconfig, the single declaration of the app version (the last assignment wins,
# as in Xcode).
version_setting() {
    awk -F' *= *' -v key="$1" '$1 == key { value = $2 } END { print value }' "$REPO_ROOT/Configs/Version.xcconfig"
}

# Validates a marketing version and build number before anything is built under their names.
check_version() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+){1,2}$ ]] || { echo "error: invalid version '$1'" >&2; return 1; }
    [[ "$2" =~ ^[1-9][0-9]*$ ]] || { echo "error: invalid build number '$2'" >&2; return 1; }
}
