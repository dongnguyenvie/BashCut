#!/bin/bash
# Archives BashCut for the Mac App Store and uploads it to App Store Connect, where it appears in TestFlight.
#     scripts/deploy-testflight.sh [--version 0.0.2] [--build 2] [--export] [--yes] [--dry-run]
# --export writes the signed BashCut.pkg without uploading it, for Transporter or a later upload.
# The version defaults to Configs/Version.xcconfig; App Store Connect rejects a build number it has seen.
# Settings come from .env (git-ignored; keys in .env.example): BASHCUT_TEAM_ID and BASHCUT_APPLE_ID. Xcode signs
# automatically with the account signed in under Xcode › Settings › Accounts.
# Without --yes the upload waits for the Apple ID to be typed back, so a wrong .env cannot upload by accident.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

version=""
build_number=""
assume_yes=false
export_only=false
dry_run=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) [[ $# -ge 2 ]] || { echo "error: --version requires a value" >&2; exit 2; }; version="$2"; shift 2 ;;
        --build) [[ $# -ge 2 ]] || { echo "error: --build requires a value" >&2; exit 2; }; build_number="$2"; shift 2 ;;
        --yes) assume_yes=true; shift ;;
        --export) export_only=true; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; exit 2 ;;
    esac
done
version="${version:-$(version_setting MARKETING_VERSION)}"
build_number="${build_number:-$(version_setting CURRENT_PROJECT_VERSION)}"
check_version "$version" "$build_number"
require_tools xcodegen xcodebuild
require_env BASHCUT_TEAM_ID BASHCUT_APPLE_ID

echo "BashCut TestFlight $($export_only && echo export || echo upload)"
echo "  Apple ID:  $BASHCUT_APPLE_ID"
echo "  Version:   $version ($build_number)"
if $dry_run; then
    echo "Dry run: nothing was archived or uploaded."
    exit 0
fi
if ! $assume_yes && ! $export_only; then
    printf "Type the Apple ID to confirm the upload account: "
    IFS= read -r confirmed
    [[ "$confirmed" == "$BASHCUT_APPLE_ID" ]] || { echo "error: the Apple ID did not match; nothing was uploaded" >&2; exit 1; }
fi

output="$REPO_ROOT/build/testflight/$version-$build_number-$(date +%Y%m%d-%H%M%S)"
archive="$output/BashCut.xcarchive"
options="$output/ExportOptions.plist"
mkdir -p "$output"
plutil -create xml1 "$options"
plutil -insert destination -string "$($export_only && echo export || echo upload)" "$options"
plutil -insert method -string app-store-connect "$options"
plutil -insert signingStyle -string automatic "$options"
plutil -insert teamID -string "$BASHCUT_TEAM_ID" "$options"
plutil -insert manageAppVersionAndBuildNumber -bool false "$options"

echo "Archiving..."
xcodegen generate --quiet
xcodebuild archive \
    -project BashCut.xcodeproj -scheme BashCut -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$archive" \
    -allowProvisioningUpdates -skipPackagePluginValidation -quiet \
    DEVELOPMENT_TEAM="$BASHCUT_TEAM_ID" CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY="Apple Development" \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number"

# App Store validation runs only after the upload; these catch the rejections seen so far before it.
app="$archive/Products/Applications/BashCut.app"
info="$app/Contents/Info.plist"
expect_plist() {
    local actual
    actual="$(plutil -extract "$1" raw "$info")"
    [[ "$actual" == "$2" ]] || { echo "error: $1 is '$actual', expected '$2'" >&2; exit 1; }
}
expect_plist CFBundleIdentifier app.bashcut
expect_plist CFBundleShortVersionString "$version"
expect_plist CFBundleVersion "$build_number"
expect_plist LSApplicationCategoryType public.app-category.video
[[ -f "$app/Contents/Resources/AppIcon.icns" ]] || { echo "error: AppIcon.icns is missing" >&2; exit 1; }
for executable in BashCutApp bashcut bashcut-mcp; do
    [[ -x "$app/Contents/MacOS/$executable" ]] || { echo "error: missing executable $executable" >&2; exit 1; }
    codesign -d --entitlements :- "$app/Contents/MacOS/$executable" 2>/dev/null \
        | grep -q '<key>com.apple.security.app-sandbox</key><true/>' \
        || { echo "error: App Sandbox is not enabled for $executable" >&2; exit 1; }
done

# SwiftPM resource bundles (SwiftTerm_SwiftTerm.bundle: Metal shaders) come out of the archive signed with the
# development identity, and the App Store export re-signs only code, so App Store Connect rejects the upload
# (ITMS-90284: must be signed with the certificate in the provisioning profile). They hold no executable, so their
# signature is removed and the exported app's signature seals them as resources.
for bundle in "$app"/Contents/Resources/*.bundle; do
    [[ -d "$bundle/Contents/_CodeSignature" ]] || continue
    if plutil -extract CFBundleExecutable raw "$bundle/Contents/Info.plist" >/dev/null 2>&1; then
        echo "error: $(basename "$bundle") contains code; sign it in the export instead" >&2
        exit 1
    fi
    codesign --remove-signature "$bundle"
    rmdir "$bundle/Contents/_CodeSignature" # left empty; a signature folder would still read as signed code
done

echo "$($export_only && echo Exporting || echo "Uploading to App Store Connect")..."
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$output/export" -exportOptionsPlist "$options" \
    -allowProvisioningUpdates -quiet
if $export_only; then
    # Every signed item in the exported app must carry the app's distribution signer, as App Store Connect checks.
    expanded="$(mktemp -d)"
    pkgutil --expand-full "$output/export/BashCut.pkg" "$expanded/pkg"
    exported="$(find "$expanded/pkg" -maxdepth 3 -name BashCut.app -type d | head -1)"
    codesign --verify --deep --strict "$exported"
    signer="$(codesign -dvv "$exported" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
    [[ "$signer" == "Apple Distribution:"* ]] || { echo "error: the app is signed by '$signer'" >&2; exit 1; }
    while IFS= read -r -d '' item; do
        # Unsigned items (resource files, the unsigned resource bundles) have no authority; codesign then fails.
        authority="$(codesign -dvv "$item" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true)"
        [[ -z "$authority" || "$authority" == "$signer" ]] \
            || { echo "error: ${item#"$exported"/} is signed by '$authority', not '$signer'" >&2; exit 1; }
    done < <(find "$exported/Contents" \( -name '*.bundle' -o -name '*.app' -o -name '*.framework' -o -name '*.dylib' \
        -o -perm -u+x -type f \) -print0)
    rm -rf "$expanded"
    pkgutil --check-signature "$output/export/BashCut.pkg" | sed -n '4p' | sed 's/^ *[0-9]*\. /Installer: /'
    echo "Exported $output/export/BashCut.pkg; upload it with Transporter."
    exit 0
fi
echo "Uploaded BashCut $version ($build_number). It appears in TestFlight once Apple finishes processing."
echo "Archive: $output"
