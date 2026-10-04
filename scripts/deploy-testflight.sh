#!/bin/bash
# Archives BashCut for the Mac App Store and uploads it to App Store Connect, where it appears in TestFlight.
#     scripts/deploy-testflight.sh [--version 0.0.2] [--build 2] [--yes] [--dry-run]
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
dry_run=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) [[ $# -ge 2 ]] || { echo "error: --version requires a value" >&2; exit 2; }; version="$2"; shift 2 ;;
        --build) [[ $# -ge 2 ]] || { echo "error: --build requires a value" >&2; exit 2; }; build_number="$2"; shift 2 ;;
        --yes) assume_yes=true; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; exit 2 ;;
    esac
done
version="${version:-$(version_setting MARKETING_VERSION)}"
build_number="${build_number:-$(version_setting CURRENT_PROJECT_VERSION)}"
check_version "$version" "$build_number"
require_tools xcodegen xcodebuild
require_env BASHCUT_TEAM_ID BASHCUT_APPLE_ID

echo "BashCut TestFlight upload"
echo "  Apple ID:  $BASHCUT_APPLE_ID"
echo "  Version:   $version ($build_number)"
if $dry_run; then
    echo "Dry run: nothing was archived or uploaded."
    exit 0
fi
if ! $assume_yes; then
    printf "Type the Apple ID to confirm the upload account: "
    IFS= read -r confirmed
    [[ "$confirmed" == "$BASHCUT_APPLE_ID" ]] || { echo "error: the Apple ID did not match; nothing was uploaded" >&2; exit 1; }
fi

output="$REPO_ROOT/build/testflight/$version-$build_number-$(date +%Y%m%d-%H%M%S)"
archive="$output/BashCut.xcarchive"
options="$output/ExportOptions.plist"
mkdir -p "$output"
plutil -create xml1 "$options"
plutil -insert destination -string upload "$options"
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

echo "Uploading to App Store Connect..."
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$output/export" -exportOptionsPlist "$options" \
    -allowProvisioningUpdates -quiet
echo "Uploaded BashCut $version ($build_number). It appears in TestFlight once Apple finishes processing."
echo "Archive: $output"
