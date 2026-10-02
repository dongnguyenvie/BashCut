# Dependencies

| Dependency | License | Purpose / system alternative | Size |
|---|---|---|---|
| swift-collections | Apache-2.0 with Swift runtime exception | Deque for unlimited session undo; Array front removal has linear cost | Only DequeModule and support modules linked; binary contribution not measured |
| SwiftTerm | MIT | Real embedded PTY terminal for Claude/Codex/Shell; AppKit has no terminal emulator | Runtime dependency; contribution not measured |
| swift-argument-parser | Apache-2.0 with Swift runtime exception | Typed CLI parsing and help | CLI only; contribution not measured |
| swift-snapshot-testing | MIT | M0 golden image regression tests; XCTest has no image-diff assertions | Test-only; no app size contribution |

Exact revisions are in Package.resolved. SnapshotTesting resolves its own test support packages; see the resolved file and upstream license files. No third-party fonts or media are bundled. Core Text uses macOS fonts. AVFoundation, Core Image, Core Text, SwiftUI and AppKit ship with macOS.
