#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build
bundle="build/BashCut.app/Contents"
mkdir -p "$bundle/MacOS" "$bundle/Resources"
bin_dir="$(swift build --show-bin-path)"
cp "$bin_dir/BashCutApp" "$bundle/MacOS/BashCutApp"
cp "$bin_dir/bashcut" "$bundle/MacOS/bashcut"
for resource in "$bin_dir"/*.bundle; do
    if [ -d "$resource" ]; then
        resource_dest="build/BashCut.app/$(basename "$resource")"
        if [ -d "$resource_dest" ]; then chmod -R u+w "$resource_dest"; fi
        cp -R "$resource" build/BashCut.app/
    fi
done
cp BashCut/Info.plist "$bundle/Info.plist"
cp -R BashCut/Resources/en.lproj BashCut/Resources/vi.lproj "$bundle/Resources/"
open build/BashCut.app
