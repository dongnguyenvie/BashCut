# 05 — Agent integration (Claude Code / Codex)

BashCut hosts Claude Code and Codex in real terminals and gives them, and any other agent, the same command
surface as the editor UI. This spec records the design: how terminals are launched, how commands mirror the UI,
what context agents receive and how permissions work. The user-facing guide with the complete command list is
[Automation: CLI and MCP](../guides/automation.md).

## 1. Terminals in the dock

**Each dock tab is a PTY** ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)) running an interactive
CLI: `claude`, `codex`, or `zsh -i` for a Shell tab.

**Working directory.** Claude runs in the workspace root, so `CLAUDE.md`, the `nolan-*` skills, the self-learn
hook and `.mcp.json` work exactly as in a normal terminal. Codex runs in a stable
`~/Library/Application Support/BashCut/agent-workspace` folder under a named permission profile. The open
project reaches both as context (§3), not through the working directory.

**Environment.** The child gets an allowlisted environment (common shell variables plus `CLAUDE_*`,
`ANTHROPIC_BASE_URL` and `ANTHROPIC_MODEL` for Claude, `CODEX_*`, `OPENAI_API_KEY` and `OPENAI_BASE_URL` for
Codex) and:

- `BASHCUT_PROJECT=<project path>`
- `BASHCUT_SOCKET=<automation socket>`
- `BASHCUT_SESSION_TOKEN=<per-tab token>`
- a `PATH` that includes the folder holding `bashcut` and `bashcut-mcp`

`ANTHROPIC_API_KEY` is never passed to `claude`, so the user's subscription login is used.

**Sessions can be resumed.** The app finds and stores the session ID per project; the UI never shows it. The
dock offers **Continue <agent>** (resume) or **New conversation** (forget the saved session):

- Claude: `claude --resume <id> …`
- Codex: `codex … resume <id>`

### Connecting the agent to the app

| CLI | How the BashCut MCP server and instructions are attached |
|---|---|
| Claude | `claude --mcp-config '<inline JSON>' --append-system-prompt '<instructions>'`. The JSON names only the `bashcut-mcp` command, which inherits the tab's environment. Workspace MCP servers such as `davinci-resolve` stay available for legacy projects |
| Codex | `codex -m gpt-5.6-luna -c model_reasoning_effort="low" -c mcp_servers.bashcut={ command = …, env_vars = ["BASHCUT_SOCKET", "BASHCUT_SESSION_TOKEN"] } -c developer_instructions=…`, plus a permission profile that may write the socket folder and connect to that one socket |
| Both | The `bashcut` CLI is always on the tab's `PATH`, so the agent can use Bash even if MCP is not attached |

No MCP config or token is written into the project or workspace. `bashcut-mcp` is a thin stdio MCP server built
on the official Swift SDK; it forwards each tool call to the app's automation socket
([03 — Architecture](03-architecture.md) §6).

## 2. Commands: the same surface as the UI

Every command is declared once as a `CommandSpec` in `CommandCatalog`. One `CommandRegistry` validates requests
against the specs and serves every front end:

- MCP: tools named `bashcut_<group>_<command>`.
- CLI: `bashcut <group> <command>`.
- Agent instructions: rendered from the same specs.

The tables below show the design intent: which mode each area uses and which UI it mirrors; they are not a
complete list. The generated [command reference](../reference/commands.md) lists every command with its
arguments.

### Read and UI commands

| Command | Mode | UI equivalent |
|---|---|---|
| `context get` | read | Open project, selection, playhead; running analysis jobs and media not yet measured, transcribed or described |
| `project get` / `project recents` | read | Welcome screen, Recent projects |
| `timeline get [--format text\|json]` | read | Looking at the timeline, its transitions and section markers |
| `media list [--analysis]` / `media analyze` / `media analysis` | read | Library (`media analyze`: a measured record per source file with shots, motion, sound spans and file facts, read with `media analysis`) |
| `media cuts` | edit | Correcting the shots found in a source file |
| `media inventory` | read | None yet: capture time, place, device, orientation, speech and what is measured, transcribed and described, per media, folder and project |
| `media frames` / `media frame` / `media strip` | read | None yet: exact source frames, contact sheets (with a REF row) and a filmstrip with level, gaps and words, by source time |
| `media describe` / `media description` | edit / read | None yet: shot facts the agent saw in a source file (closed vocabulary), with their coverage |
| `audio measure --curve\|--timeline` / `audio mix-measure` | read | None yet: loudness over time of a file or of the mix, and the mix by role (voice, music under speech and in gaps, sound effects against the voice) |
| `speech rate` / `narration windows` / `voice voices` | read | None yet: speaking rate per speaker and voice, speech-free windows with a text budget, voices by facts |
| `voice check` / `voice fit` / `captions group` / `captions align` | read / edit | Voice panel takes, captions: check a take against its text, fit it to a slot, re-cut captions from word groups, captions from a script |
| `platforms list` | read | None yet: platform facts (zones, length, loudness) with the project's overrides and each output's loudness target |
| `review hook` | read | None yet: how the edit opens and closes (first words, titles, captions, cuts, described subjects; last title, words, cut) |
| `beats grid` / `audio energy` | read | None yet: the stored beat grid with strengths, downbeats, fit and alternates; the music's energy curve (level, onset, fullness); the agent picks lifts and drops |
| `color measure` | read | None yet: colour of each clip as numbers, source or graded, the change a grade makes and the distance from the median clip |
| `ui frames --compare graded\|source` | read | The viewer's Compare toggle, as one before/after grid per frame |
| `review cuts` / `review sync` / `review window` / `timeline sheet` | read | None yet: every cut with kind and framing; cuts, titles and sound effects timed against beats and words (and a render against the timeline); the frames, level and words around a frame; contact sheets of the composed edit with zones per output |
| `review run` / `review measure` / `review picture` / `review shots` / `review layout` | read | Review, Measure picture (`review picture`: the raw samples and cuts behind the picture checks; `review shots`: the shots on Main with timing, source, framing and motion; `review layout`: rendered text bounds next to the platform zones) |
| `captions export` | read | Text panel, Export SRT |
| `export status` / `jobs status` | read | Export queue, job progress |
| `plugins list` / `plugins health` | read | Plugins sheet, Check Health |
| `plugins search` / `plugins updates` | read | Plugins › Browse and Updates |
| `plugins actions` / `plugins hooks` / `plugins options <plugin>` | read | Plugin actions wherever they appear, Hook Activity, Options… |
| `doctor run` | read | Doctor sheet |
| `knowledge get` | read | Knowledge window: Notes and Skills |
| `knowledge lessons [--scope] [--status] [--tag] [--query] [--sort]` / `knowledge prefs` / `knowledge facts` / `knowledge proposals` / `knowledge history [--kind] [--target]` | read | Knowledge window: Lessons (search, filters, sort), Preferences, Project facts, Inbox, History; dock badge |
| `skills list [--scope project\|user\|plugin\|kit]` / `skills get <name> [--scope]` | read | Knowledge window › Skills: the project's, every project's, the plugins' (read-only, `<plugin-id>:<name>`) and the agent kit's skills with their descriptions, Edit and Preview |
| `ui frame [frame]` | read | Ask's attach viewer frame: the viewer picture at a frame as a PNG path |
| `ui actions` | read | Every toolbar button, menu item and shortcut, with its enabled state |
| `ui dialog` | read | Every open alert, file panel, sheet and popover |
| `ui respond <option> [--path]` / `ui open <dialog>` | ui | Answering or opening a dialog |
| `ui select` / `ui seek` / `ui panel` / `ui notify` | ui | Pointing something out to the user |
| `ui view [--zoom 10…140] [--snap] [--safe-area] [--compare] [--agent-dock] [--inspector <tab>] [--knowledge-section <section>] [--reveal <frame>]` | ui | Zoom slider and ⌘=/⌘−, Snap, Safe area, Compare, Agent button, Inspector tabs, Knowledge window sidebar, scrolling |
| `ui source <media> [--in N] [--out N]` | ui | Clicking a Library thumbnail (source viewer) |

### Edit commands

| Command | Mode | UI equivalent |
|---|---|---|
| `project create` / `project open` / `project save` | edit | New Project, Open, Save |
| `project folder [<path>] [--reset]` | edit | Settings › General › Projects folder (New Project's default Save in) |
| `edl import <edl.json>` | edit | Welcome screen, Import from edl.json… |
| `timeline apply <ops.json> --base-rev N --label "…"` | edit | Every cut, trim, drag and property change |
| `timeline undo` / `timeline redo` | edit | Undo, Redo |
| `timeline move` / `media place` / `layers add` | edit | Dragging clips, Import placement, Add layer |
| `media import <path> [--place]` | edit | Dropping files into the Library |
| `media proxy [media] [--force]` | edit | Media panel, Create Preview Proxy (imports queue proxies for heavy footage automatically) |
| `captions import <file.srt>` | edit | Text panel, Import SRT |
| `captions generate --media <id>` | edit, job | Auto Captions |
| `beats detect --media <id>` | edit, job | Detect Beats |
| `voice speak "<text>" [--takes N] [--keep-takes]` | edit, job | Voice panel, Generate + Insert; `--keep-takes` keeps every take for the take list |
| `jobs cancel <job>` | edit | Cancelling a job or queued export |
| `plugins run <action> [--params '{…}']` | edit, job | A plugin action in the Plugins menu, toolbar, a context menu, a panel or the inspector, with its parameter sheet |
| `plugins proposal <id> --decision apply\|discard` | edit | Reviewing an edit a plugin hook proposed |
| `plugins option <plugin> --option <id> [--value]` / `plugins set <plugin> [--enabled off] [--hooks off]` | edit | Plugins sheet: Options…, Enabled and Hooks switches (agents can only turn them off) |
| `plugins install <plugin> [--version]` / `plugins remove <plugin>` | edit | Browse › Install/Update (the approval stays with the user) and Installed › Remove |
| `luts import <file.cube> [--name]` | edit | Filters panel, Import .cube… |
| `knowledge memo <file> [--scope user]` / `knowledge skill <name> <file>` / `knowledge migrate [--to project]` | edit | Knowledge window › Notes and Skills: Save memo, Save notes, Save skill, Move older memo |
| `knowledge add-lesson` / `update-lesson` / `remove-lesson` / `approve [--value]` / `reject` / `set-pref` / `set-fact` | edit | Knowledge window: New lesson, Save, Enable/Disable, Delete…, Approve, Reject; Inbox Approve, Edit…, Reject; Preferences and facts Add, Save, Remove |
| `knowledge revert <change-id>` | edit | Knowledge window › History: Revert… |
| `knowledge split-memo <entries.json> [--scope user]` / `knowledge split-memo --keep` | edit | Knowledge window › Notes: Ask the agent to split it, Keep as notes (#72) |
| `skills save <name> <file> [--scope user]` / `skills enable` / `skills disable` / `skills remove` / `skills propose <name> <file> --summary` | edit | Knowledge window › Skills: Add, Save skill, On for agents, Share with Claude + Codex, Delete…, Propose change… (kit skills) |
| `ui action <id\|shortcut>` | edit | Any editor button or shortcut, run by the same code: `timeline.split` / `cmd+b`, `timeline.zoom-in` / `cmd+=`, `playback.toggle` / `space`, `source.mark-in` / `i`; plugin action IDs and shortcuts too |

### Privileged commands

| Command | Mode | UI equivalent |
|---|---|---|
| `export start --preset … --name …` | privileged | Export |
| `export otio --name …` | privileged | Export › OTIO |

### Planned commands

Not in the catalog yet:

| Command | Mode | UI equivalent |
|---|---|---|
| `media search "<speech>"` | read | Library, search by speech |
| `voice list` | read | Voice panel |
| `ui show <file>` | ui | Revealing a file to the user |
| `audio separate <item>` | edit | Inspector › Audio › Separate Voice |
| `voice enroll <media> --start --dur --name` | privileged | Clone New Voice |
| `resolve plan` | read | Apply to Resolve › preview of what will happen |
| `resolve apply --project <name>` | privileged | Apply to Resolve ([03 — Architecture](03-architecture.md) §7) |

### UI parity rule

Anything the user can click or press in the editor is an agent command:

- Buttons, menu items and shortcuts are `UIAction` cases (ID, title, shortcuts) that the views bind to and
  `ui action` runs.
- View state (zoom, toggles, scroll position, inspector tab) is `ui view`.
- Dialogs go through `ModalCenter`, so every alert, file panel, sheet and popover is visible to `ui dialog`
  and can be answered with `ui respond` or opened with `ui open`.

The export approval and plugin-install sheets only offer `deny` or `cancel` to agents; approving stays with
the user. `ui action` refuses while a dialog is open, and actions that open an alert or panel (`project.new`,
`project.open`, `project.import-media`) return at once so the agent can answer it.

A new UI feature is not finished until it has a `UIAction`, a `ui view` field, a dialog name or a
`CommandSpec`.

### Permissions

| Mode | Behavior |
|---|---|
| **read**, **ui** | Always allowed to local processes under the same OS account; no token needed. |
| **edit** | Allowed with a live session token, because every change is undoable and visible. Settings → **Allow agent timeline edits** (on by default) withholds tokens from Claude and Codex tabs when turned off. |
| **privileged** | Shows a confirmation sheet in the app with the author and arguments. Settings → **Approve agent actions without asking** (off by default; no automation command can change it) skips the sheet: such requests return `approval: "approved"` and are audited as `<method>.auto-approved`. Export is slow and writes large files; planned privileged commands include voice enrollment, which changes the shared `voices.json`, and file deletion, which is destructive. |

Settings → **Dangerously allow all agent actions** (on by default, user-only) turns all of the above on at once,
turns the scope guard (#356) off and skips plugin action confirmations for agents; `context get` reports it in
`agentPermissions`.

Plugin trust, turning a plugin or its hooks on, and Settings → **Apply plugin hook edits without review** are
user-only; agents may turn plugins or hooks off (`plugins set`) and apply or discard hook proposals. Plugins never
receive a token: their results come back through the app, are validated like agent edits and are committed by
author `plugin`, audited as `plugin.action.<action id>` or `plugin.hook.<event>`.

Every command is written to the audit log with its author and outcome. The rule is: read-only by default,
undoable edits with a token, explicit confirmation for anything slow or destructive.

The CLI's own tools (Bash, file edits) keep asking for permission inside the terminal as usual; BashCut does
not intercept them.

### Provider-backed feature commands

Agents never launch plugin entrypoints or dependency installers through BashCut's automation surface. A
feature command such as captions, voice, beats or normalized export asks the app to resolve the same
capability and provider as the native panel. The app validates the result and converts it to normal
`EditOperation` values, so revision checks, audit, provenance, change markers and undo behave identically.

- Provider calls can take minutes, so these commands return a job ID at once; `jobs status` reports
  `running`, `completed` (with the new revision), `failed` or `cancelled`, and `jobs cancel` stops a job.
- Each accepts an optional `provider` that overrides the project preference for that request only.
- Exports share the job center: each approved export, and each export started in the UI, waits as `queued`
  behind the running one. Exports render one at a time, in request order, from the project as it was when
  requested.
- Opening another project cancels and clears all jobs.

Installing a plugin or running its dependency recipes stays an explicit native Plugins workflow; an agent may
open or point to it but cannot approve it. Provider credentials are never placed in the terminal environment
or in automation requests. A future credential contract may use Keychain references, never secret values in
project JSON. The plugin protocol is described in [Writing plugins](../guides/plugins.md).

## 3. Context

### Timeline text form

Agents read the timeline with `timeline get --format text`. The format is compact and cheap in tokens, and
every line carries the item ID used for edits. The target form:

```text
project lau-bo-noi-dat  rev 142  1080x1920 29.97fps  1:49.81  48 cuts
SECTIONS hook 0:00.00 | street 0:12.26 | grill 0:25.71 | hotpot 0:41.40 | eat 1:02.10 | sidewalk 1:18.50 | outro 1:33.20
MAIN c-01 0:00.00-0:02.04 m-0449 speech z1.00          "Top 10 món nên ăn / ở Buôn Ma Thuột"
MAIN c-02 0:02.04-0:04.09 m-0450 speech z1.22 p40 t-30 "Một quán các bạn / KHÔNG nên ăn…"
…
VO   vo-1 0:26.11-0:29.20 voiceover/vo1.wav  "Trong lúc chờ lẩu sôi…"
MUS  mu-1 0:00.00-1:49.81 @assets/nhac/inspired.mp3 duck-14  beat 117.5bpm
```

Today's output is simpler: a header line (`project <name> rev <rev> <width>x<height> <fps>fps`) and one line
per item, `ROLE id at-end media=<id> in=<frame> <text>`, in frames.

### Context block

Agents read this block with `context get` (the session prompt has it when a tab starts). Requests sent from the
dock (Survey, Write VO, Review, ⌘K) are pasted alone, because agent CLIs fold a long paste into a placeholder that
hides the request. The block:

```text
[BashCut context]
project: /path/to/projects/lau-bo-noi-dat/project.bashcut.json
rev: 142
selection: c-25
playhead: 1144 frames
[/BashCut context]
```

When the user attaches the viewer frame, its PNG is written to `.bashcut/cache/agent-context` and the absolute path
is included. Agents capture the same PNG themselves with `ui frame [frame]`. The target form also carries the selection's track, media, tag, section, time range and caption
text.

### Agent instructions

Claude receives the instructions through `--append-system-prompt`; Codex through `developer_instructions`.
They are rendered from the command specs (`BashCut/Core/Automation/AgentInstructions.swift`), followed by the
context block and the knowledge (notes for every project, the project memo and skills with their paths), and say:

- Prefer the `bashcut_*` MCP tools; the `bashcut` CLI on `PATH` is the fallback.
- Read `context get` and `timeline get` before editing. Track IDs and roles are dynamic; never assume them.
- Respect the layer rules; prefer `media place` and `timeline move`, which find a free or new layer.
- Edit only through commands with `--base-rev` from the latest read. One request is one atomic apply. On
  `staleRevision`, re-read and retry.
- Job commands return a job ID to poll. Installing plugins is user-only. Exports need the user's approval.
- Never hand-edit `project.bashcut.json` while the app is open, never overwrite original footage, never render
  with ffmpeg.
- Ask before downloading media or installing tools. Reply in the user's language.

The instructions end with an example of every timeline operation. When Settings turns agent edits off, they
say so.

## 4. Example round trip

1. The user selects `c-25`, presses ⌘K, types "trim to 4 s, keep the so-much-topping line", and presses Enter.
2. Claude runs `bashcut timeline get --format text` and finds the clip and the line's timing.
3. Claude runs:

   ```sh
   bashcut timeline apply /tmp/ops.json --base-rev 142 --label "Trim c-25 to 4 s"
   ```

   with `ops.json`:

   ```json
   [{"op": "trim", "item": "c-25", "edge": "start", "toFrame": 1183, "ripple": true},
    {"op": "trim", "item": "c-25", "edge": "end", "toFrame": 1303, "ripple": true}]
   ```

4. The app applies the operations and `rev` becomes 143. The timeline updates immediately, the changed clip is
   marked, and a toast appears: "Claude: Trim c-25 to 4 s · [Undo]".
5. Claude runs `bashcut review run` to check the structure and speech coverage, then reports back.

## 5. Switching Claude ↔ Codex

The two CLIs don't share transcripts. When the user hands a task from one agent to the other, the app pastes a
*handoff* into the target tab (opening it if needed). Today it contains:

- the context block (§3);
- the timeline text form;
- the knowledge: notes for every project, the project memo (`<project>/.bashcut/agent-memory.md`) and project
  skills, with a hint under a memo not yet split into structured entries (`knowledge split-memo`, #72);
- a bounded summary of the structured knowledge (`.bashcut/knowledge/`, #67, #73): up to 20 active lessons
  (project first, newest first) with their fix, up to 30 preferences (a project value wins) and 30 project facts,
  each one line of at most 240 characters, and the number of proposals waiting for review. The same summary is in
  every new terminal's session prompt, in chat agents' context and in `context get` (`knowledge`).

Planned additions: the last 5 user requests, the last 5 labeled undo steps and the latest review result.

Codex reaches parity with Claude only once the workspace has `AGENTS.md` and `.agents/skills/`
([02 — Project format](02-project-format.md) §6). `knowledge skill` and `skills save` write project skills to both locations inside the project folder; skills for
every project stay in BashCut's Knowledge folder and reach BashCut's agents through the paths in their knowledge.

## 6. Later (P2): structured chat mode

If the terminal stops being enough (for example, for rich tool-call cards or diff-based approval in the UI),
add a headless mode:

- Claude: `claude -p --output-format stream-json --input-format stream-json --verbose --include-partial-messages --permission-prompt-tool …`
- Codex: `codex exec --json`

Both are **(to verify)**. Events from both CLIs would be normalized into one `AgentEvent` type in
`BashCutAutomation`. The terminal stays the default.
