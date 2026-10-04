# Code-signing helpers for the release scripts. Sourced, never executed; needs common.sh first.
#
# shellcheck shell=bash

[[ -n "${BASHCUT_LIB_SIGNING_SOURCED:-}" ]] && return 0
BASHCUT_LIB_SIGNING_SOURCED=1

# Filters `security find-identity -v` output (stdin) to the first identity named "<prefix>... (<team>)". Matching
# by team means another account's certificates in the same keychain are never picked.
identity_for_team() {
    local prefix="$1" team="$2"
    awk -F'"' -v prefix="$prefix" -v team="($team)" \
        'index($2, prefix) == 1 && substr($2, length($2) - length(team) + 1) == team { print $2; exit }'
}

# Usage: find_identity "Developer ID Application:" [codesigning]
find_identity() {
    security find-identity -v ${2:+-p "$2"} 2>/dev/null | identity_for_team "$1" "$BASHCUT_TEAM_ID"
}

# Checks every Mach-O in an app bundle the way notarization will: a secure timestamp and the expected signer on
# each, and the hardened runtime on each executable. Dylibs (Xcode's Swift compatibility libraries) need no runtime
# flag. Failing here takes seconds; a notary rejection takes minutes and a log download.
verify_app_signatures() {
    local app="$1" identity="$2" file kind details
    codesign --verify --deep --strict "$app" || return 1
    while IFS= read -r -d '' file; do
        kind="$(file -b "$file")"
        [[ "$kind" == *Mach-O* ]] || continue
        details="$(codesign -dvv "$file" 2>&1)"
        if [[ "$kind" == *executable* ]] && ! grep -q 'flags=.*runtime' <<<"$details"; then
            echo "error: no hardened runtime: ${file#"$app"/}" >&2
            return 1
        fi
        grep -q '^Timestamp=' <<<"$details" || { echo "error: no secure timestamp: ${file#"$app"/}" >&2; return 1; }
        grep -qx "Authority=$identity" <<<"$details" \
            || { echo "error: not signed by $identity: ${file#"$app"/}" >&2; return 1; }
    done < <(find "$app" -type f -perm -u+x -print0)
}

# Resolves the identity to sign with: BASHCUT_RELEASE_IDENTITY, else the team's Developer ID Application identity.
# Prints it; fails with what to do when there is none.
developer_id_identity() {
    local identity="${BASHCUT_RELEASE_IDENTITY:-}"
    [[ -n "$identity" ]] || identity="$(find_identity "Developer ID Application:" codesigning)"
    if [[ -z "$identity" ]]; then
        echo "error: no \"Developer ID Application\" identity for BASHCUT_TEAM_ID in the keychain." >&2
        echo "       Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application." >&2
        return 1
    fi
    printf '%s\n' "$identity"
}

# The same for installer packages: BASHCUT_INSTALLER_IDENTITY, else the team's Developer ID Installer identity.
installer_identity() {
    local identity="${BASHCUT_INSTALLER_IDENTITY:-}"
    [[ -n "$identity" ]] || identity="$(find_identity "Developer ID Installer:")"
    if [[ -z "$identity" ]]; then
        echo "error: no \"Developer ID Installer\" identity for BASHCUT_TEAM_ID in the keychain." >&2
        echo "       Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Installer." >&2
        return 1
    fi
    printf '%s\n' "$identity"
}
