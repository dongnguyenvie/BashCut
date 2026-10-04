# 12 — Terminal agents: agent CLIs as plugins

Status: implemented (2026-10-04). Owner: Nolan.

A **terminal agent** is a plugin with the `agent.terminal` capability. It adds an agent CLI (Gemini CLI, Qwen
Code, opencode, aider…) to the agent dock as a terminal tab, next to the built-in Claude, Codex and Shell tabs.
The CLI runs in a real terminal with its own interface. It reaches BashCut through the bundled MCP server
`bashcut-mcp` with its own session token, exactly like Claude Code and Codex.

The app side is generic: nothing in `bash-cut` names a particular CLI. A plugin brings the CLI's identity and the
one thing only it knows: how to start that CLI with an MCP server, a system prompt, skills and a session to resume.

## 1. Goals and non-goals

Goals:
- Anyone can add an agent CLI to the dock without changing BashCut.
- The CLI gets what the built-in tabs get: the `bashcut` MCP server with a per-tab token (author `agent`, revoked on
  close), BashCut's instructions and project context, and the agent kit's skills.
- Resume the last conversation for a project when the CLI can.
- Everything works from the CLI/MCP too (`agent terminals`, `agent open`).

Non-goals (first version): several terminal tabs per plugin from one manifest, editing the plugin's launch
from Settings, a terminal agent as the default agent.

## 2. Who owns what

| Part | Owner | Why |
|---|---|---|
| Terminal, PTY, tabs, handoff, quick prompts | App | Same for every CLI |
| Session token, socket, `bashcut-mcp` path | App | The plugin process never sees the token (plugin rule since API 1). Only the terminal does, through its environment |
| Environment filtering | App | The CLI inherits only `AgentEnvironment.common`, the manifest's `terminal.environment` patterns and what the launch adds |
| Instructions and project context (the prompt) | App | One source for every agent |
| **Agent kit (skills)** | **App** | See below |
| How to pass MCP, prompt and skills to this CLI | Plugin | Every CLI has its own flags and config files |
| Finding the CLI's last session for a project | Plugin | Every CLI stores sessions differently |
| Installing the CLI | Plugin | A normal plugin dependency with a probe and an install recipe |

### Skills stay in BashCut

The agent kit (`bashcut-agent-kit`) is bundled with the app, updated by `agent kit-update`, can be pointed at a
checkout in Settings › Agents and can be switched off. One copy serves every agent, so a skill fix reaches Claude,
Codex, chat agents and terminal agents at once. A plugin therefore never ships skills. The app sends the kit with
each launch, and the plugin chooses how its CLI reads it:

- **The CLI reads skill folders** (`<name>/SKILL.md`, as Claude Code, Codex and Gemini CLI do): return
  `skillsFolder` with a folder inside `agentFolder`. The app links each kit skill there and removes links to skills
  that are gone. The plugin points its CLI at that folder (for example, it runs the CLI in `agentFolder` where the
  CLI looks for `.gemini/skills`).
- **The CLI has no skills:** use `kit.root` and `kit.skills` (name and description) to tell the model in the prompt
  where the skills are, so it reads them with its file tools.

With Settings › Agents › *Load the agent kit* off, `kit` is null and the app removes the linked skills.

## 3. Plugin API 5 (additive)

### 3.1 Manifest

```json
{
  "schema": "bashcut.plugin/1",
  "id": "dev.example.gemini",
  "name": {"en": "Gemini"},
  "version": "0.1.0",
  "apiVersion": 5,
  "entrypoint": "bin/provider",
  "capabilities": ["agent.terminal"],
  "providers": [{"id": "dev.example.gemini.terminal", "capability": "agent.terminal", "name": "Gemini"}],
  "terminal": {"icon": "sparkles", "environment": ["GEMINI_*", "GOOGLE_*"]},
  "dependencies": [{
    "id": "gemini", "name": "Gemini CLI", "kind": "executable",
    "probe": {"executable": "bin/check-gemini"},
    "install": {"summary": "npm install -g @google/gemini-cli", "command": {"executable": "bin/install-gemini"}}
  }]
}
```

- `agent.terminal` needs `apiVersion` 5 and a `terminal` object; `terminal` needs the capability. Either
  transport works (`oneshot` is enough: the app calls the plugin once per launch).
- `terminal.icon`: an SF Symbol name for the tab (default `terminal`).
- `terminal.environment`: up to 32 variable names the CLI may inherit from the app's environment. A trailing `*`
  matches a prefix. `BASHCUT_*`, `PATH` and bare `*` are refused. Declared in the manifest, so the user sees them
  before trusting the plugin.
- The tab is titled with the plugin's name.

### 3.2 Method `agent.terminal`

`params.op` selects the operation. Every request carries the plugin's `options`.

**`launch`** (required): build the command line for one new tab.

| Param | Value |
|---|---|
| `workspace` | The dock's workspace folder (Settings › Workspace, else the project's folder) |
| `agentFolder` | A folder BashCut owns for this plugin's tabs: `~/Library/Application Support/BashCut/agent-workspaces/<plugin id>`, created before the call. The plugin may write CLI config here |
| `project` | The open project's path, or null |
| `prompt` | BashCut's instructions and the project context, for the CLI's system prompt |
| `mcp` | `{"name": "bashcut", "command": "<path of bashcut-mcp>", "arguments": [], "environment": ["BASHCUT_SOCKET", "BASHCUT_SESSION_TOKEN"]}`. The named variables are set in the terminal; the CLI must pass them to the server |
| `kit` | `{"root", "skillsFolder", "version", "skills": [{"name", "description"}]}` or null |
| `resume` | The session ID to continue, or "" for a new conversation |
| `canEdit` | false when Settings turns off agent timeline edits (the token cannot edit) |

Result:

| Field | Value |
|---|---|
| `executable` | Required. A name looked up on the terminal's PATH (`gemini`), an absolute path, or a path inside the plugin folder (`bin/run`) |
| `arguments` | Array of strings (argv, never a shell string) |
| `directory` | Absolute folder to start in; default `workspace` |
| `environment` | Extra variables, `{"NAME": "value"}`, at most 64. `PATH`, `HOME`, `TERM`, `COLORTERM` and `BASHCUT_*` are refused |
| `skillsFolder` | A folder inside `agentFolder` to link the kit's skills into (see §2) |

**`session`** (optional): the newest session of this CLI that belongs to the project, so the next launch can
resume it. Params: `workspace`, `agentFolder`, `project`, `notBefore` (seconds since 1970, or null). Result `{"id": "<session id>"}` or `{"id": null}`. The app asks after each new launch (a few times in the
first seconds) and when a project opens. An error or an unknown op means the plugin does not resume.

## 4. App side

- `PluginTerminalProvider` conforms to `AgentProvider`: ID = plugin ID (it always contains a dot, so it never
  clashes with `claude`, `codex` or `shell`), author `agent`, environment allowlist from the manifest. It holds the
  command line the plugin returned, so `AgentLaunch.make` builds the launch as for Claude and Codex (PATH, session
  variables, executable lookup).
- `PluginTerminalLaunch` validates the result (§3.2) before anything starts.
- **Dock:** the + menu lists "<name> terminal" for each ready terminal plugin; the empty state has Start / Continue /
  New conversation for them like Claude and Codex; Handoff works too. The tab icon comes from the manifest.
- **Bookmarks:** the session ID per project is saved with the others in `agent-sessions.json`, keyed by plugin ID.
- **CLI/MCP:**
  - `agent terminals` lists the terminals the dock can open (built-in and plugin), whether each is ready, whether it
    can continue a conversation, and the open tabs;
  - `agent open <id> [--new]` opens one (`claude`, `codex`, `shell` or a plugin ID); `--new` starts without the saved
    conversation. It returns after the launch, so a plugin error is the command's error.

## 5. Security

- A terminal agent is a CLI the user chose to install and trust, like Claude Code: it can run anything the user can.
  Its BashCut access is a per-tab token with author `agent`, revoked when the tab closes, and unable to edit when
  agent timeline edits are off.
- The plugin process gets no token or socket. The terminal gets them in its environment, because its MCP server
  needs them.
- The launch is argv only, the environment is allowlisted, and skills are links in a folder BashCut owns.

## 6. Writing a terminal plugin (outline for a Gemini CLI plugin)

1. Manifest as in §3.1, with a dependency that finds or installs `gemini`.
2. `launch`: write `<agentFolder>/.gemini/settings.json` with
   `{"mcpServers": {"bashcut": {"command": mcp.command, "args": [], "env": {"BASHCUT_SOCKET": "$BASHCUT_SOCKET", "BASHCUT_SESSION_TOKEN": "$BASHCUT_SESSION_TOKEN"}, "trust": false}}}`,
   write `prompt` to `<agentFolder>/GEMINI.md`, return
   `{"executable": "gemini", "arguments": resume ? ["--resume", resume] : [], "directory": agentFolder, "skillsFolder": agentFolder + "/.gemini/skills"}`.
3. `session`: look in Gemini's session store for the newest session started in `agentFolder`.
4. Test with `plugins doctor <id>`, then `agent open <id>` and `agent terminals`.
