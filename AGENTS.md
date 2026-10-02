# Developing BashCut

Read docs/specs/README.md and docs/status/implementation.md. Develop only this repo; do not alter the video workspace or read tools/vendor.

- Swift 6, macOS 14. UI and document are MainActor; engine consumes immutable snapshots off the UI actor.
- All project edits use EditOperation/applying. Keep integer frame timing, rational source/project FPS, stable IDs and unknown JSON fields.
- Keep project/edit/render contracts in core. Optional heavyweight tools use the versioned out-of-process plugin API; never load third-party Swift code into the app process.
- English code/docs, localized English/Vietnamese UI. Do not translate user content.
- Run scripts/verify.sh build and test. SwiftLint --strict is the lint authority; never report a missing tool as PASS.
- Tests use generated media/temp folders, never real workspace files, agent CLIs, ML tools or network.
- Record meaningful changes in CHANGELOG.md. Do not commit generated projects, build products, secrets or test media.
