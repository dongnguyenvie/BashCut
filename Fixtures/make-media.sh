#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p media
ffmpeg -hide_banner -loglevel error -y -f lavfi -i 'testsrc2=size=320x180:rate=30000/1001' \
    -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 2 -c:v libx264 -pix_fmt yuv420p -c:a aac media/test.mp4
