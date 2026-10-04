#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p Fixtures/media
fixture_dir="$(mktemp -d Fixtures/media/native.XXXXXX)"
trap 'rm -rf "$fixture_dir"' EXIT
swift run bashcut-fixtures "$fixture_dir/test.mp4"
mv -f "$fixture_dir/test.mp4" Fixtures/media/test.mp4
