#!/bin/bash
# Renders BashCut/Assets.xcassets/AppIcon.appiconset from BashCutLogo (BashCut/Views/BashCutLogo.swift), the single
# source of the mark, and copies the 256 px icon to .github/assets/logo.png for the READMEs.
#     scripts/render-app-icon.sh
# Each size is drawn from the vectors, not downscaled. The tile follows the macOS icon grid: 824 of 1024 points,
# centred, with the system's drop shadow below it.
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
require_tools swiftc

build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
cat >"$build/main.swift" <<'EOF'
import AppKit
import SwiftUI

@main struct RenderAppIcon {
    @MainActor static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let icon = ZStack {
            BashCutLogo()
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 10)
        }
        .frame(width: 1024, height: 1024)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(content: icon)
                renderer.scale = CGFloat(points * scale) / 1024
                guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                try data.write(to: folder.appendingPathComponent(name))
            }
        }
    }
}
EOF
swiftc -O -parse-as-library -o "$build/render" "$build/main.swift" BashCut/Views/BashCutLogo.swift
icons="BashCut/Assets.xcassets/AppIcon.appiconset"
"$build/render" "$icons"
cp "$icons/icon_256x256.png" .github/assets/logo.png
echo "Rendered $icons and .github/assets/logo.png"
