# Automation: CLI and MCP

BashCut can be driven by agents, scripts and the built-in terminal dock. This guide covers how they connect,
and every command they can run. The design rationale is in
[05 — Agent integration](../specs/05-agent-integration.md).

## Overview

The app runs one local JSON-RPC server on a Unix socket. Two thin clients talk to it:

- `bashcut`, a command-line tool bundled with the app.
- `bashcut-mcp`, a stdio MCP server built with the official MCP Swift SDK. It exposes each command as a
  tool named `bashcut_<group>_<command>` (for example `bashcut_timeline_get`).
  Every result is the tool's text: string results as they are, everything else as compact JSON. There is no
  `structuredContent` (the SDK re-decodes it slowly, and compact text is also fewer tokens for the agent).
  While BashCut runs, the tool list also has one `bashcut_action_<action id>` tool per installed plugin action,
  with the action's parameters as its input schema; calling it is `plugins run <action> --params …`. At most 40
  are listed, so hundreds of plugins do not crowd out the built-in tools: actions available with the current
  selection come first, then the most recently run. Every other action is still found with
  `plugins actions <text>` and run with `bashcut_plugins_run`, and its `bashcut_action_…` name still works.

Both clients forward to the same handlers the UI uses. Edits go through the validated `EditOperation` and
history path, so permissions, revision checks, audit records and undo behave the same whether a change comes
from a click, the CLI or MCP.

### Socket protocol

- The socket is `~/Library/Application Support/BashCut/automation.sock`; set `BASHCUT_SOCKET` to use
  another path. The folder is `0700` and the socket `0600`. Run one BashCut instance per socket.
- Each connection carries one newline-delimited JSON-RPC 2.0 request with `id`, `method`, `params` and an
  optional `token`. Messages are limited to 8 MiB, with a 10-second I/O timeout.
- Metadata-only audit records go to `~/Library/Application Support/BashCut/audit.jsonl`. Request contents and
  credentials are never recorded.
- This is a local automation service, not a security boundary against other software already running as the
  same user.

Common error codes:

| Code | Meaning |
|---|---|
| `-32001` | The command needs a live session token |
| `-32002` | Stale revision: re-read the timeline and retry |
| `-32003` | Busy: a dialog is open, another approval is pending, or the action is not available now |
| `-32601` | Unknown command |
| `-32602` | Invalid or missing parameters, or a rejected edit |

## Terminal dock

Open a terminal with **Agent → + → Claude terminal / Codex terminal / Shell terminal**. Each tab is a real
SwiftTerm terminal. Claude and Codex use your installed CLI and its existing login.

- **Workspace.** Choose a workspace before opening a tab. Claude runs in the workspace folder. Codex runs in
  `~/Library/Application Support/BashCut/agent-workspace`; the project path and project knowledge reach it
  through the session context.
- **Knowledge.** The book button opens the **Knowledge** window, which can stay open while agents work and shows
  their changes as they happen. Its sections are Lessons, Preferences, Project facts, Notes (the memos) and Skills;
  `ui view --knowledge-section <section>` switches between them. The project memo and project skills live in the
  project folder (`.bashcut/agent-memory.md`, `.bashcut/skills`, linked into the project's `.claude/skills` and
  `.agents/skills`), never in the workspace or home folder, so each project keeps its own. **Notes for every
  project** (`~/Library/Application Support/BashCut/Knowledge/agent-memory.md`) hold your taste and rules that
  every project reads. Without a saved project only those notes are available. A memo that older versions kept in
  the workspace or home folder is offered once: move it to the notes for every project (`knowledge migrate`) or to
  this project (`knowledge migrate --to project`). Agents write the notes with `knowledge memo FILE --scope user`,
  which asks for your approval. A memo with text is offered once for a split into lessons, preferences and facts:
  **Ask the agent to split it** puts the request in the open agent's input, and the agent runs `knowledge
  split-memo ENTRIES.json [--scope user]` (`{"lessons": [{"title", "symptom", "cause", "fix", "tags"}], "prefs":
  [{"key", "value"}], "facts": [{"key", "value"}]}`). What it finds waits in the **Inbox**; the memo stays as notes.
  **Keep as notes** (`knowledge split-memo --keep`) stops the offer.
- **Lessons, preferences and facts.** Next to the memos, agents keep structured knowledge as JSON files in the
  same two places (`.bashcut/knowledge/` in the project, `Knowledge/` for every project):
  - **Lessons** (`knowledge lessons`, `add-lesson`, `update-lesson`, `remove-lesson`): a title, the symptom, its
    cause, what to do next time, evidence and tags. Each has a status: `active` lessons are followed, `proposed`
    ones wait for your review, `disabled` ones are kept for the record. The source records which agent wrote it,
    in which session and when.
  - **Preferences** (`knowledge prefs`, `set-pref`): your taste as key/value pairs, for every project by default. A
    value set for one project wins over the one for every project.
  - **Facts** (`knowledge facts`, `set-fact`): people, places, footage notes and what was approved, for this project.
  - **Proposals** (`knowledge proposals`, `approve`, `reject`): what waits in the Knowledge window's **Inbox**. A
    lesson an agent records for every project always starts as a proposal (ID `l-…`); approving makes it active,
    rejecting removes it. An agent's preference change for every project (`set-pref`) is not applied at once: it
    waits as a value proposal (ID `p-…`, kept in that scope's `proposals.json`) and `set-pref` returns
    `{"approval": "proposed", "proposal": …}`. A newer proposal for the same key replaces the older one. `approve
    p-… --value TEXT` applies your edited value instead. Kit change proposals (lessons tagged `kit`, written by the
    `bc:self-learn` skill) show their diff. When Settings lets agents act without confirmation, preferences are
    applied at once as before.
  - **History** (`knowledge history [--kind] [--target]`, `revert`): every change to lessons, preferences, facts,
    memos and project skills, newest first, with who made it, the entry before and after and a line `diff`
    (`history.jsonl`). The Knowledge window's **History** section shows the diff; **Revert…** or `knowledge revert
    <change-id>` puts the entry back to how it was before that change, undoing later changes to it too, and is
    recorded as a change of its own. Rejecting a preference proposal changed nothing, so it has nothing to revert.
  - **Skills** (`skills list [--scope kit|user|project]`, `get`, `save`, `enable`, `disable`, `remove`, `propose`):
    the agent kit's skills are read-only; `skills propose <name> <file> --summary TEXT` sends the line diff against
    the kit's SKILL.md to the Inbox as a lesson for every project tagged `kit`. Skills you or agents write live in the
    project (`.bashcut/skills/<name>`, linked into the project's `.claude/skills` and `.agents/skills`) or, with
    `--scope user`, for every project (`Application Support/BashCut/Knowledge/skills/<name>`, listed with its path in
    BashCut agents' knowledge). `disable` turns one off without deleting it: a project skill is unlinked, a skill for
    every project gets a `.disabled` marker and is left out of the agents' knowledge. Saves and removals are in
    History, so `knowledge revert` brings a deleted skill back. The Knowledge window's **Skills** section lists all
    three groups with an editor and Markdown preview.

  An agent's request that otherwise changes knowledge for every project (memo, lesson edits and removals, skills for
  every project, reverts),
  or approves or rejects a proposal, asks for your approval. Changes to this project's lessons and facts do not.

  The book button in the agent dock shows an orange count while proposals wait (clicking it opens the Inbox) and a
  dot when agents changed knowledge since you last closed the window.

  In the Knowledge window, Lessons can be searched, filtered by scope, status and tag, and sorted newest or oldest
  first (`knowledge lessons --query --scope --status --tag --sort`). Select a lesson to edit its fields, approve or
  reject a proposal, enable or disable it, or delete it (history keeps it). Preferences and facts are edited in
  place. Each entry shows which agent and session added it and when, and entries changed since you last opened the
  window carry a **New** badge. Your changes are recorded with the source `user`.

  Every agent session starts with a short summary: the active lessons (at most 20, this project's first), the
  preferences and the project facts (at most 30 each), and how many proposals wait for you. Proposed and disabled
  lessons are not in it. `context get` returns the same summary as `knowledge`, so an agent outside BashCut's
  terminals sees it too.
- **Resuming.** When BashCut has found the last Claude or Codex conversation for the project, the dock offers
  **Continue Claude/Codex** or **New conversation**. You never see or type session IDs.
- **Codex defaults.** Codex starts idle on `gpt-5.6-luna` with low reasoning effort, under a named permission
  profile that extends its workspace profile with the BashCut folder and the exact BashCut socket. It does not
  get a broad socket allowlist.
- **Requests.** Survey, Write VO and Review paste a short request into the terminal for you to review before
  pressing Enter; agents read the selection and playhead themselves with `context get`. **Ask agent…** (⌘K) opens
  a sheet with request templates, Clear and Send, which pastes the request and presses Enter. It can attach the
  current viewer frame: BashCut renders a bounded PNG into
  `.bashcut/cache/agent-context`, keeps the ten newest frames and passes the absolute path to the terminal.
- **Switching projects.** Tabs stay open when the project changes, also when their own agent creates or opens
  one (before, the switch closed the tab mid-task). Every token, in-app or external, must then read the new
  project (`context get`, `timeline get` or `project get`) before its next edit; until then edits fail with
  "The open project changed to …", so an agent cannot apply what it remembers of the old project. Open
  conversations are bookmarked for the new project too, so **Continue** there resumes them.

Each child process gets a filtered environment plus:

- `BASHCUT_SOCKET`, `BASHCUT_PROJECT` and an in-memory `BASHCUT_SESSION_TOKEN`;
- a `PATH` that includes the bundled `bashcut` and `bashcut-mcp`;
- for Claude and Codex, a temporary MCP server definition on the command line. No MCP config or token is
  written into the project.

Claude does not inherit `ANTHROPIC_API_KEY`, so it uses your CLI login. Shell tabs edit as the user; Claude and
Codex tabs have their own authors. Closing a tab revokes its token. Keep tokens out of scripts, logs and
project files.

**Settings → Allow agent timeline edits** is on by default. When it is off, Claude and Codex tabs get no
token, so they can read and point at things but cannot edit.

## Agent kit

The [agent kit](https://github.com/dongnguyenvie/bashcut-agent-kit) is a set of editing skills (footage survey,
beat cuts, audio mix, captions, colour, effects, voiceover…) for Claude Code and Codex. BashCut ships a copy in
`Contents/Resources/AgentKit` (`scripts/bundle-agent-kit.sh`, run by `scripts/run.sh` and the Xcode build, copies
the tracked files of a `bashcut-agent-kit` checkout next to the repo, or `$BASHCUT_AGENT_KIT`). **Settings → Agents**
and `agent status` / `agent setup` manage it. The kit is the plugin `bc`, so Claude Code and Codex show its skills
as `bc:audio-mix`, `bc:edit-workflow`, … (kits before 0.1.0 were the `bashcut` plugin, `bashcut:bashcut-<skill>`).

- **Finding it.** When Claude Code or Codex is installed but lacks the kit (or has an older one), the agent dock
  shows a banner: **Set Up** (or **Update**) runs `agent setup` for each of them, **Details…** opens Settings →
  Agents (`ui action show.agent-kit`; also Agent › Agent Skills… and ☰), and **Later** (`ui action
  agent.kit-later`) hides it until BashCut has a newer kit.

- **Kit updates.** Settings → Agents checks the kit's signed releases (`releases.json` on bashcut-agent-kit's
  `main`) and offers **Download & Update** (`agent kit-check`, `agent kit-update`; the update asks for approval).
  BashCut installs a release only over HTTPS from GitHub, with a first-party ed25519 signature checked before the
  download and the SHA-256 after it, into `~/Library/Application Support/BashCut/agent-kits/<version>`. The newer
  of that download and the built-in kit is used; a chosen folder is never updated. After installing, Claude Code
  and Codex are refreshed where the kit is set up. Claude Code caches the plugin per version, so its row shows
  "Older kit set up" until **Update** runs.

- **BashCut's tabs** load it by default (`agent setup in-app`, `--remove` to stop). The built-in kit is copied to
  `~/Library/Application Support/BashCut/agent-kit`. Claude tabs get a skills-only plugin
  (`agent-kit-claude`, passed with `--plugin-dir`; the tab already has the BashCut MCP server). Codex tabs see
  the skills as links (`bc-<skill>`) in `agent-workspace/.agents/skills`, which holds only the kit's skills.
- **Another kit folder** (a checkout being worked on): **Choose…** in Settings or `agent setup in-app --kit
  /abs/path` (`--kit built-in` to go back). It is used in place, so edits show up in the next tab.
- **Claude Code and Codex outside BashCut**: `agent setup claude` adds the kit as the `bashcut-agent-kit`
  marketplace and installs the `bc` plugin (skills and MCP server), uninstalling the old `bashcut` plugin;
  `agent setup codex` links the skills into `~/.agents/skills` as `bc-<skill>` (never over a folder that is not a
  link), removes the old kit's `bashcut-<skill>` links, and runs `codex mcp add bashcut`. An old `bashcut` plugin
  shows as an older kit until **Update** runs. `--remove`
  undoes either. From the CLI this asks for approval like an export, because it changes the agents' own
  configuration.
- **Configuration folders.** Claude Code and Codex may keep their login and settings elsewhere
  (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`), often set in a shell profile that BashCut does not see when it starts
  from Finder. Each folder comes from Settings (`--claude-config-dir`, `--codex-home`; `default` detects
  again), else BashCut's environment, else the login shell (`$SHELL -ilc`, read once at launch), else
  `~/.claude` / `~/.codex`. The result is used for setup, for the tabs' environment and for finding their
  sessions to resume. `agent status` shows each folder and where it came from.

## Agents outside BashCut

Claude Code in another terminal, scripts and other MCP clients need no copied token. While BashCut runs, it
writes a fresh token to `~/Library/Application Support/BashCut/automation-token` with mode `0600`, next to the
`0600` socket, so the file grants nothing beyond what can already open the socket. The CLI and `bashcut-mcp`
read it whenever `BASHCUT_SESSION_TOKEN` is not set.

- Edits are attributed to `agent` and get the same change markers and Undo toast as Claude and Codex.
- Unlike in-app terminal tokens, this token survives project switches.
- BashCut deletes the file when it quits. **Settings → Agents outside BashCut** turns it off or issues a new
  token.
- Exports still wait for your approval in the app.

## Version and updates

`app version` returns this copy's version, build, plugin API and how it was installed: `homebrew`, `direct` (a zip
or dmg), `app-store` (App Store or TestFlight) or `development` (`scripts/run.sh`). `app update-check` asks GitHub
for the latest release (`api.github.com/repos/<owner>/<repo>/releases/latest`, from `BCRepositoryURL`) and returns
`updateAvailable`, the `latest` release and `update`: the Homebrew command or the release page. It never installs
anything, and App Store copies are not checked.

The UI does the same in **BashCut › Check for Updates…** (`ui action show.updates`, also ☰ and Settings ›
General). Homebrew and downloaded copies also check once a day when a project opens (**Settings › General ›
Check for BashCut updates daily**). A newer release then opens Software Update by itself, once per launch, as the
`updates` sheet with the options `skip` (**Skip This Version**, `ui action app.update-skip`: no reminders until a
newer release), `later` (**Remind Me Later**, `ui action app.update-later`: not before the next day) and `close`.
Until a release is skipped, ☰ shows a dot and an **Update to BashCut …** item. The last answer is remembered, so the
prompt and the dot work without asking GitHub at every launch. `ui action show.about` opens About BashCut.

Development builds (`scripts/run.sh`) check only on demand. To try the prompt, start one with
`BASHCUT_UPDATE_FEED=<release.json>` (a file shaped like GitHub's release JSON: `tag_name`, `html_url`,
`published_at`, `body`; read instead of GitHub) and `BASHCUT_UPDATE_INSTALL=homebrew` or `direct`, for example
`open --env BASHCUT_UPDATE_FEED=/tmp/release.json --env BASHCUT_UPDATE_INSTALL=homebrew build/BashCut.app`.
Release builds ignore both.

## Commands

Every command is declared once as a `CommandSpec` in `BashCut/Core/Automation/CommandCatalog.swift`: its name,
permission mode, parameters (type, range, choices, default and CLI binding) and whether it runs immediately,
as a background job or after in-app approval. The socket validates every request against its spec before the
handler runs, so the CLI and MCP return identical errors. The CLI parser, the MCP tool list and
schemas, and the agent instructions are all generated from these specs.

Print every usage line (also shown by `bashcut --help`) with:

```sh
bashcut help
```

Add `--format text` to any command to print string results without JSON quoting. MCP tools take the same
parameter names as the JSON-RPC `params` (`baseRev`, `atFrame`, …); the CLI spells them as options
(`--base-rev`, `--at-frame`). Relative paths given to the CLI are made absolute against its working
directory.

### Permission modes

| Mode | Token | Behavior |
|---|---|---|
| `read` | Not needed | Reads state; changes nothing |
| `ui` | Required | Controls selection, playback, panels and dialogs; dialog responses can also apply edits |
| `edit` | Required | Changes the project as one undoable, visible step; edits also need the current `--base-rev` |
| `privileged` | Required | Waits for the user to approve in the app (see [Exports and approval](#exports-and-approval)) |

### Command reference

**[Command reference](../reference/commands.md)** lists every command with its usage, mode, how it runs, MCP
tool name and parameters (types, ranges, choices, defaults). It is generated from the catalog
(`scripts/update-commands.sh`) and a test fails when it is out of date, so it never misses a command.

- Plugin actions: agents get the workflow in their instructions (list → select → run → `jobs status`), and the
  session context lists every installed action with its `when` condition and parameters. Plugin actions also
  appear in `ui actions` and run with `ui action <id>`. See [Writing plugins](plugins.md#commands).
- `ui frame [frame]` renders the viewer picture to a PNG for agents to look at; it never moves the playhead.

#### Allowed values

| Parameter | Values |
|---|---|
| `timeline get --format` | `json` (default), `text` |
| `project create --canvas` | `portrait` (default), `landscape`, `square` |
| `project create --resolution` | `720`, `1080` (default), `2160` (short side) |
| `project create --fps` | `29.97` (default), `30`, `24`, `60` |
| `project create --language` | A language tag; defaults to `vi` |
| `project create --dir` | An existing absolute folder; defaults to the projects folder (`project folder`, `~/Movies/BashCut` unless changed), made on first use |
| `layers add --kind` | `video`, `adjustment`, `text`, `audio` |
| `adjustment add --look`, `style save --look` | Built-in `original` (default), `vivid`, `muted-film`, `black-white`, or a custom look ID from `timeline get` |
| `style apply <kit>` | Built-in `food-review` (vivid, Bold Outline), `cinematic` (muted film, Cinematic Serif), or a custom kit ID |
| Grade options | `--exposure` −10…10, `--contrast` 0…4, `--saturation` 0…4, `--lut-strength` 0…1 (decimals allowed), `--lut` a LUT ID |
| `style save --caption-preset` | `bold-outline` (default), `cinematic-serif`, `keyword-sticker`, `place-card`, `hook-title`, `chapter-card` |
| `media import --kind` | `video` (default), `audio` |
| `export start --preset` | `tiktok`, `youtube-1080`, `youtube-4k`, `quick-draft`, `prores` |
| `ui open <dialog>` | `new-project`, `export`, `export-report`, `agent-changes`, `review`, `history`, `plugins`, `settings`, `doctor`, `knowledge`, `ask`, `sections`, `external-changes`, `plugin-proposals` |
| `ui panel <panel>` | `media`, `audio`, `text`, `stickers`, `effects`, `transitions`, `filters`, `voice` |
| `ui view --zoom` | 1–600 pixels per second; `--zoom-anchor` is the frame kept in place (the playhead by default) |
| `ui view --snap`, `--safe-area`, `--compare`, `--agent-dock` | `on` / `off` (also `true`/`false`, `yes`/`no`, `1`/`0`) |
| `ui view --inspector` | `video`, `audio`, `text`, `color`, `speed` |

### Adding a command

Add one `CommandSpec` to the catalog and one `handle`/`handleAuthored` registration in `ProjectDocument`, then
run `scripts/update-commands.sh`. Debug builds assert that every spec has a handler, `CommandSpecTests` checks
names, schemas and CLI bindings, and `CommandReferenceTests` fails until the reference is regenerated. If
the command mirrors something in the UI, see the parity rule in
[05 — Agent integration](../specs/05-agent-integration.md#ui-parity-rule). The step-by-step checklist is in
[CONTRIBUTING.md](../../CONTRIBUTING.md).

## Editing the timeline

Edit commands need a live session token and the current revision as `--base-rev`. The server rejects stale
revisions, file conflicts, busy operations and active timeline gestures; re-read the timeline and retry. Each
apply is atomic and creates one undo step. The response has the new `rev` and `changed`. A batch that leaves the
project exactly as it was returns `changed: false` with the current `rev`: no new revision, undo step, agent diff
marks or plugin hooks.

```sh
bashcut context get
bashcut timeline get --format text
bashcut timeline apply /absolute/path/ops.json --base-rev 12 --label 'Trim opening'
bashcut timeline undo --base-rev 13
bashcut timeline redo --base-rev 14
```

`context get` and `ui view` return the primary selected item as `selection` (the one last clicked, which
single-clip actions use) and every selected item as `selectedItems`. `ui select a --items b,c` selects several
items (`--add` keeps the current selection). Delete, Lift, Copy, Cut, Paste and Mute (`ui action timeline.delete`,
`clip.copy`, `clip.cut`, `clip.paste`, `clip.mute`) act on the whole selection as one undo step;
`timeline.select-all` and `timeline.deselect` change it.

`ui action clip.send-to-agent` (Send to Agent) attaches the selected items to the open agent's request, and
`chat attach --items a,b` / `chat detach [--items a]` do the same for a chat agent. While items are attached,
`context get` lists them as `scope` (`{plugin, scope: [{id, linked, track, layer, name, start, end}]}`) and every
chat message starts with a `[Scope]` block: edit only those items and ask before changing anything else.

Use `timeline apply ... --dry-run` (MCP parameter `dryRun: true`) to validate the same batch on a copy.
It checks the base revision, locks and project invariants, but changes no revision, undo history, files,
preview or plugin hooks. The response has `dryRun: true`, current `rev`, `projectedRev`, predicted `duration`
and `previousDuration` in frames, `changedItems`, `changedTracks`, `addedTracks` and `removedTracks`.
Changed item IDs include additions, deletions, property changes and moves. A live edit token is still required.
The preview does not reserve a revision; apply the batch with the same base revision and handle stale errors.


### Timeline operations

`ops.json` is an array of up to 1,000 operations:

```json
[
  {"op": "split", "item": "clip-1", "atFrame": 30, "newID": "clip-right"},
  {"op": "setProperties", "item": "clip-right", "patch": {"transform": {"zoom": 1.2}}}
]
```

- **Operations.** `insert`, `delete`, `split`, `trim`, `roll`, `slip`, `move`, `reorder`, `setSpeed`, `setProperties`,
  `setLinkedAudio`, track operations (`addTrack`, `moveTrack`, `setTrackProperties`, `deleteTrack`),
  `setProjectProperties`, `setProviderPreference`, `setBeatGrid`, `upsertSection`, `deleteSection`,
  `upsertTransition`, `deleteTransition`, `addColorLUT`, `deleteColorLUT` and `setFormat` (the canvas size; the
  `project format` command and the toolbar's format menu use it). The agent instructions
  (`BashCut/Core/Automation/AgentInstructions.swift`) show an example of each.
- **Frames.** All frames are integers. `atFrame` and `toFrame` are absolute timeline frames; an item's `in` is a
  source frame at that media's FPS.
- **Property patches** replace the top-level keys they supply, so keep existing nested fields when you change
  color, transform or tags.
- **Sections and LUTs** keep stable IDs. A LUT catalog entry uses a project-relative `luts/*.cube` path and a 3D
  size from 2 through 64. Apply it with `setProperties` on `color.lut`, with optional `color.lutStrength` from 0
  through 1.
- **Transitions.** `upsertTransition` takes stable `from`/`to` clip IDs, a kind (`dissolve`, `whip`, `blink`,
  `zoom`, `spin`, `shutter` or `wipe`), an integer-frame `duration` and an optional `easing` (`linear`, the default,
  `in`, `out` or `inOut`; preview and export shape the tween the same way). The clips must be adjacent on one video
  track. `deleteTransition` restores a hard cut; moving or deleting either clip removes a transition that no
  longer describes a valid cut.
- **Roll.** `{"op": "roll", "item": "ID", "edge": "end", "toFrame": 75}` moves the shared cut with exactly one
  adjacent clip; `edge: "start"` uses the preceding clip. Both clips must stay nonempty and within source
  bounds, and the rest of the track and the total duration stay fixed.
- **Slip.** `{"op": "slip", "item": "ID", "sourceIn": 100}` sets an absolute source start without changing
  timeline position or duration. It rejects text items and source overruns.
- **Rejections.** Invalid render values, unsafe LUT paths, duplicate section boundaries, missing media, source
  overruns and Main overlaps are rejected, and nothing is applied.

Source-viewer insert and overwrite plan a group of these same operations.

### Captions (SubRip)

`bashcut captions import /path/captions.srt --base-rev N` appends cues; `--replace` replaces the caption track
atomically. Stale revisions and malformed files leave existing captions untouched.
`bashcut captions export --format text` writes SRT to stdout without changing the project. The Text library
offers the same import, add, replace and export workflows.

Input is UTF-8, at most 4 MiB and 10,000 cues. BOM, CRLF, multiline text and comma or period milliseconds are
accepted. Timing rounds to the nearest project frame; reversed, out-of-bounds or sub-frame cues are rejected.
Export sorts cues and keeps Unicode text. Paragraph gaps collapse to single line breaks because blank lines
delimit SRT cues. Inline markup stays literal text; rich caption styling lives only in the project format.

## Layers and placement

Layer commands follow the layer rules in [02 — Project format](../specs/02-project-format.md#rules).

```sh
bashcut layers add --kind video --role overlay --name "B-roll 2" --base-rev 12
bashcut media import /path/to/clip.mp4 --place --base-rev 12
bashcut media place --media MEDIA_ID --track TRACK_ID --at-frame 90 --base-rev 13
bashcut timeline move ITEM_ID --track TRACK_ID --at-frame 120 --base-rev 14
```

Track IDs and roles are dynamic: always take them from `timeline get`. `media place` and `timeline move` use
the same planner as the timeline UI. When the range is taken, the clip goes to the next free layer of the same
kind and role, or to a new layer next to the target, and linked sound follows onto a dialogue layer. Both
return the layer actually used. Raw `timeline apply` insert and move operations that would overlap are
rejected.

`media import` of a file the project already has (same path, same kind, rate, length, size and sound) reuses
that media and returns `existing: true` instead of adding a duplicate. With `--place` it still places a new
item; without it the revision stays the same.

## Library items

The library panels (Audio, Text, Stickers, Effects, Transitions, Filters, Voice) are collections of items with one
model (#66). An item has an `id`, a `kind` (`audio`, `text-preset`, `sticker`, `effect-preset`, `transition-preset`,
`look`, `voice`), a `name`, `tags`, a `pack`, `source` and `license`, `createdBy` (user, agent or plugin),
`version`, usage, an optional copied `file` and `preview`, and `params` with what the kind needs.

Items come from four scopes; when the same ID is in several, the first wins, and `scope:id` picks one:

| Scope | Where | Writable |
|---|---|---|
| `project` | `.bashcut/library/library.json`, `usage.json` and `files/` in the project folder; travels with the project | yes |
| `user` | `~/Library/Application Support/BashCut/Library` (this Mac) | yes; agents need approval |
| `plugin` | A pack in a plugin's `contributes.library` (#81), while the plugin is installed, trusted and on | no |
| `built-in` | Shipped with BashCut | no |

Built-in packs: **Text styles** (`bold-outline`, `cinematic-serif`, `keyword-sticker`, `place-card`, `hook-title`,
`chapter-card`), **Emoji** stickers (`fire`, `yum`, `thumbs-up`, `hundred`, `star`, `pin`, `hot-pot`, `laughing`) and
**Framing** effects (`punch-in`, `reset-framing`), **Motion** effects (`ken-burns-in`, `ken-burns-out`,
`zoom-punch-in`), **Speed** effects (`speed-ramp`, `slow-motion`), **Transitions** presets (`soft-dissolve`, `quick-whip`,
`zoom-punch`) and **Looks** (`original`, `vivid`, `muted-film`, `black-white`, `bright-airy`, `moody`). Their IDs are
reserved. The Text, Stickers, Effects, Transitions and Filters panels show them first, then the items saved in the
project or on this Mac. The Filters panel also lists the style kits and the project's own looks (`style save`,
`looks save`) among its items; clicking a kit runs `style apply`.

- `bashcut library list [--panel text] [--kind sticker] [--tag food] [--scope user] [--created-by agent] [--pack X]
  [--query word]` lists items with their usage; `library get <id>` adds the earlier versions and the file path.
- `bashcut library add --kind sticker --name Fire --params '{"emoji":"🔥"}' [--tags food,hot] [--pack Food]
  [--file f.png] [--scope project|user]` saves a new item (the ID comes from the name unless `--id` is given).
- `bashcut library update <id> [--name] [--tags] [--params] [--file] …` saves a new version; the old one stays in
  `history`. Built-in and plugin items are read-only: `--as <new-id> [--into user]` saves an improved copy with
  `basedOn` pointing at the original. Nothing is overwritten silently.
- `bashcut library remove <id>` removes a project or user item and its files. Placed copies live in the project
  folder and are never touched; files of the item that the open project's media still points at directly (placed
  before #64 from a project library) are kept and listed in the result's `kept`.
- `bashcut library place <id> [--at-frame] [--duration] [--track] [--text] --base-rev N` adds a text preset or emoji
  sticker as a text item, an image, animated or video sticker on the Overlay layer (see Stickers below), a look as an
  adjustment, or an audio item as a clip (see Audio below). `library apply <id> [--item] --base-rev N` sets a text preset,
  an effect preset's recipe or a look's grade on an existing item. Both count a use (in `usage.json` next to
  `library.json`; the item list is not rewritten).
- `bashcut library save-selection --kind text-preset|effect-preset|transition-preset|look|audio|sticker --name X [--item]
  [--media] [--scope] [--tags] [--pack]` saves what is selected: a text item's style and text, a clip's `transform` and
  `keyframes` as an effect recipe (see below), the transition at the selected clip (kind, duration, easing and the sound a preset placed at that cut),
  a grade as a look: the whole filter stack, with the project LUT it uses copied in as the look's file, or an audio
  clip (or, with `--media`, any project audio media) as an audio item (see Audio below), or an overlay item as a
  sticker (see Stickers below).
- `bashcut library move <id> --to project|user` moves a saved item with its versions, files and use count.
- Transition presets (#77) are `params` `{kind, duration, easing, sfx}`: `sfx` names an audio library item, or the
  preset carries its own sound as its `file` (`sfx` wins when both are set). `library apply` on one sets the transition
  at the cut beside the video clip (the duration at most the shorter clip) and places the sound from the cut on an
  SFX layer (added when missing), as one undo step. A sound from outside the project is copied into its `sfx/`
  folder; applying a preset with a sound again at that cut replaces the sound the last one placed (items marked
  `transitionSFX`). Edit a saved preset with `library update <id> --params '{...}'` (the Transitions panel's
  Edit…).
- Effect presets are recipes (#76): `params` `{steps: [...], parameters: {name: {default, min, max, label?}}}`.
  Steps run in order on the clip, each on the clip as the steps before left it, and all of them are one undo step:

  | `op` | Fields | Same as |
  |---|---|---|
  | `motion` | `preset` (`zoom-in`, `pan-left`, …), or `focus` `[x, y, w, h]` as fractions 0–1 of the picture with `focusTo`, `ease` | `clip motion --preset`, `--focus` |
  | `keyframes` | `keys` `{zoom: [{t, value, ease?}, {frame, value}]}`; replaces those properties' keys, keeps the others | `clip motion --keyframes` |
  | `speed` | `speed`, `keepDuration` | `clip speed` |
  | `speedCurve` | `preset` or `points` `[[t, speed], …]`, `keepDuration` | `clip speed-curve` |
  | `reverse` | — (a reversed clip stays reversed) | `clip reverse` |
  | `freeze` | `t` or `frame`: the frame held over the clip (the first by default) | Freeze frame |
  | `patch` | `patch`: item properties (`transform`, `opacity`, …) | the older `params.patch` |
  | `sfx` | `sfx` (audio item ID; the preset's own `file` without it), `t` or `frame`, `volumeDb` | a sound on the SFX layer |
  | `text` | `text`, `textPreset`, `t` or `frame`, `duration` (frames; to the clip's end by default) | `library place` of a text preset |

  `t` runs from 0 (first frame) to 1 (last frame), so positions scale with the clip; `frame` counts integer frames
  from the start (negative from the end). A value written `"$name"` takes the parameter (frames must stay whole).
  `library apply <id> --set zoom=1.5,frames=12` (or `--set '{"zoom":1.5}'`) overrides parameters within their
  range, and `--from F --to T` (timeline frames inside the clip) splits that part off in the same undo step and
  applies the recipe only there; the result's `item` is the clip that got the effect. Sounds and text are marked
  `effectSFX` / `effectText` with that clip's ID and replaced when the preset is applied to it again; a sound from
  outside the project is copied into `sfx/`. A `reverse` step whose reversed copy is not in `reversed/` yet returns
  `{job}` instead: the job renders the copy, then commits the whole recipe. A preset with only `params.patch` (made
  before recipes) is one `patch` step and works as before. `save-selection --kind effect-preset` writes a recipe of
  the clip's reverse, speed or speed ramp, `transform`, keyframes (as `t`) and the sound effect at its start (one a
  preset placed, or one on an SFX layer starting with the clip), and a 320-pixel still of the clip's middle as the
  preview. The Effects panel's **Apply with…** (the slider button, or the context menu) shows the parameters and an
  optional frame range; it is the `effect-apply` dialog (`ui respond apply|cancel`).
- Looks are filter stacks (#79): `params` `{color: {exposure, contrast, saturation, lutStrength}, lutName}` plus an
  optional .cube LUT as the item's `file` (`library add --kind look --name X --file look.cube`; without `--params`
  the look is just that LUT). `library place` adds one as an adjustment and `library apply` replaces a clip's or
  adjustment's grade with it; when it has a LUT, the .cube is copied into the project's `luts/` folder
  (`luts/library-<hash>.cube`, its project LUT keeps `sha256` and `libraryItem`) and added in the same undo step, and
  using a look with the same file again reuses that LUT. Looks without a file apply their grade exactly as before.
  Edit one with `library update <id> --params '{...}'` (the Filters panel's Edit…).
- Audio items (#78) are music, sound effects and ambience kept outside any one project (user scope) or with it
  (project scope). The item's `file` is the sound; `params` `{role, seconds, bpm, loopable, lufs, truePeak}` are all
  optional: `role` is `music`, `sfx` or `ambience`, `seconds` the length, `bpm` the tempo, `lufs` the integrated
  loudness and `truePeak` the true peak in dBTP, and `loopable` says the end joins the start. Mood, genre and use are
  tags (`--tags calm,lofi,intro`). `library add --kind audio --name X --file song.wav [--params '{"loopable":true}']`
  measures `seconds` and, without a role, picks `sfx` for a file under 10 seconds and `music` otherwise.
  - `library analyze <id> [--provider P]` runs as a job (`jobs status --job J` for its result): it measures the length,
    the loudness and true peak with an `audio.loudness` provider (as `audio measure`) and, unless the item is a sound
    effect, the tempo with an `audio.beats` provider (as `beats detect`), on the library file itself, and saves them
    as a new version. A missing or failing provider leaves that value as it was and says why in the result's
    `notes`. An agent analyzing a user-scope item waits for approval like any user-library change. Read-only items
    (plugin, built-in) need a copy first (`library update <id> --as <new-id>`).
  - `library place <id> [--at-frame F] [--duration N] [--track T]` copies the file into the project's `music/` (music,
    ambience) or `sfx/` (sound effects) folder as `library-<hash>.<ext>` (the same content is copied once and reused,
    whichever item or folder asked), imports it as media (reusing media for the same file) and places it on the Music
    or SFX layer, adding that layer when the project has none (a new Music layer ducks under speech like a new
    project's), or on a free layer beside it, as one undo step. `--duration` trims the sound. BashCut has no clip
    looping, so a longer duration on a `loopable` sound places copies back to back (the last one trimmed; the result
    lists them in `items` with `looped: true`); a sound that does not loop plays once and the result has a `note`.
  - `library save-selection --kind audio --name X [--item clip | --media id]` saves a project sound: the clip's (or
    media's) whole file is copied in, with its `seconds` and a role from its layer (Music → `music`, SFX → `sfx`).
  - `library preview <id>` plays the item's sound in BashCut (the Audio panel's play button); `library preview
    --stop` stops it.
  - The Audio panel lists the project's audio (context menu **Save to Library…**) and the library's audio items with
    a play/stop button, badges for role, length, BPM, LUFS and loop, and **Place**; their context menu adds **Place at
    Playhead** and **Analyze Length, Loudness & Tempo**, and Edit… sets the role and the loop flag. Audio files dropped
    on the panel or chosen with Add… become items.
- Stickers (#64) have a kind, `params.stickerKind`: `emoji` (`params.emoji`, drawn as text with `params.textPreset`),
  `image` (a PNG, JPEG, HEIC, WebP… file; transparency is kept), `animated` (a GIF, APNG or animated WebP) or
  `video-alpha` (a .mov or .mp4 with an alpha channel: HEVC with alpha or ProRes 4444 with alpha). Lottie files are
  refused: export the animation as a GIF, an animated WebP or a movie with alpha. `library add --kind sticker --name
  Arrow --file arrow.png [--pack Arrows] [--tags arrow] [--source URL --license CC0] [--scope project]` reads the kind,
  `width`, `height` and `frames` from the file (an image with more than one frame is `animated`; a movie without
  alpha is refused, since it would cover the picture below). Optional placing defaults in `params`: `size` (the
  sticker's width as 0.01–1 of the frame width; 0.3 without one), `position` (`center`, `top`, `bottom`, `left`,
  `right`, `top-left`, `top-right`, `bottom-left`, `bottom-right`, which keep the sticker inside the safe area the
  viewer draws, or `{x, y}`, its centre as 0–1 of the frame from the top left), `animation` (a `clip motion` preset
  such as `pop-in` or `slide-up`; zoom keys scale the sticker's own size and pan/tilt keys move it from its place)
  and `seconds` (how long it stays; 3 for an image without one).
  - `library place <id> [--at-frame F] [--duration N] [--position top-right|x,y] [--size 0.25] [--track T]` copies an
    image, animated or video sticker's file into the project's `stickers/` folder as `library-<hash>.<ext>` (the same
    content is copied once), imports it as media (reusing media for the same file) and places it on the Overlay layer,
    added in front of the other video layers when the project has none, or on a free overlay layer beside it, fitted
    (`fill: false`) and framed with `transform` zoom, pan and tilt, all as one undo step. Options win over the
    sticker's defaults. The engine draws an animated sticker's first frame for now; the result's `note` says so. A
    sticker movie plays once (a longer `--duration` is cut to its length and the `note` says so) and is marked
    `alpha: true` in the project, so BashCut previews it from the original instead of a proxy without alpha. Emoji
    stickers place as text exactly as before; `--position` and `--size` do not apply to them.
  - The project copy belongs to the project: `library remove` or `library update` of the sticker never changes it.
  - `library save-selection --kind sticker --name X [--item id]` saves the selected overlay: an image (or a movie with
    `alpha`) with its file, `size`, `position` (`{x, y}`) and `seconds` from the item's framing and length, or an emoji
    text item with its text and text preset. A filling item keeps only its length.
  - The Stickers panel shows emoji, image and movie thumbnails (badges for animated and video stickers), places one
    at the playhead on click (context menu **Place at Playhead**), takes dropped or chosen images and alpha movies
    (Add…), and its item sheet (Duplicate & Edit…, Edit…, Save selection as sticker) sets size, position and
    animation.
- Plugin items (#81) come from the packs plugins ship (`contributes.library`, plugin API 6; see the
  [plugin guide](plugins.md#library-packs)). They list in the `plugin` scope with `createdBy` `{by: plugin, plugin,
  pluginName, pluginVersion}` and paths under the plugin folder (`library get` gives `fileURL`), are read-only (`library
  update <id> --as <new-id>` saves an editable copy with the files) and go away when the plugin is removed, turned off
  or changed and not trusted again. `library place` and `library apply` copy any file they use into the project first
  (`music/`, `sfx/`, `stickers/`, `luts/`), even for a plugin installed in the project's `.bashcut/plugins`, so the
  timeline never points into a plugin. An item whose ID is built in or came from an earlier plugin is left out and
  `plugins list` reports it under `diagnostics`.
- `bashcut library search "<text>" --kind audio [--provider <plugin or provider id>] [--limit 12] [--page 1]` and
  `bashcut library generate "<prompt>" --kind sticker [--provider P] [--limit 4] [--params '{"seconds":30}']` ask a plugin
  that provides `library.search` or `library.generate` (Freesound or Giphy search, AI music or stickers…) for
  candidates. Each runs as a job; `jobs status --job J` gives `{kind, provider: {plugin, provider, version,
  capability}, directory, candidates: [{index, id, name, kind, tags, params, source, license, fileURL, previewURL,
  …}]}`, with the files in a request folder under `~/Library/Caches/BashCut/LibraryCandidates` (removed after a day).
  Nothing is saved until `library add --from-result <job>:<index> [--scope user] [--name] [--tags] [--id]` copies one
  in with its files, source, license and the provider as `provenance` (`createdBy.plugin` names the plugin), or the
  search itself is given `--save <index> [--scope project|user]` (a failed save is reported as `saveError`, and the
  candidates stay). Agents saving to the user scope wait for approval as with `library add`. A named `--provider`
  must be available and serve the kind; without one, the highest-priority provider that serves it is used. Network
  use is the plugin's own; BashCut only starts the plugin.
- `bashcut library stats [--panel]` reports usage, the saved items nobody used, and duplicates (same kind, params
  and file), to prune or merge. Saved items compare the `fileSHA256` stored when their file was copied in.
- `bashcut library export-pack --pack Food --output ~/Food` writes a pack folder (`pack.json` and `files/`);
  `library import-pack <folder|zip> [--scope user] [--replace]` adds one. IDs already there are refused unless
  `--replace` saves them as new versions.

Agents' `add`, `save-selection`, `update`, `analyze`, `remove` and `import-pack` in the `user` scope, and every `move`, wait for
the user's approval, like exports; the project scope follows the normal edit rules.

Each panel (Audio, Text, Stickers, Effects, Transitions, Filters) shows its items with search, pack, tag and scope
filters, badges for agent-made and project or Mac items, plugin packs grouped under the plugin's name, **Add…** (and
drops) for files and packs, **Save selection as…**, **Search…** and **Generate…** when a plugin provides them for the
panel's kinds (the sheet runs `library search`/`library generate`, previews each candidate and saves it with **Save**;
`ui open library-search|library-generate` opens it for the open panel and `ui respond run|save-<index>|close` answers
it), and a context menu: Duplicate & Edit (`update --as`), Rename (`update --name`), Move (`move`), Show Source &
License (`get`), Show in Finder and Remove (`remove`). `ui view --library-query X --library-pack P --library-tag T
--library-scope user` sets the open panel's search and filters (`libraryFilter` in the view state); the item sheet
is the `library-item` dialog (`ui respond save|cancel`).

## Media proxies

Heavy footage (HEVC, a long side above 1920 px, or above 20 Mbit/s) gets a preview proxy when it is imported:
an H.264 copy at most 960 px on the long side, with a keyframe every 10 frames and the original frame times,
written to `.bashcut/cache/proxies/<media id>.mov`. The viewer reads proxies; exports always read the originals.

Proxies are made one at a time as `media.proxy` jobs, and the preview switches to each one as it lands.

- `bashcut media proxy [MEDIA_ID] [--force]` queues them by hand and returns a status per media: `queued`
  (with its job ID), `exists`, `not-needed` or `skipped`. The Media panel's **Create Preview Proxy** menu does
  the same with `--force`.
- `media list` reports each media's `proxy` state: `none`, `queued` or `ready`.

## Dialogs and UI actions

Anything you can click or press in the editor is also a command. Buttons, menu items and shortcuts are
`UIAction` cases (`BashCut/Core/Automation/UIAction.swift`) with an ID, a title and shortcuts; the views bind
to them and `ui action` runs the same code.

```sh
bashcut ui actions                 # every action, its shortcuts and whether it is enabled now
bashcut ui action timeline.split   # by ID
bashcut ui action cmd+b            # or by shortcut: cmd+=, space, i, shift+delete
bashcut ui view --zoom 60 --snap on --inspector color --reveal 300
bashcut ui view --zoom 480 --zoom-anchor 1200   # zoom in on frame 1200, keeping it where it is on screen
bashcut ui action timeline.zoom-fit            # or shift+z: show the whole timeline
bashcut ui action clip.freeze                  # the clip context menu: clip.freeze, clip.change-framing, clip.unlink-audio
bashcut ui action shift+right                  # timeline arrows: left/right step a frame, shift+left/right a second
```

Shortcuts are written as `cmd+shift+z`; modifiers can also be spelled `command`, `option`/`alt`/`opt` and
`control`/`ctrl`. When one shortcut means different things in different places (`space` plays the source viewer
while it is shown), `ui action` picks the one that is available.

Every alert, file panel, sheet and popover is visible to `ui dialog`:

```sh
bashcut ui action project.open     # returns at once with {"started": true}
bashcut ui dialog                  # the open-panel, with its option IDs
bashcut ui respond --path /path/to/project
```

- `ui action` refuses while a dialog is open; answer it first.
- Actions that open an alert or panel (`project.new`, `project.open`, `project.import-media`) return at once
  so you can answer the dialog.
- `ui respond --dialog ID` answers only if that dialog is topmost.
- `ui open` refuses while another dialog is open, and some sheets only open when they apply (for example
  `export` needs a nonempty timeline).
- The export approval and plugin-install sheets offer agents only `deny` or `cancel`. Approving stays with
  the user.

## Jobs

`captions generate`, `beats detect` and `voice speak` call the same `CapabilityService` as the Text, Audio and
Voice panels, so provider resolution, health checks, output confinement and validation are identical.

```sh
bashcut captions generate --media MEDIA_ID --replace
bashcut beats detect --media AUDIO_MEDIA_ID
bashcut voice speak 'Xin chào các bạn' --takes 3 --at-frame 120
bashcut jobs status JOB_ID
bashcut jobs cancel JOB_ID
```

- Each returns `{"job": ID, "state": "running"}` at once. Poll `jobs status ID` until it reports `completed`,
  `failed` or `cancelled`. A completed job's result includes the new `rev`, plus `bpm`/`beats`, or the inserted
  voice `item` with its score and all take scores.
- The result is one undoable edit attributed to the agent, with change markers and the Undo toast.
- `voice speak --keep-takes` inserts nothing and keeps every take in `voiceover/generated`, so you can choose
  one and place it with `media import`.
- `--provider ID` overrides the project preference for one request.
- A capability that is already running (from the UI or another job) is rejected with a retry error.
- Opening another project cancels and clears all jobs.
- Installing plugins, running their dependency recipes, trusting a plugin or turning one on is never available
  through automation. See [Writing plugins](plugins.md).

Jobs move through `queued`, `running`, `completed`, `failed` and `cancelled`. Exports and proxy builds use the
same job center.

## Exports and approval

```sh
bashcut export start --preset quick-draft --name draft-v1 --include-srt --normalize-audio
bashcut export otio --name timeline-v1
bashcut export status
```

`export start` and `export otio` need a live session token. They return at once with an approval request ID,
and the app shows a sheet with the author, preset, output path, caption behavior and normalization choice.
Denying writes nothing. Approving starts the same background pipeline as the Export sheet. Only one privileged
request can wait for approval at a time.

**Settings → Run agent exports without confirmation** is off by default, and no command can change it. When
you turn it on, requests run at once, return `approval: "approved"` and are audited as
`<method>.auto-approved`.

- **Output.** Files go to the project's `render/` folder unless you pass `--output-dir`.
- **Queue.** Each approved export (and each export started in the UI) becomes an `export.start` job. Exports
  render one at a time in request order, from the project as it was when requested. `jobs cancel` stops a
  queued or running export.
- **Status.** `export status` lists the queue with job IDs. While an export runs, its top-level fields (`job`,
  `step`, `progress`, `preset`, `path`, `includedSRT`) describe that export and the previous receipt moves to
  `lastExport`. Otherwise it returns the most recent receipt: path, preset, duration, bytes, cuts, captions and
  companion-SRT state. Poll it after an approved request.
- **Captions.** An export asked to include SubRip writes no `.srt` when the timeline has no captions.
- **Loudness.** `--normalize-audio` needs an installed, healthy `audio.loudness` plugin and runs the two-pass
  target and true-peak workflow. A normalized receipt also includes `lufs`, `truePeakDbTP`,
  `normalizationGainDb` and whether the final measurement was verified; other exports return `lufs: null`.
- **OTIO.** `export otio` writes OpenTimelineIO JSON. It keeps integer-frame timing, source ranges and rates,
  layered overlaps, text generators, section markers, speed effects and BashCut metadata.

## Model APIs

The dock no longer has a model-API tab (removed 2026-10-04): it generated a script or one timeline proposal per
request, without tools, the agent kit or a look at the result, which is not enough to finish a video. To use a
model with API billing, use a Codex tab (it passes `OPENAI_API_KEY` through) or log the Claude CLI in with a Console
account (Claude tabs never receive `ANTHROPIC_API_KEY`); both get the agent kit and the full command set. See the
[Claude CLI reference](https://code.claude.com/docs/en/cli-reference) and the
[Codex CLI reference](https://developers.openai.com/codex/cli/reference).

## Debug log

The app, the `bashcut` CLI and `bashcut-mcp` append one line per event to `~/Library/Logs/BashCut/debug.log`
(rotated to `debug.1.log` at 5 MB) and mirror it to the unified log under subsystem `app.bashcut`. It records:

- app launch, with the executable path and build time;
- project opens, with the layer layout and any layer-rule repair;
- every committed or rejected edit with its operation name, and layer placement and spill decisions;
- media import details (`kind`, `hasAudio`, frames), proxy queueing, timeline gestures and library panel
  switches;
- every automation request with its author, duration and success/failure code, and auto-approved exports.

Sensitive command parameters are marked in `CommandParameter` and replaced with `[redacted]`; unknown input
fields are redacted too. Chat text, option values, arbitrary plugin parameters and operation payloads are not
persisted. RPC results and error messages are omitted because they may echo secrets. The CLI logs the parsed
command name, never raw argv. Log files are created with `0600`, existing active files are restricted on write,
and unified-log messages use private visibility. Open uses `O_NOFOLLOW` and append mode. Handles are retained;
a stable `.lock` file protects append and rotation across processes, and writers reopen when the pathname's
inode changes. Release builds disable logging by default; use `BASHCUT_DEBUG_LOG=1` to enable it explicitly,
or `BASHCUT_DEBUG_LOG=0` to disable it in Debug. `BASHCUT_DEBUG_LOG_PATH` overrides the file destination.

```sh
tail -f ~/Library/Logs/BashCut/debug.log
```

Set `BASHCUT_DEBUG_LOG=0` to turn it off. Test runners never write to it.

### Error responses

CLI failures write `{"error":{"code":-32002,"message":"…","data":{"expected":1,"actual":2}}}` to stderr
and leave stdout empty. `data` is optional. MCP returns the same object in `structuredContent` and JSON text,
with `isError: true`. Error messages are intended for the requesting client and are omitted from debug logs.

| Condition | RPC code | CLI exit status |
|---|---:|---:|
| Stale revision / project read required | -32002 | 75 |
| Editor busy | -32003 | 69 |
| App/socket unavailable | -32000 | 69 |
| Missing or revoked token | -32001 | 77 |
| Invalid request, command or arguments | -32600 / -32601 / -32602 | 64 |
| Malformed response | -32700 | 65 |
| Internal / other failure | -32603 / other | 70 |

Stale revision errors include `data.expected` and `data.actual`. Refresh the project before constructing a new
edit; do not blindly replay after a timeout because a timed-out mutation may already have completed.
