#!/bin/bash
# Builds a BashCut release for distribution outside the Mac App Store: Developer ID signed, notarized and stapled
# BashCut-<version>.dmg and .zip (and .pkg with --pkg) in build/release/<version>-<build>/, with SHA256SUMS.
#     scripts/build-release.sh [--version 0.0.2] [--build 2] [--pkg] [--skip-notarize] [--dry-run]
# Account settings come from the repository's .env (git-ignored; see .env.example and scripts/load-env.sh):
#     BASHCUT_TEAM_ID           Apple Developer team ID (required)
#     BASHCUT_APPLE_ID          Apple ID of the team account, for notarization
#     BASHCUT_NOTARY_PASSWORD   app-specific password from appleid.apple.com, for notarization
#     BASHCUT_SIGN_IDENTITY     defaults to the team's "Developer ID Application" identity in the keychain
#     BASHCUT_INSTALLER_IDENTITY  for --pkg; defaults to the team's "Developer ID Installer" identity
set -euo pipefail
cd "$(dirname "$0")/.."
repository="$(pwd)"

version=""
build_number=""
make_pkg=false
notarize=true
dry_run=false

usage() {
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) [[ $# -ge 2 ]] || { echo "error: --version requires a value" >&2; exit 2; }; version="$2"; shift 2 ;;
        --build) [[ $# -ge 2 ]] || { echo "error: --build requires a value" >&2; exit 2; }; build_number="$2"; shift 2 ;;
        --pkg) make_pkg=true; shift ;;
        --skip-notarize) notarize=false; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

source scripts/load-env.sh
require_env BASHCUT_TEAM_ID
team_id="$BASHCUT_TEAM_ID"

config_value() {
    awk -F' *= *' -v key="$1" '$1 == key { value = $2 } END { print value }' Configs/Version.xcconfig
}
version="${version:-$(config_value MARKETING_VERSION)}"
build_number="${build_number:-$(config_value CURRENT_PROJECT_VERSION)}"
[[ "$version" =~ ^[0-9]+([.][0-9]+){1,2}$ ]] || { echo "error: invalid version '$version'" >&2; exit 2; }
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] || { echo "error: invalid build '$build_number'" >&2; exit 2; }

for tool in xcodegen xcodebuild; do
    command -v "$tool" >/dev/null || { echo "error: $tool is required" >&2; exit 1; }
done

# Identities are matched by team, so another account's certificates in the keychain are never picked.
find_identity() {
    security find-identity -v ${2:+-p "$2"} 2>/dev/null \
        | awk -F'"' -v prefix="$1" -v team="($team_id)" \
            'index($2, prefix) == 1 && substr($2, length($2) - length(team) + 1) == team { print $2; exit }'
}
sign_identity="${BASHCUT_SIGN_IDENTITY:-$(find_identity "Developer ID Application:" codesigning)}"
[[ -n "$sign_identity" ]] || {
    echo "error: no \"Developer ID Application\" identity for BASHCUT_TEAM_ID in the keychain." >&2
    echo "       Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application." >&2
    exit 1
}
if [[ "$sign_identity" != "Developer ID Application:"* ]]; then
    echo "warning: '$sign_identity' is not a Developer ID identity; Gatekeeper rejects this build on other Macs" >&2
    [[ "$notarize" == false ]] || { echo "error: notarization needs a Developer ID identity" >&2; exit 1; }
fi
installer_identity=""
if $make_pkg; then
    installer_identity="${BASHCUT_INSTALLER_IDENTITY:-$(find_identity "Developer ID Installer:")}"
    [[ -n "$installer_identity" ]] || {
        echo "error: --pkg needs a \"Developer ID Installer\" identity for BASHCUT_TEAM_ID in the keychain" >&2
        exit 1
    }
fi
if $notarize; then
    [[ -n "${BASHCUT_APPLE_ID:-}" && -n "${BASHCUT_NOTARY_PASSWORD:-}" ]] || {
        echo "error: set BASHCUT_APPLE_ID and BASHCUT_NOTARY_PASSWORD (app-specific password) in .env," >&2
        echo "       or pass --skip-notarize for a local test build" >&2
        exit 1
    }
fi

output="$repository/build/release/$version-$build_number"
echo "BashCut release $version ($build_number)"
echo "  Signing:    $sign_identity"
$make_pkg && echo "  Installer:  $installer_identity"
echo "  Notarize:   $($notarize && echo "yes, as $BASHCUT_APPLE_ID" || echo no)"
echo "  Output:     $output"
if $dry_run; then
    echo "Dry run: nothing was built."
    exit 0
fi

work="$output/work"
rm -rf "$output"
mkdir -p "$work"

notarize_file() {
    local file="$1" result id status
    echo "Notarizing $(basename "$file")..."
    result="$(xcrun notarytool submit "$file" --wait --output-format json \
        --apple-id "$BASHCUT_APPLE_ID" --password "$BASHCUT_NOTARY_PASSWORD" --team-id "$team_id")" || true
    id="$(plutil -extract id raw - <<<"$result" 2>/dev/null || true)"
    status="$(plutil -extract status raw - <<<"$result" 2>/dev/null || true)"
    if [[ "$status" != "Accepted" ]]; then
        echo "error: notarization of $(basename "$file") ended with '${status:-no result}'" >&2
        echo "$result" >&2
        if [[ -n "$id" ]]; then
            xcrun notarytool log "$id" --apple-id "$BASHCUT_APPLE_ID" --password "$BASHCUT_NOTARY_PASSWORD" \
                --team-id "$team_id" "$output/notary-$id.json" >/dev/null && echo "log: $output/notary-$id.json" >&2
        fi
        exit 1
    fi
}

echo "Generating BashCut.xcodeproj..."
xcodegen generate --quiet

echo "Archiving..."
archive="$work/BashCut.xcarchive"
xcodebuild archive \
    -project BashCut.xcodeproj -scheme BashCut -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    -skipPackagePluginValidation -quiet \
    DEVELOPMENT_TEAM="$team_id" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$sign_identity" \
    OTHER_CODE_SIGN_FLAGS=--timestamp ENABLE_HARDENED_RUNTIME=YES \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number"

app="$work/BashCut.app"
ditto "$archive/Products/Applications/BashCut.app" "$app"
info="$app/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw "$info")" == "$version" ]] || { echo "error: version mismatch" >&2; exit 1; }
[[ "$(plutil -extract CFBundleVersion raw "$info")" == "$build_number" ]] || { echo "error: build mismatch" >&2; exit 1; }

# Notarization rejects a Mach-O without a secure timestamp, or an executable without the hardened runtime; check
# them all up front. Dylibs (Xcode's Swift compatibility libraries) need no runtime flag.
echo "Checking signatures..."
codesign --verify --deep --strict "$app"
while IFS= read -r -d '' file; do
    kind="$(file -b "$file")"
    [[ "$kind" == *Mach-O* ]] || continue
    details="$(codesign -dvv "$file" 2>&1)"
    if [[ "$kind" == *executable* ]] && ! grep -q 'flags=.*runtime' <<<"$details"; then
        echo "error: no hardened runtime: ${file#"$app"/}" >&2
        exit 1
    fi
    grep -q '^Timestamp=' <<<"$details" || { echo "error: no secure timestamp: ${file#"$app"/}" >&2; exit 1; }
    grep -q "^Authority=$sign_identity\$" <<<"$details" || { echo "error: not signed by $sign_identity: ${file#"$app"/}" >&2; exit 1; }
done < <(find "$app" -type f -perm -u+x -print0)

# The app is notarized and stapled first, so the zip and the app inside the dmg work offline.
if $notarize; then
    ditto -c -k --keepParent "$app" "$work/BashCut-notarize.zip"
    notarize_file "$work/BashCut-notarize.zip"
    xcrun stapler staple -q "$app"
fi

name="BashCut-$version"
echo "Packaging $name.zip..."
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$name.zip"

echo "Packaging $name.dmg..."
dmg_root="$work/dmg"
mkdir -p "$dmg_root"
ditto "$app" "$dmg_root/BashCut.app"
ln -s /Applications "$dmg_root/Applications"
hdiutil create -quiet -volname "BashCut $version" -srcfolder "$dmg_root" -fs HFS+ -format UDZO -ov "$output/$name.dmg"
codesign --force --sign "$sign_identity" --timestamp "$output/$name.dmg"
if $notarize; then
    notarize_file "$output/$name.dmg"
    xcrun stapler staple -q "$output/$name.dmg"
fi

if $make_pkg; then
    echo "Packaging $name.pkg..."
    pkgbuild --quiet --component "$app" --install-location /Applications \
        --identifier app.bashcut.pkg --version "$version" "$work/component.pkg"
    productbuild --quiet --package "$work/component.pkg" --sign "$installer_identity" --timestamp "$output/$name.pkg"
    if $notarize; then
        notarize_file "$output/$name.pkg"
        xcrun stapler staple -q "$output/$name.pkg"
    fi
fi

if $notarize; then
    spctl --assess --type execute "$app"
    spctl --assess --type open --context context:primary-signature "$output/$name.dmg"
fi

rm -rf "$work"
(cd "$output" && shasum -a 256 BashCut-* >SHA256SUMS)
echo "Release files in $output:"
cat "$output/SHA256SUMS"
