# Notarizes an artifact, staples the ticket and proves Gatekeeper accepts it. Sourced, never executed; needs
# common.sh first. Credentials come from .env: BASHCUT_APPLE_ID, BASHCUT_NOTARY_PASSWORD (an app-specific password
# from appleid.apple.com) and BASHCUT_TEAM_ID.
#
# The two checks after stapling are not redundant. spctl asks Gatekeeper, which fetches a missing ticket from
# Apple over the network, so an artifact that was notarized but never stapled still passes it. Only `stapler
# validate` proves the ticket is inside the artifact, which is what an offline Mac needs.
#
# shellcheck shell=bash

[[ -n "${BASHCUT_LIB_NOTARIZE_SOURCED:-}" ]] && return 0
BASHCUT_LIB_NOTARIZE_SOURCED=1

require_notary_env() {
    require_env BASHCUT_TEAM_ID BASHCUT_APPLE_ID BASHCUT_NOTARY_PASSWORD
}

# Usage: notarize_and_staple <path> [execute|open|install]
#
# The assessment type is "execute" for an app, "open" for a disk image and "install" for a package. Stapling
# rewrites the artifact, so anything packaged from it (a zip, a checksum) must be made after this returns.
notarize_and_staple() {
    local path="${1:?notarize_and_staple needs a path}" assessment="${2:-execute}"
    local name submission scratch="" result id status
    local -a credentials=(--apple-id "$BASHCUT_APPLE_ID" --password "$BASHCUT_NOTARY_PASSWORD"
        --team-id "$BASHCUT_TEAM_ID")
    name="$(basename "$path")"

    # notarytool takes an archive, not a bundle; the ticket is stapled into the bundle itself afterwards.
    submission="$path"
    if [[ -d "$path" ]]; then
        scratch="$(mktemp -d)"
        submission="$scratch/$name.zip"
        ditto -c -k --keepParent "$path" "$submission"
    fi

    echo "Notarizing $name..."
    # The status is read from the JSON as well as the exit code: notarytool has shipped versions that exit 0 on a
    # rejected submission.
    result="$(xcrun notarytool submit "$submission" --wait --output-format json "${credentials[@]}")" || true
    [[ -z "$scratch" ]] || rm -rf "$scratch"
    id="$(plutil -extract id raw - <<<"$result" 2>/dev/null || true)"
    status="$(plutil -extract status raw - <<<"$result" 2>/dev/null || true)"
    if [[ "$status" != "Accepted" ]]; then
        echo "error: notarization of $name ended with '${status:-no result}'" >&2
        echo "$result" >&2
        if [[ -n "$id" ]]; then
            echo "Notary log for $id:" >&2
            xcrun notarytool log "$id" "${credentials[@]}" >&2 || true
        fi
        return 1
    fi

    xcrun stapler staple -q "$path" || { echo "error: stapling failed for $name" >&2; return 1; }
    xcrun stapler validate -q "$path" || { echo "error: the stapled ticket did not validate for $name" >&2; return 1; }

    # A disk image or package is assessed by its own signature; an app by its contents.
    local -a context=(--type "$assessment")
    [[ "$assessment" == execute ]] || context+=(--context context:primary-signature)
    spctl --assess "${context[@]}" "$path" \
        || { echo "error: Gatekeeper rejects $name after notarization" >&2; return 1; }
    echo "$name notarized, stapled and accepted by Gatekeeper"
}
