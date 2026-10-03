# BashCut documentation

BashCut is a native macOS video editor with a docked Claude Code / Codex terminal. Everything the UI does, an agent
can do through the `bashcut` CLI or MCP. Start with the section that matches what you want to do.

## Using and automating BashCut

| Guide | For |
|---|---|
| [Automation: CLI and MCP](guides/automation.md) | Driving the editor from agents, scripts and the terminal dock; the full command list |
| [Writing plugins](guides/plugins.md) | Adding transcription, voice, beat or loudness providers as out-of-process plugins |
| [Sample project](guides/sample-project.md) | A generated project with every timeline case, for manual testing and an end-to-end check |

## Reference

| Document | Contents |
|---|---|
| [Command reference](reference/commands.md) | Every CLI command and MCP tool with its parameters (generated) |
| [Project format reference](reference/project-format.md) | How `project.bashcut.json`, history and edits behave on disk |
| [Third-party dependencies](reference/third-party.md) | Packages, licenses and why each one is used |

## Status

| Document | Contents |
|---|---|
| [Implementation status](status/implementation.md) | What is built and verified, M0 benchmark results, known limitations |
| [Mockup parity](status/mockup-parity.md) | Native UI compared with the HTML mockup, area by area |

## Design specs

The [specs](specs/README.md) explain what BashCut is meant to be and why: goals, UI, file format, architecture,
agent integration, conventions and the roadmap.

## Contributing

[CONTRIBUTING.md](../CONTRIBUTING.md) covers building, verifying and the one-file templates for agent providers,
model adapters, commands, plugin capabilities and timeline formats. Changes are recorded in
[CHANGELOG.md](../CHANGELOG.md).
