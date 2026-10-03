#!/bin/bash
# Regenerates docs/reference/commands.md from CommandCatalog (the Swift command specs are the source).
set -euo pipefail
cd "$(dirname "$0")/.."
BASHCUT_UPDATE_COMMANDS=1 swift test --filter CommandReferenceTests >/dev/null
echo "Updated docs/reference/commands.md"
