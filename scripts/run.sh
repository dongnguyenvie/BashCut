#!/bin/bash
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
swift build
bundle="build/BashCut.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
bin_dir="$(swift build --show-bin-path)"
# Replace binaries by rename so a running instance keeps its old, intact executable.
for binary in BashCutApp bashcut bashcut-mcp; do
    if [ -f "$bin_dir/$binary" ]; then
        cp "$bin_dir/$binary" "$bundle/MacOS/.$binary.new"
        mv -f "$bundle/MacOS/.$binary.new" "$bundle/MacOS/$binary"
    fi
done
# The agent kit (editing skills for Claude Code and Codex) from a checkout next to this repo, or $BASHCUT_AGENT_KIT.
scripts/bundle-agent-kit.sh "$bundle/Resources/AgentKit"
# Core plugins (Plugins/<name>/plugin.json + their provider executable) go in Contents/Resources/Plugins/<id>/
# (Contents/PlugIns is for code bundles: codesign rejects plain folders there).
rm -rf "$bundle/PlugIns"
plugin_dir="$bundle/Resources/Plugins/bashcut.audio-analysis"
mkdir -p "$plugin_dir/bin"
cp Plugins/audio-analysis/plugin.json "$plugin_dir/plugin.json"
cp "$bin_dir/bashcut-audio-analysis" "$plugin_dir/bin/.provider.new"
mv -f "$plugin_dir/bin/.provider.new" "$plugin_dir/bin/provider"
# SwiftPM resource bundles go in Contents/Resources: codesign rejects anything else at the bundle root.
for resource in "$bin_dir"/*.bundle; do
    if [ -d "$resource" ]; then
        name="$(basename "$resource")"
        rm -rf "build/BashCut.app/$name" "$bundle/Resources/$name"
        cp -R "$resource" "$bundle/Resources/"
    fi
done
# Expand the Xcode build settings Info.plist uses; an unexpanded bundle ID breaks AppleScript, defaults and TCC.
# The version comes from Configs/Version.xcconfig, like the Xcode build; plugin registry checks compare against it.
version="$(version_setting MARKETING_VERSION)"
build_number="$(version_setting CURRENT_PROJECT_VERSION)"
sed -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/app.bashcut/' -e 's/$(PRODUCT_NAME)/BashCut/' \
    -e "s/\$(MARKETING_VERSION)/${version:-0.0.0}/" -e "s/\$(CURRENT_PROJECT_VERSION)/${build_number:-1}/" \
    BashCut/Info.plist >"$bundle/Info.plist"
cp -R BashCut/Resources/en.lproj BashCut/Resources/vi.lproj "$bundle/Resources/"
if pgrep -qf "build/BashCut.app/Contents/MacOS/BashCutApp"; then
    echo "BashCut is already running the previous build. Quit it (⌘Q), then run scripts/run.sh again." >&2
    exit 1
fi
# Sign with a stable identity so macOS privacy grants (Desktop folder access) survive rebuilds; an ad-hoc
# signature changes with every build and macOS asks again. BASHCUT_SIGN_IDENTITY picks the identity;
# otherwise the first valid Apple Development identity in the keychain is used.
identity="${BASHCUT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ { print $2; exit }')}"
if [ -z "$identity" ]; then
    echo "warning: no Apple Development identity found; signing ad hoc (macOS will ask for folder access again)" >&2
    identity="-"
fi
codesign --force --sign "$identity" --identifier app.bashcut.audio-analysis "$plugin_dir/bin/provider" 2>&1 \
    | { grep -v "replacing existing signature" >&2 || true; }
codesign --force --sign "$identity" --identifier app.bashcut.cli "$bundle/MacOS/bashcut" 2>&1 \
    | { grep -v "replacing existing signature" >&2 || true; }
codesign --force --sign "$identity" --identifier app.bashcut.mcp "$bundle/MacOS/bashcut-mcp" 2>&1 \
    | { grep -v "replacing existing signature" >&2 || true; }
codesign --force --sign "$identity" --identifier app.bashcut build/BashCut.app 2>&1 \
    | { grep -v "replacing existing signature" >&2 || true; }
echo "Signed build/BashCut.app with: $identity"
open build/BashCut.app
