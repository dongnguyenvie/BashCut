#!/bin/bash
# Regenerates docs/reference/project.schema.json from ProjectSchema (the Swift declarations are the source).
set -euo pipefail
cd "$(dirname "$0")/../Packages/BashCutCore"
BASHCUT_UPDATE_SCHEMA=1 swift test --filter ProjectSchemaTests >/dev/null
echo "Updated docs/reference/project.schema.json"
