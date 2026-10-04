#!/bin/bash
# Builds a BashCut release for distribution outside the Mac App Store: a Developer ID signed, notarized and stapled
# app, packaged as BashCut-<version>.zip and .dmg (and .pkg with --pkg) in build/release/<version>-<build>/, with
# SHA256SUMS.
#     scripts/build-release.sh [--version 0.0.2] [--build 2] [--pkg] [--skip-notarize] [--dry-run]
# The version defaults to Configs/Version.xcconfig. Settings come from .env (git-ignored; keys in .env.example):
#     BASHCUT_TEAM_ID             Apple Developer team ID (required)
#     BASHCUT_APPLE_ID            Apple ID of the team account, for notarization
#     BASHCUT_NOTARY_PASSWORD     app-specific password from appleid.apple.com, for notarization
#     BASHCUT_RELEASE_IDENTITY    defaults to the team's "Developer ID Application" identity in the keychain
#     BASHCUT_INSTALLER_IDENTITY  for --pkg; defaults to the team's "Developer ID Installer" identity
# The Developer ID build is not sandboxed (Configs/DeveloperID.entitlements): the bundled `bashcut` and `bashcut-mcp`
# must run from any terminal, which sandboxed helpers that inherit the app's sandbox cannot. The App Store build
# (scripts/deploy-testflight.sh) keeps BashCut.entitlements.
# Steps: archive and verify here, then scripts/create-dmg.sh and scripts/create-pkg.sh, which also run alone.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
source "$BASHCUT_LIB_DIR/signing.sh"
source "$BASHCUT_LIB_DIR/notarize.sh"

version=""
build_number=""
make_pkg=false
notarize=true
dry_run=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) [[ $# -ge 2 ]] || { echo "error: --version requires a value" >&2; exit 2; }; version="$2"; shift 2 ;;
        --build) [[ $# -ge 2 ]] || { echo "error: --build requires a value" >&2; exit 2; }; build_number="$2"; shift 2 ;;
        --pkg) make_pkg=true; shift ;;
        --skip-notarize) notarize=false; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; exit 2 ;;
    esac
done
version="${version:-$(version_setting MARKETING_VERSION)}"
build_number="${build_number:-$(version_setting CURRENT_PROJECT_VERSION)}"
check_version "$version" "$build_number"
require_tools xcodegen xcodebuild
require_env BASHCUT_TEAM_ID
! $notarize || require_notary_env
identity="$(developer_id_identity)"
if [[ "$identity" != "Developer ID Application:"* ]]; then
    echo "warning: '$identity' is not a Developer ID identity; Gatekeeper rejects this build on other Macs" >&2
    ! $notarize || { echo "error: notarization needs a Developer ID identity" >&2; exit 1; }
fi
! $make_pkg || installer_identity >/dev/null

output="$REPO_ROOT/build/release/$version-$build_number"
echo "BashCut release $version ($build_number)"
echo "  Signing:   ${identity% (*}"
echo "  Notarize:  $($notarize && echo yes || echo no)"
echo "  Packages:  zip, dmg$($make_pkg && echo ", pkg" || true)"
echo "  Output:    $output"
if $dry_run; then
    echo "Dry run: nothing was built."
    exit 0
fi

rm -rf "$output"
work="$output/work"
mkdir -p "$work"

echo "Archiving..."
xcodegen generate --quiet
archive="$work/BashCut.xcarchive"
xcodebuild archive \
    -project BashCut.xcodeproj -scheme BashCut -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    -skipPackagePluginValidation -quiet \
    DEVELOPMENT_TEAM="$BASHCUT_TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" \
    OTHER_CODE_SIGN_FLAGS=--timestamp ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_ENTITLEMENTS="$REPO_ROOT/Configs/DeveloperID.entitlements" \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number"

app="$work/BashCut.app"
ditto "$archive/Products/Applications/BashCut.app" "$app"
info="$app/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw "$info")" == "$version" ]] \
    || { echo "error: the archived app's version is not $version" >&2; exit 1; }
[[ "$(plutil -extract CFBundleVersion raw "$info")" == "$build_number" ]] \
    || { echo "error: the archived app's build number is not $build_number" >&2; exit 1; }

echo "Checking signatures..."
verify_app_signatures "$app" "$identity"
verify_not_sandboxed "$app"

# The app is stapled before it is packaged, so the zip and the app inside the dmg open offline.
! $notarize || notarize_and_staple "$app" execute

skip=()
$notarize || skip=(--skip-notarize)
echo "Packaging BashCut-$version.zip..."
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/BashCut-$version.zip"
scripts/create-dmg.sh "$app" --output "$output" ${skip[@]+"${skip[@]}"}
! $make_pkg || scripts/create-pkg.sh "$app" --output "$output" ${skip[@]+"${skip[@]}"}

rm -rf "$work"
(cd "$output" && shasum -a 256 BashCut-* >SHA256SUMS)
echo "Release files in $output:"
cat "$output/SHA256SUMS"
