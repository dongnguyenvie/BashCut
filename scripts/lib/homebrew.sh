# Renders the Homebrew cask for a BashCut release. Sourced, never executed; needs common.sh first.
#
# The cask installs BashCut.app from the release zip on GitHub and links the bundled `bashcut` CLI and
# `bashcut-mcp` server into Homebrew's bin, so agents in any terminal can drive the app. Nothing here is secret:
# the cask, its URL and its checksum are public by design.
#
# shellcheck shell=bash

[[ -n "${BASHCUT_LIB_HOMEBREW_SOURCED:-}" ]] && return 0
BASHCUT_LIB_HOMEBREW_SOURCED=1

# "owner/name" from a GitHub remote URL (SSH or HTTPS, with or without .git); empty for anything else.
github_repo_from_remote() {
    local url="$1"
    if [[ "$url" =~ ^(git@github\.com:|ssh://git@github\.com/|https://github\.com/)([^/]+/[^/]+)$ ]]; then
        echo "${BASH_REMATCH[2]%.git}"
    fi
}

# The cask symbol for an LSMinimumSystemVersion, e.g. 14.0 -> :sonoma. Fails for a version it does not know, so a
# raised deployment target is noticed here rather than shipped with a wrong requirement.
macos_cask_symbol() {
    case "${1%%.*}" in
        12) echo ":monterey" ;;
        13) echo ":ventura" ;;
        14) echo ":sonoma" ;;
        15) echo ":sequoia" ;;
        26) echo ":tahoe" ;;
        *) echo "error: no Homebrew macOS symbol for minimum system version '$1'" >&2; return 1 ;;
    esac
}

# Usage: render_cask <version> <sha256 of the zip> <owner/name of the GitHub repository> <minimum macOS version>
render_cask() {
    local version="$1" sha256="$2" repo="$3" macos
    [[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || { echo "error: invalid sha256 '$sha256'" >&2; return 1; }
    macos="$(macos_cask_symbol "$4")" || return 1
    cat <<EOF
cask "bashcut" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/$repo/releases/download/v#{version}/BashCut-#{version}.zip"
  name "BashCut"
  desc "Video editor driven by coding agents through a CLI and MCP server"
  homepage "https://github.com/$repo"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: $macos

  app "BashCut.app"
  binary "#{appdir}/BashCut.app/Contents/MacOS/bashcut"
  binary "#{appdir}/BashCut.app/Contents/MacOS/bashcut-mcp"

  zap trash: [
    "~/Library/Application Support/BashCut",
    "~/Library/Caches/app.bashcut",
    "~/Library/Caches/BashCut",
    "~/Library/Containers/app.bashcut",
    "~/Library/HTTPStorages/app.bashcut",
    "~/Library/Logs/BashCut",
    "~/Library/Preferences/app.bashcut.plist",
    "~/Library/Saved Application State/app.bashcut.savedState",
  ]
end
EOF
}
