#!/bin/bash
# Publishes a BashCut release built by scripts/build-release.sh to Homebrew: uploads the zip, dmg and SHA256SUMS
# to a GitHub release v<version>, then writes Casks/bashcut.rb to the tap and pushes it.
#     scripts/publish-homebrew.sh [--version 0.0.2] [--build 2] [--tap owner/homebrew-tap] [--skip-release]
#                                 [--yes] [--dry-run]
# Users then install with `brew install --cask <owner>/tap/bashcut`, which also links `bashcut` and `bashcut-mcp`.
# The version defaults to Configs/Version.xcconfig. The release repository is the `origin` remote; the tap
# defaults to <owner>/homebrew-tap and must already exist. Optional .env keys (keys in .env.example):
#     BASHCUT_GITHUB_REPO    owner/name of the release repository, instead of the origin remote
#     BASHCUT_HOMEBREW_TAP   owner/name of the tap repository
# The app must be Developer ID signed, notarized and stapled: Homebrew refuses casks Gatekeeper rejects.
# --dry-run checks the release files and prints the cask without publishing anything. --skip-release reuses an
# existing GitHub release. Without --yes the script waits for the version to be typed back before publishing.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
source "$BASHCUT_LIB_DIR/homebrew.sh"

version=""
build_number=""
tap="${BASHCUT_HOMEBREW_TAP:-}"
create_release=true
assume_yes=false
dry_run=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) [[ $# -ge 2 ]] || { echo "error: --version requires a value" >&2; exit 2; }; version="$2"; shift 2 ;;
        --build) [[ $# -ge 2 ]] || { echo "error: --build requires a value" >&2; exit 2; }; build_number="$2"; shift 2 ;;
        --tap) [[ $# -ge 2 ]] || { echo "error: --tap requires a value" >&2; exit 2; }; tap="$2"; shift 2 ;;
        --skip-release) create_release=false; shift ;;
        --yes) assume_yes=true; shift ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "error: unknown option: $1" >&2; exit 2 ;;
    esac
done
version="${version:-$(version_setting MARKETING_VERSION)}"
build_number="${build_number:-$(version_setting CURRENT_PROJECT_VERSION)}"
check_version "$version" "$build_number"
require_tools ditto plutil codesign spctl shasum ruby
$dry_run || require_tools gh git

repo="${BASHCUT_GITHUB_REPO:-$(github_repo_from_remote "$(git remote get-url origin 2>/dev/null || true)")}"
[[ "$repo" =~ ^[^/]+/[^/]+$ ]] || { echo "error: set BASHCUT_GITHUB_REPO; origin is not a GitHub remote" >&2; exit 1; }
tap="${tap:-${repo%%/*}/homebrew-tap}"
[[ "$tap" =~ ^[^/]+/homebrew-[^/]+$ ]] \
    || { echo "error: a tap repository is named <owner>/homebrew-<name>, not '$tap'" >&2; exit 1; }
tap_name="${tap%%/*}/${tap#*/homebrew-}"
tag="v$version"

release="$REPO_ROOT/build/release/$version-$build_number"
zip="$release/BashCut-$version.zip"
assets=("$zip" "$release/BashCut-$version.dmg" "$release/SHA256SUMS")
for asset in "${assets[@]}"; do
    [[ -f "$asset" ]] || { echo "error: $asset is missing; run scripts/build-release.sh first" >&2; exit 1; }
done
(cd "$release" && shasum -a 256 -c --quiet SHA256SUMS) \
    || { echo "error: the release files do not match $release/SHA256SUMS" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Checking $(basename "$zip")..."
ditto -x -k "$zip" "$work/unzipped"
app="$work/unzipped/BashCut.app"
[[ -d "$app" ]] || { echo "error: the zip does not contain BashCut.app at its root" >&2; exit 1; }
info="$app/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw "$info")" == "$version" ]] \
    || { echo "error: the zipped app's version is not $version" >&2; exit 1; }
[[ "$(plutil -extract CFBundleVersion raw "$info")" == "$build_number" ]] \
    || { echo "error: the zipped app's build number is not $build_number" >&2; exit 1; }
for binary in bashcut bashcut-mcp; do
    [[ -x "$app/Contents/MacOS/$binary" ]] || { echo "error: the app has no Contents/MacOS/$binary" >&2; exit 1; }
done
codesign --verify --deep --strict "$app"
# A dry run may check a development build, so Gatekeeper's verdict only fails a real publish.
if ! gatekeeper="$(spctl --assess --type execute --verbose "$app" 2>&1)" \
    || ! xcrun stapler validate -q "$app" >/dev/null 2>&1; then
    echo "${gatekeeper:-the app has no stapled notarization ticket}" >&2
    $dry_run || { echo "error: the app is not notarized for Gatekeeper; Homebrew would refuse it" >&2; exit 1; }
    echo "warning: the app is not notarized; a real publish would stop here" >&2
fi

sha256="$(shasum -a 256 "$zip" | awk '{ print $1 }')"
# Under a Casks/ folder so `brew style` applies the cask rules, not those for Homebrew's own code.
mkdir -p "$work/Casks"
cask="$work/Casks/bashcut.rb"
render_cask "$version" "$sha256" "$repo" "$(plutil -extract LSMinimumSystemVersion raw "$info")" >"$cask"
ruby -c "$cask" >/dev/null
if command -v brew >/dev/null 2>&1; then
    brew style "$cask"
fi

echo "BashCut $version ($build_number) for Homebrew"
echo "  Release:  https://github.com/$repo/releases/tag/$tag$($create_release || echo " (existing)")"
echo "  Tap:      https://github.com/$tap (Casks/bashcut.rb)"
echo "  Install:  brew install --cask $tap_name/bashcut"
if $dry_run; then
    echo "--- Casks/bashcut.rb"
    cat "$cask"
    echo "Dry run: nothing was published."
    exit 0
fi

# Fail before anything is published if the tap cannot be cloned; creating it is left to a person.
gh repo clone "$tap" "$work/tap" -- --depth 1 --quiet \
    || { echo "error: cannot clone $tap; create it first: gh repo create $tap --public" >&2; exit 1; }
if $create_release; then
    ! gh release view "$tag" --repo "$repo" >/dev/null 2>&1 \
        || { echo "error: release $tag already exists; pass --skip-release to reuse it" >&2; exit 1; }
    commit="$(git rev-parse HEAD)"
    [[ -n "$(git branch -r --contains "$commit" 2>/dev/null)" ]] \
        || { echo "error: HEAD ($commit) is not pushed; the release tag must point at a published commit" >&2; exit 1; }
else
    gh release view "$tag" --repo "$repo" >/dev/null \
        || { echo "error: release $tag does not exist on $repo" >&2; exit 1; }
fi

if ! $assume_yes; then
    printf "Type the version (%s) to publish it: " "$version"
    IFS= read -r confirmed
    [[ "$confirmed" == "$version" ]] || { echo "error: the version did not match; nothing was published" >&2; exit 1; }
fi

if $create_release; then
    echo "Creating release $tag..."
    gh release create "$tag" "${assets[@]}" --repo "$repo" --target "$commit" \
        --title "BashCut $version" --generate-notes
fi

echo "Updating $tap..."
mkdir -p "$work/tap/Casks"
cp "$cask" "$work/tap/Casks/bashcut.rb"
git -C "$work/tap" add Casks/bashcut.rb
if git -C "$work/tap" diff --cached --quiet; then
    echo "Casks/bashcut.rb is already current."
else
    git -C "$work/tap" commit --quiet -m "bashcut $version"
    git -C "$work/tap" push --quiet
fi
echo "Published. Install with: brew install --cask $tap_name/bashcut"
