# 05 — Agent integration (Claude Code / Codex)

## 1. Terminals in the dock

**Each dock tab is a PTY** ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)) running an
interactive CLI: `claude`, `codex`, or `zsh` for a Shell tab.

**`cwd` is the workspace root.** That keeps `CLAUDE.md`, the `nolan-*` skills, the self-learn hook
and `.mcp.json` working exactly as they do in a normal terminal. The open project is passed to the
agent as context (§3), not through `cwd`.

**Extra environment variables:**

- `BASHCUT_PROJECT=<project path>`
- `BASHCUT_SESSION_TOKEN=<per-tab token>`
- PATH rebuilt to include the directory that holds `bashcut`
- `ANTHROPIC_API_KEY` removed for `claude`, so the user's subscription is used

**Sessions can be resumed.** The app stores the session ID per project:

- Claude: `claude --resume <id>`.
- Codex: the resume command **(to verify)**.

### Connecting the agent to the app

| CLI | How BashCut's MCP server is attached |
|---|---|
| Claude | `claude --mcp-config <tmp-0600.json> --append-system-prompt "$(cat bashcut-prompt.md)"` <br>**(to verify)** that `--mcp-config` adds to the workspace `.mcp.json` rather than replacing it. The `davinci-resolve` server must stay available for legacy projects |
| Codex | `codex -c mcp_servers.bashcut.command=… -c mcp_servers.bashcut.env…` <br>**(to verify syntax)** |
| Both | The **`bashcut` CLI** is always on the tab's PATH, so the agent can use Bash even if MCP is not attached |

Temporary MCP config:

```json
{"mcpServers": {"bashcut": {
  "command": "/Applications/BashCut.app/Contents/MacOS/bashcut-mcp",
  "env": {"BASHCUT_SESSION_TOKEN": "<per-tab token>"}}}}
```

`bashcut-mcp` is a thin stdio MCP server built on the official Swift SDK. It forwards each tool
call to the app's automation socket (`03-architecture.md` §6).

## 2. Commands: the same surface as the UI

One `CommandRegistry` serves both front ends:

- MCP: tools named `bashcut_<group>_<command>`.
- CLI: `bashcut <group> <command>`.

### Read and UI commands

| Command | Mode | UI equivalent |
|---|---|---|
| `context get` | read | open project, selection, playhead, current tab |
| `project get` | read | Welcome screen |
| `project open` | ui | Welcome screen, Open |
| `timeline get [--range] [--format text\|json]` | read | looking at the timeline |
| `media list` / `media search "lau bo"` | read | Library, search by speech |
| `voice list` | read | Voice tab |
| `review run` | read | [Review] |
| `export status` | read | export queue |
| `ui select` / `ui seek` / `ui show <file>` / `ui notify` | ui | pointing something out to the user |

### Edit commands

| Command | Mode | UI equivalent |
|---|---|---|
| `project create` | edit | New Project |
| `timeline apply <ops.json> --base-rev N --label "…"` | edit | every cut, trim, drag, property change |
| `media import <paths>` | edit | dropping files into the Library |
| `captions generate [--range]` | edit | [Auto Captions] |
| `voice speak "<text>" --voice … --insert-at 12.3` | edit | Voice tab, Generate + Insert |
| `beats detect <media>` | edit | [Detect Beats] |
| `audio separate <item>` | edit | Inspector › Audio › Separate Voice |

### Privileged commands

| Command | Mode | UI equivalent |
|---|---|---|
| `voice enroll <media> --start --dur --name` | **dialogs** | Every alert, file panel, sheet and popover is visible to `ui dialog` and answerable with `ui respond` (option ID/title, or `--path` for file panels); `ui open` shows a named sheet. The privileged approval sheet only offers `deny` to agents. |
| **privileged** | [Clone New Voice] |
| `export start --preset … --name …` | **privileged** | [Export] |

### Reserved for later (not in v1)

| Command | Mode | UI equivalent |
|---|---|---|
| `export otio` | privileged | Export › OTIO |
| `resolve plan` | read | Apply to Resolve › preview of what will happen |
| `resolve apply --project <name>` | privileged | Apply to Resolve (`03-architecture.md` §7) |

### Permissions

| Mode | Behavior |
|---|---|
| **read**, **ui** | Always allowed. |
| **edit** | Allowed, because every change is undoable and visible. Settings has "Ask before the agent edits the timeline" for a stricter setup. |
| **privileged** | Shows a confirmation sheet in the app with the command and its arguments, unless the user turns on Settings → "Run agent exports without confirmation" (off by default; no automation command can change it); auto-approved requests return `approval: "approved"` and are audited as `<method>.auto-approved`. Export is slow and writes large files; voice enrollment changes the shared `voices.json`; file deletion is destructive. |

Every command is written to the session's audit log. The rule is read-only by default, with
explicit confirmation for destructive actions.

The CLI's own tools (Bash, file edits) keep asking for permission inside the terminal, as usual.
BashCut does not intercept them.

### Provider-backed feature commands

Agents never launch plugin entrypoints or dependency installers directly through BashCut's
automation surface. A feature command such as captions, voice, beats or normalized export asks the
app to resolve the same capability/provider used by the native panel. The app validates the result
and converts it to normal `EditOperation` values, so revision checks, audit, provenance, UI diffs
and undo behavior remain identical.

Implemented commands are `captions.generate` (media ID, optional replace), `beats.detect` (audio
media ID already on the timeline) and `voice.speak` (text, 1–8 takes, optional start frame; the best
take is inserted on the Voiceover track and the rest are deleted). Each accepts an optional
`provider` that overrides the project preference for that request only. Because provider calls can
take minutes, these edit-mode commands return a job ID at once; `jobs.status` reports `running`,
`completed` (with the new revision), `failed` or `cancelled`, and `jobs.cancel` stops a running job.
`plugins.list` exposes installed plugins, providers, project preferences and catalog diagnostics.
Exports share the same job center: each approved `export.start` (and each export started in the UI)
becomes an `export.start` job that waits as `queued` behind the running export, then runs; exports
render one at a time in request order from the project as it was when requested. `export status`
lists the queue with job IDs; while an export runs its top-level fields (`job`, `step`, `progress`,
`preset`, `path`, `includedSRT`) describe that export and the previous receipt moves to `lastExport`.
An export asked to include SubRip writes no `.srt` when the timeline has no captions. `jobs.cancel`
stops a queued or running export. Opening another project cancels and clears all jobs.

Installing a plugin or running its dependency recipes stays an explicit native Plugins workflow;
an agent may open or point to that workflow but cannot silently approve it. Provider credentials
are not placed in the terminal environment or automation request. A future credential contract may
use Keychain references, never secret values in project JSON.

## 3. Context

### Timeline text form

Agents read the timeline with `timeline get --format text`. The format is compact and cheap in
tokens, and every line carries the item ID used for edits:

```
project lau-bo-noi-dat  rev 142  1080x1920 29.97fps  1:49.81  48 cuts
SECTIONS hook 0:00.00 | street 0:12.26 | grill 0:25.71 | hotpot 0:41.40 | eat 1:02.10 | sidewalk 1:18.50 | outro 1:33.20
MAIN c-01 0:00.00-0:02.04 m-0449 speech z1.00          "Top 10 món nên ăn / ở Buôn Ma Thuột"
MAIN c-02 0:02.04-0:04.09 m-0450 speech z1.22 p40 t-30 "Một quán các bạn / KHÔNG nên ăn…"
…
VO   vo-1 0:26.11-0:29.20 voiceover/vo1.wav  "Trong lúc chờ lẩu sôi…"
MUS  mu-1 0:00.00-1:49.81 @assets/nhac/inspired.mp3 duck-14  beat 117.5bpm
```

### Context block sent by ⌘K or the chip

```
[BashCut context]
project: projects/lau-bo-noi-dat  rev: 142
selection: MAIN c-25 (m-0474, speech, section=hotpot) 0:38.12–0:44.62
caption: "Các bạn thấy chưa? / Quá trời là topping luôn"
frame: ~/Library/Application Support/BashCut/cache/frames/c-25@38.12.jpg
[/BashCut context]
trim to 4 s, keep the "so much topping" line
```

### Appended system prompt

For Claude this goes in `--append-system-prompt`. For Codex it is sent as the first message.

```
You are running inside BashCut, a video editor. The open project is $BASHCUT_PROJECT.
- Read the timeline with `bashcut timeline get` (or MCP bashcut_timeline_get) before editing.
- Edit ONLY through `bashcut timeline apply` with --base-rev; never hand-edit
  project.bashcut.json while BashCut is open. On staleRevision, re-read and retry once.
- One user request = one apply call with a clear --label (shown to the user as an undo step).
- "this clip / here / đoạn này" = the [BashCut context] selection; if none, run `bashcut context get`.
- Export only via `bashcut export start` (the user confirms in the app). Never render with ffmpeg.
- Legacy projects (edl.py + build.sh, no project.bashcut.json) keep their old Resolve workflow.
- Reply in the language the user writes in.
```

## 4. Example round trip

1. The user selects c-25, presses ⌘K, types "trim to 4 s, keep the so-much-topping line", and
   presses Enter.
2. Claude runs `bashcut timeline get --range 0:36-0:48`. Then it runs
   `bashcut media search "quá trời topping"` to get the word timestamps from the transcript.
3. Claude runs:

   ```
   bashcut timeline apply --base-rev 142 --label "Trim c-25 to 4 s" ops.json
   ```

   with `ops.json`:

   ```json
   [{"op": "trim", "item": "c-25", "edge": "start", "to": "0:39.50", "ripple": true},
    {"op": "trim", "item": "c-25", "edge": "end", "to": "0:43.50", "ripple": true}]
   ```

4. The app applies the operations and `rev` becomes 143. The timeline updates immediately and a
   toast appears: "Claude: Trim c-25 to 4 s · [Undo]".
5. Claude runs `bashcut review run --range …` to check that the voiceover doesn't overlap real
   speech and that no new silence appeared. Then it reports back.

## 5. Switching Claude ↔ Codex

The two CLIs don't share transcripts. When you open a Codex tab on a project you just worked on
with Claude (or the reverse), the app sends a *handoff* as the first message. It contains:

- the project memo (`memos/<date>-<video>.md`, if any);
- the last 5 user requests;
- the last 5 labeled undo steps;
- the latest review result.

Codex reaches parity with Claude only once the workspace has `AGENTS.md` and `.agents/skills/`
(`02-project-format.md` §6).

## 6. Later (P2): structured chat mode

If the terminal stops being enough (for example, you want rich tool-call cards or diff-based
approval in the UI), add a headless mode:

- Claude: `claude -p --output-format stream-json --input-format stream-json --verbose --include-partial-messages --permission-prompt-tool …`
- Codex: `codex exec --json`

Both are **(to verify)**. Events from both CLIs are normalized into one `AgentEvent` type
(`BashCutWire`). The terminal
stays the default.
