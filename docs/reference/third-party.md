# Third-party dependencies

Every Swift package BashCut resolves, what it links into and under which license. The policy and the packages
considered for later are in [04 — Dependencies](../specs/04-dependencies.md). Exact revisions are pinned in
`Package.resolved` (root package) and `Packages/BashCutCore/Package.resolved` (core package).

## Direct dependencies

| Package | Version | License | Linked into | Why |
|---|---|---|---|---|
| [swift-collections](https://github.com/apple/swift-collections) | 1.7.1 | Apache-2.0 with Runtime Library Exception | `BashCutProject` (core package) | `Deque` for the bounded undo/redo stacks; only `DequeModule` is linked |
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | 1.20.0 | MIT | `BashCut` app | Embedded PTY terminal for the Claude, Codex and Shell tabs; AppKit has no terminal emulator |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | 1.8.2 | Apache-2.0 with Runtime Library Exception | `bashcut` CLI | Typed argument parsing and help |
| [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) | 0.12.1 (exact) | MIT, moving to Apache-2.0 (see below) | `bashcut-mcp` | Official stdio MCP server for Claude and Codex |
| [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | 1.19.6 | MIT | `BashCutEngineTests` only | Golden-image regression tests for the compositor; no app size contribution |

The root `Package.swift` declares SwiftTerm, swift-argument-parser, the MCP SDK and swift-snapshot-testing;
`Packages/BashCutCore/Package.swift` declares only swift-collections. Binary size contributions have not been
measured.

## Transitive dependencies

| Package | Version | License | Pulled in by | Linked |
|---|---|---|---|---|
| [swift-log](https://github.com/apple/swift-log) | 1.15.1 | Apache-2.0 | MCP SDK | `bashcut-mcp` |
| [swift-system](https://github.com/apple/swift-system) | 1.8.1 | Apache-2.0 with Runtime Library Exception | MCP SDK | `bashcut-mcp` |
| [eventsource](https://github.com/mattt/eventsource) | 1.5.1 | MIT | MCP SDK | `bashcut-mcp` |
| [swift-nio](https://github.com/apple/swift-nio) | 2.103.0 | Apache-2.0 | MCP SDK conformance tools | Not linked; resolved only |
| [swift-atomics](https://github.com/apple/swift-atomics) | 1.3.1 | Apache-2.0 with Runtime Library Exception | swift-nio | Not linked; resolved only |
| [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump) | 1.7.3 | MIT | swift-snapshot-testing | Tests only |
| [xctest-dynamic-overlay](https://github.com/pointfreeco/xctest-dynamic-overlay) | 1.13.1 | MIT | swift-custom-dump | Tests only |
| [swift-syntax](https://github.com/swiftlang/swift-syntax) | 604.0.0 | Apache-2.0 with Runtime Library Exception | swift-snapshot-testing | Tests only |

## License notes

- **MCP Swift SDK.** Its license file states that the MCP project is moving from MIT to Apache-2.0: new
  contributions are Apache-2.0, earlier contributions stay MIT until their authors consent, and documentation is
  CC-BY-4.0. Both licenses are permissive; ship both texts with any distributed build.
- Licenses were read from the checked-out package sources. Recheck them when a package is upgraded.

## Not bundled

- **Fonts and media.** None are bundled; Core Text uses the fonts installed with macOS.
- **Apple frameworks** (AVFoundation, Core Image, Core Text, SwiftUI, AppKit and others) ship with macOS.
- **Plugin dependencies** such as models, Python environments and analyzers live in out-of-process plugins and
  are installed only after the user reviews the exact commands. See [Writing plugins](../guides/plugins.md).
