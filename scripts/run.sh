#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
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
for resource in "$bin_dir"/*.bundle; do
    if [ -d "$resource" ]; then
        resource_dest="build/BashCut.app/$(basename "$resource")"
        if [ -d "$resource_dest" ]; then chmod -R u+w "$resource_dest"; fi
        cp -R "$resource" build/BashCut.app/
    fi
done
# Expand the Xcode build settings Info.plist uses; an unexpanded bundle ID breaks AppleScript, defaults and TCC.
sed -e 's/$(PRODUCT_BUNDLE_IDENTIFIER)/app.bashcut/' -e 's/$(PRODUCT_NAME)/BashCut/' \
    BashCut/Info.plist >"$bundle/Info.plist"
cp -R BashCut/Resources/en.lproj BashCut/Resources/vi.lproj "$bundle/Resources/"
if pgrep -qf "build/BashCut.app/Contents/MacOS/BashCutApp"; then
    echo "BashCut is already running the previous build. Quit it (⌘Q), then run scripts/run.sh again." >&2
    exit 1
fi
open build/BashCut.app
