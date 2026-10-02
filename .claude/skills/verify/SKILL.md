---
name: verify
description: Build, test or lint BashCut and retain full logs.
---

Run `scripts/verify.sh build`, `scripts/verify.sh test`, or `scripts/verify.sh lint` from the repo root as appropriate. Generate fixture media once with `Fixtures/make-media.sh` before engine tests. Full output is retained under build/logs. Use `scripts/verify.sh perf` for the synthetic engine budget; it is not a substitute for real DJI playback and scrub measurements. Never claim unavailable tools passed.
