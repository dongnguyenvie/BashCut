# 11 — Chat agents: in-app editing agents as plugins

Status: implemented (2026-10-04). Owner: Nolan.

A **chat agent** is a plugin with the `agent.chat` capability. Each ready one gets its own tab in the agent dock,
titled with the plugin's name. Unlike the removed model-API tab, a chat agent runs a real tool loop: it reads the
project, edits through the same commands as Claude Code and Codex, looks at the result with `ui frame`, and
follows the agent kit's skills.

The app side is generic. Nothing in `bash-cut` names a particular agent, so anyone can contribute another chat
agent as a plugin. The first one is **Director** (`bashcut.director` in `bashcut-plugins`). Its model runtime is
the MIT-licensed [pi](https://github.com/earendil-works/pi) libraries (`@earendil-works/pi-agent-core` and
`pi-ai`); pi is an implementation detail of that plugin.

## 1. Goals and non-goals

Goals:
- Chat with a model (Anthropic, OpenAI, Google, OpenRouter and others pi-ai supports) using an API key, with no CLI
  login.
- The model drives BashCut only through catalogued commands (`CommandCatalog`), with the same validation, edit
  permission, project-switch gate, privileged approval and audit as other agents.
- The agent kit's skills are available to the model.
- Everything works from the CLI/MCP as well (`chat` commands), like every other feature.

Non-goals (first version): subscription OAuth logins, running shell commands or editing files (chat agents have no
bash/write tools), several parallel conversations per project, image generation.

## 2. Architecture

```
┌──────── BashCut (Swift) ────────┐        session transport (NDJSON)        ┌──── e.g. bashcut.director ──────┐
│ Agent dock › chat-agent tab     │  request agent.chat {op:"turn", …} ─────▶ │ agent loop (Director: pi)        │
│ ChatAgentModel (per plugin)     │  ◀──── event {text delta, tool start…}   │ models + API key option          │
│   └ host channel                │  ◀──── call {method:"timeline.get", …}   │ tools = BashCut command catalog  │
│       └ CommandRegistry.handle  │  callResult {result | error} ──────────▶ │   + read_skill (agent kit)       │
│         (token, author .agent)  │  ◀──── {id, result:{stopReason}}         │ conversation saved per project   │
└─────────────────────────────────┘                                           └──────────────────────────────────┘
```

The plugin never receives the automation socket or a token (plugin rule since API 1). When the model calls a
tool, the plugin sends a `call` line inside the running request, and the app runs it through
`CommandRegistry.handle` with a token issued for that conversation. Edits therefore show up in History
and Show Changes like any agent's.

## 3. Plugin API 4 (additive)

### 3.1 Host channel in the session transport

A request may carry a **host channel**. Only requests that the app starts with a channel accept the two new
plugin → app lines. Today that means `agent.chat`.

| Direction | Message |
|---|---|
| Plugin → app | `{"type":"event","id":<request id>,"event":{…}}`: a UI event for the caller; it also counts as activity, like `progress` |
| Plugin → app | `{"type":"call","id":<request id>,"callId":"c1","method":"timeline.get","params":{…}}` |
| App → plugin | `{"type":"callResult","callId":"c1","result":…}` or `{"type":"callResult","callId":"c1","error":{"code":-32602,"message":"…"}}` |

- `call` lines are answered in any order. While a call is outstanding, the request's silence timeout is paused.
  A long export that takes minutes does not time the turn out.
- A `call` on a request without a host channel, or after the request finished, gets an error `callResult`.
- Calls are limited to 1 MiB of params, like requests. Results larger than 1 MiB are cut to an error that says so.
- Cancelling the request (`cancel`) also cancels the app-side wait for its calls. Commands that have started
  still finish.

### 3.2 `secret` option type

`"type": "secret"` (API 4): a string the user enters in Settings › Plugins, such as an API key.
- It is stored in the Keychain (service `app.bashcut.plugin-secret`, account `<plugin id>/<option id>`), never in
  `plugin-trust.json` or the project. Its scope must be `user`.
- It is sent to the plugin in the request's `options` like other values.
- It is never returned by `plugins options` and never written to the debug log. Listings show `"set": true|false`.
- Only the user sets it, in Settings. `plugins option` refuses secrets with "Set secrets in Settings", so no agent
  can read or replace a key.

### 3.3 Capability `agent.chat`

Requires `"transport": "session"` and API 4. Method `agent.chat`; `params.op` selects the operation.

| op | Params | Result | Notes |
|---|---|---|---|
| `turn` | `conversation` (string), `text` (begins with the `[Scope]` block when clips are attached), `images` (paths, optional), `scope` (array of attached items `{id, linked?, track, layer, name, start, end}`, may be empty), `context` (string), `instructions` (string), `tools` (array of `{name, method, description, inputSchema}`), `kit` (`{root, skillsFolder, version, skills:[{name, description}]}` or null), `options` | `{"stopReason":"end"\|"aborted"\|"error","error"?}` | Streams `event`s and makes `call`s while it runs |
| `reset` | `conversation` | `{}` | Forgets the conversation |
| `status` | `options` | `{"ready":bool,"provider","model","detail"}` | Is a key set, and is the model known |
| `commands` | `options` | `{"commands":[{"name","args"?,"summary","choices"?}]}` | The plugin's own slash commands. `choices` are argument suggestions, such as thinking levels or model IDs |
| `command` | `conversation`, `name`, `args` (string), `options` | `{"text"?,"options"?}` | Runs one of those commands. `text` is shown as a notice. `options` is a patch of the plugin's non-secret options; the app stores it, as if the user had changed Settings |

### 3.4 Slash commands

Typing `/` in a chat-agent tab opens a menu: arrows move, Tab or Enter completes, and Escape closes it. A message
that starts with a known command runs the command instead of going to the model.

- **App commands**, the same for every chat agent:

  | Command | What it does |
  |---|---|
  | `/new` (alias `/clear`) | Start a new conversation |
  | `/stop` | Stop the running turn |
  | `/settings` | Open Settings › Plugins |
  | `/copy` | Copy the last reply |
  | `/export [path]` | Save the conversation as Markdown |
  | `/skill:<name> [task]` | Ask the agent to follow that agent-kit skill |

- **Plugin commands:** those that op `commands` lists, for example Director's `/compact`, `/model`, `/thinking` and
  `/session`. App commands win when a name clashes.
- **Input:** Enter sends, and Shift+Enter or Option+Enter inserts a new line. While an input method is composing
  (Vietnamese Telex, for example), Enter only commits the text.
- **CLI:** `chat commands [--plugin]` lists the commands. `chat command "<line>" [--plugin]` runs one as typed,
  such as `chat command "/compact keep the caption decisions"`.

Events (`event.kind`):

| kind | Fields | UI |
|---|---|---|
| `text` | `delta` | Appends to the assistant bubble |
| `thinking` | `delta` | Collapsed "Thinking…" |
| `tool` | `callId`, `name`, `summary` | Tool row, running |
| `toolEnd` | `callId`, `ok`, `summary` | Tool row, done or failed |
| `message` | `role`, `text` | Final text of a message; replaces the streamed one |
| `notice` | `text` | Grey line (retry, compaction) |

Tool names are MCP-style (`bashcut_timeline_get`), and `method` is the catalog name (`timeline.get`). The plugin
calls back with `method`.

## 4. App side (generic)

- **`ChatAgents`** (one per document) keeps one **`ChatAgentModel`** per ready plugin that provides
  `agent.chat`. Each `ChatAgentModel` holds:
  - the transcript for the UI;
  - `send(text, imageURL?)`, `stop()`, `reset()`;
  - the conversation ID per project, saved in `.bashcut/chat/<plugin id>.json` next to the project;
  - the token, issued on the first command call with author `.agent` and revoked on reset or a project switch.
    With **Allow agent timeline edits** off, no token is issued, so edits fail.
- **Tools:** every `CommandSpec` except `agent.*`, `chat.*` and `ui.notify`. The app also refuses any other
  method a plugin calls.
- **Context:** `document.contextText()` plus the timeline summary on every turn. The instructions are a generic
  preamble (how to work in steps, look with `ui frame`, keep edits undoable) plus `CommandCatalog.instructions`.
  The plugin adds its own identity.
- **Dock:**
  - one tab per chat agent, titled with the plugin name;
  - **Start <name>** in the empty state and in the + menu;
  - each tab has the transcript with tool rows, an input box, Send and Stop, a new-conversation button, and a
    status line (model and key state) with a link to Settings › Plugins.

  Survey, Write VO and Review fill the shown agent's input box; **Ask agent…** (⌘K) sends the request written in
  the Ask agent sheet as a turn.

  **Send to Agent** (clip menu, Clip menu, multi-selection Inspector; `ui action clip.send-to-agent`) attaches the
  selected clips as chips over the input (`Clip · Main · 00:12–00:18`, a linked pair once). Chips stay when the
  selection changes and until the user removes them or starts a new conversation; every message carries them
  as a `[Scope]` block (item IDs, layer, frames and the rule "Edit only these items; ask before changing anything
  else") and as `scope`. The transcript keeps each message's scope. A terminal tab gets the block pasted in its
  input instead. With no agent open it opens the first chat agent, or shows the dock when there is none.
- **CLI/MCP:**
  - `chat status` lists every chat agent;
  - `chat send <text> [--plugin <id>] [--image <path>]` starts a turn and returns at once;
  - `chat transcript [--plugin]` shows the conversation; poll it until `running` is false;
  - `chat stop` and `chat reset`;
  - `chat attach --items a,b [--plugin]` and `chat detach [--items a] [--plugin]` change the chips;
    `context get` reports the shown chat tab's as `scope`;
  - `ui action agent.open-chat` opens the first chat agent's tab;
  - `ui view` reports `chatTab`.

  `--plugin` defaults to the agent whose tab is shown, else the first one.

## 5. Director, the first chat agent (`plugins/director` in `bashcut-plugins`)

- **Manifest:** `bashcut.director`, name Director, `apiVersion` 4, `transport: session`, capability `agent.chat`,
  provider `bashcut.director.agent` (`timeoutSeconds` 300).
- **Options:**
  - `provider` (enum: anthropic, openai, google, openrouter, groq, xai, mistral);
  - `model` (string; empty means that provider's default);
  - `apiKey` (secret);
  - `thinking` (enum off/low/medium/high);
  - `maxTurns` (integer, default 40).
- **Dependency:** Node.js ≥ 22.19.
  - `bin/check` finds `node` in the plugin data folder, then in Homebrew, nvm and Volta folders.
  - `bin/setup` downloads the official Node 22 LTS for darwin-arm64 into `BASHCUT_PLUGIN_DATA/node`, checking it
    against `SHASUMS256.txt`.
- **Code:** TypeScript in `plugins/director/src`, bundled with esbuild into `plugins/director/dist/director.mjs`.
  The bundle is committed, so there is no `npm install` on the user's Mac. `bin/provider session` runs it.
- **Conversations:** saved as JSON in `BASHCUT_PLUGIN_DATA/conversations/<id>.json` after each turn, so an idle
  shutdown (90 s) does not lose them. Context is compacted when it nears the model's window.
- **Tests:** pi-ai's faux provider scripts the model; tests drive the session protocol end to end, with no network.

## 6. Security

- The model's only way to act is through catalogued commands, with the app's checks. It has no shell and no file
  writes. Its only file read is `read_skill` inside the kit folder.
- The API key reaches only the plugin process, in the request. It is never logged by the app or the plugin.
- Images sent to the model are the `ui frame` PNGs and the frames the user attaches.

## 7. Phases

1. API 4 in the core: host channel, `secret` options, `agent.chat` validation, plus tests with a Python fixture
   plugin.
2. App: ChatAgents and ChatAgentModel, dock tabs, `chat` commands, docs.
3. Plugin: `bashcut-plugins/plugins/director`, with faux-provider tests.
4. Live test in a scratch project with the faux provider (scripted tool calls), then with a real key when Nolan
   adds one.
5. Later: OAuth subscription logins (pi-ai supports them), several conversations, cost and token display.
