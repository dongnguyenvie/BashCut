#!/bin/bash
# Packages a signed BashCut.app as an installer package for /Applications, signs it and notarizes it.
#     scripts/create-pkg.sh <BashCut.app> [--output DIR] [--skip-notarize]
# Writes BashCut-<version>.pkg, named from the app's Info.plist, to DIR (default: the folder holding the app).
# Needs a "Developer ID Installer" identity; settings come from .env, see scripts/build-release.sh.
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
[[ -d "$app" ]] || { echo "error: usage: scripts/create-pkg.sh <BashCut.app> [--output DIR] [--skip-notarize]" >&2; exit 2; }
app="$(cd "$app" && pwd)"
output="${output:-$(dirname "$app")}"
require_env BASHCUT_TEAM_ID
! $notarize || require_notary_env
identity="$(installer_identity)"

version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
pkg="$output/BashCut-$version.pkg"
echo "Packaging $(basename "$pkg")..."

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
pkgbuild --quiet --component "$app" --install-location /Applications \
    --identifier app.bashcut.pkg --version "$version" "$staging/component.pkg"
mkdir -p "$output"
productbuild --quiet --package "$staging/component.pkg" --sign "$identity" --timestamp "$pkg"
! $notarize || notarize_and_staple "$pkg" install
echo "$pkg"
