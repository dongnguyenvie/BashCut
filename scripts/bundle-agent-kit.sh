#!/bin/bash
# Copies the agent kit into an app bundle's resources (scripts/run.sh and the Xcode build phase):
#     scripts/bundle-agent-kit.sh <Contents/Resources/AgentKit>
# The kit comes from $BASHCUT_AGENT_KIT or a ../bashcut-agent-kit checkout. In a git checkout only tracked files are
# copied, from the working tree so skill edits show up in a dev build; tests, CI and the release catalog stay out.
# Without a kit the app still works: it downloads releases, or Settings › Agents can point at a folder.
set -euo pipefail
destination="$1"
repository="$(cd "$(dirname "$0")/.." && pwd)"
kit="${BASHCUT_AGENT_KIT:-$repository/../bashcut-agent-kit}"
if [ ! -f "$kit/.claude-plugin/plugin.json" ]; then
    rm -rf "$destination"
    echo "warning: no agent kit at $kit; the app downloads kit releases, or Settings › Agents can point at one" >&2
    exit 0
fi
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
if git -C "$kit" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    (cd "$kit" && git ls-files -z | tar --null -T - -cf -) | tar -xf - -C "$staging"
else
    cp -R "$kit/." "$staging/"
fi
rm -rf "$staging/.git" "$staging/.github" "$staging/tests" "$staging/dist" "$staging/releases.json" "$staging/.gitignore"
find "$staging" \( -name __pycache__ -o -name .DS_Store \) -prune -exec rm -rf {} +
rm -rf "$destination"
mkdir -p "$(dirname "$destination")"
cp -R "$staging" "$destination"
chmod 755 "$destination"
