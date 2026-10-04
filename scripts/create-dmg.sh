#!/bin/bash
# Packages a signed BashCut.app as a drag-to-Applications disk image, signs it and notarizes it.
#     scripts/create-dmg.sh <BashCut.app> [--output DIR] [--skip-notarize]
# Writes BashCut-<version>.dmg, named from the app's Info.plist, to DIR (default: the folder holding the app).
# Signing and notary settings come from .env; see scripts/build-release.sh.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
source "$BASHCUT_LIB_DIR/signing.sh"
source "$BASHCUT_LIB_DIR/notarize.sh"

app=""
output=""
notarize=true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) [[ $# -ge 2 ]] || { echo "error: --output requires a folder" >&2; exit 2; }; output="$2"; shift 2 ;;
        --skip-notarize) notarize=false; shift ;;
        -h|--help) sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "error: unknown option: $1" >&2; exit 2 ;;
        *) app="$1"; shift ;;
    esac
done
[[ -d "$app" ]] || { echo "error: usage: scripts/create-dmg.sh <BashCut.app> [--output DIR] [--skip-notarize]" >&2; exit 2; }
app="$(cd "$app" && pwd)"
output="${output:-$(dirname "$app")}"
require_env BASHCUT_TEAM_ID
! $notarize || require_notary_env
identity="$(developer_id_identity)"

version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
dmg="$output/BashCut-$version.dmg"
echo "Packaging $(basename "$dmg")..."

# The staging folder holds the app and an /Applications link, the whole drag-to-install window.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/BashCut.app"
ln -s /Applications "$staging/Applications"
mkdir -p "$output"
hdiutil create -quiet -volname "BashCut $version" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
codesign --force --sign "$identity" --timestamp "$dmg"
hdiutil verify -quiet "$dmg"
! $notarize || notarize_and_staple "$dmg" open
echo "$dmg"
