# Changelog

- Set the first TestFlight candidate version to 0.0.1 (build 1).
- Add the Mac App Store category, sandbox entitlements, and BashCut app icon required for TestFlight validation.

## [Unreleased]

- **Knowledge history with diff and revert** (#70). A new **History** section in the Knowledge window lists every
  change to lessons, preferences, facts, memos and project skills, newest first, with who made it and a line diff.
  **Revert…** puts the entry back to how it was before the change (a removed entry comes back, an added one goes)
  and is recorded too, so a revert can be undone. Memo and skill edits are now recorded with their text and
  author. `knowledge history` takes `--kind` and `--target` and returns `diff` and `revertible`; the new
  `knowledge revert <id>` does the same as the button (an agent's revert of a change for every project asks for
  approval). Rejecting a preference proposal changed nothing, so it cannot be reverted.
- Knowledge window: the empty Inbox message is centred, the Skills count follows skills added or removed on disk,
  and a status message such as "Change reverted" clears when you switch sections.
- **Knowledge inbox** (#69). The Knowledge window opens on a new **Inbox** section when something waits for
  review: proposed lessons, kit change proposals (lessons tagged `kit`, with their diff coloured) and an agent's
  preference changes for every project, each with **Approve**, **Edit…** and **Reject**. An agent's `set-pref` for
  every project no longer blocks on an approval sheet: it waits in the inbox (`{"approval": "proposed"}`), unless
  Settings lets agents act without confirmation. `knowledge proposals` lists both kinds (`type` `lesson` or
  `value`), and `knowledge approve p-… --value TEXT` applies an edited value. The book button in the agent dock
  shows the number of proposals, or a dot when agents changed knowledge since your last visit. The session summary
  counts preference proposals too. Fixed: rejecting or deleting the lesson open in the Lessons editor crashed the
  app; a kit change's diff is edited in a multi-line monospaced editor.

- Knowledge window: the scope of a preference ("This project" / "Every project") sits next to its key and is no
  longer cut off.

- **Knowledge window** (#68). The book button in the agent dock now opens a resizable **Knowledge** window instead
  of the small sheet, so it can stay open while agents work; it reloads when agents or people change the files.
  Sections: **Lessons** (search, filter by scope, status and tag, newest or oldest first; edit every field,
  approve or reject a proposal, enable, disable or delete; shows which agent and session added it and when),
  **Preferences** and **Project facts** (edit values inline, add and remove), **Notes** (the two memos) and
  **Skills**. Entries changed since the last visit carry a "New" badge, with counts in the sidebar. Changes made
  here are recorded as the user's. `ui view --knowledge-section` picks the section, and `knowledge lessons` takes
  `--sort newest|oldest` (newest first by default) and also searches the evidence.

- **Agents start every session with what they learned** (#73). New terminals, chat agents and handoffs get a
  short summary of the structured knowledge: active lessons with their fix, preferences (a project value wins over
  the one for every project), project facts, and the number of proposals waiting for review. It is bounded (20
  lessons, 30 preferences, 30 facts, one line of at most 240 characters each) and skips a file it cannot read.
  `context get` returns it as `knowledge`.

- **Structured agent knowledge** (#67). Besides the free-text memos, the agent can now keep lessons (title,
  symptom, cause, fix, evidence, tags, status `proposed`/`active`/`disabled`, and who wrote it in which session),
  the user's preferences and facts about the project. They are plain JSON files that Claude Code and Codex can read:
  `.bashcut/knowledge/` in the project, and `Application Support/BashCut/Knowledge/` for every project. Every change
  is appended to `history.jsonl` with the entry before and after. New commands: `knowledge lessons`, `add-lesson`,
  `update-lesson`, `remove-lesson`, `prefs`, `set-pref`, `facts`, `set-fact`, `proposals`, `approve`, `reject`
  and `history`. An agent's lesson for every project always starts as a proposal. Changing or removing knowledge
  for every project, and approving or rejecting a proposal, waits for the user's approval when an agent asks.

- **Python plugins can share one Python and one package cache** (#115). Plugin processes get
  `BASHCUT_SHARED_DATA` (`PluginData/_shared` in Application Support) and `BASHCUT_SHARED_CACHE`
  (`PluginData/_shared` in Caches). A plugin built with uv points `UV_PYTHON_INSTALL_DIR` and `UV_CACHE_DIR` there,
  so a second ML plugin reuses the same Python and clones the same wheels instead of downloading and storing them
  again. Settings › Storage shows them as "Shared plugin runtimes" and "Shared plugin downloads", and
  `storage clear` takes `shared-data` and `shared-cache`. Removing a plugin leaves them alone.
- **Settings › Storage shows one row per plugin, largest first** (#114). Each plugin's folder, data and downloads
  add up to one total, so a Python ML plugin of 1.5–3 GB is no longer split across two rows in plugin-ID order.
  Expand a row to see its parts and the same Delete and Free Up buttons as before. Data left over from a removed
  plugin is marked as such. `storage get` adds `plugins`, each plugin's total sorted by size, lists plugin entries
  in that order, and has one `plugins` entry per installed plugin instead of one for the whole folder.
- **Plugin hooks run at most 4 at a time** (#99). One edit heard by hundreds of plugins used to start a plugin
  process for each of them at once. Hook deliveries now share a limit of 4 (fewer on a Mac with fewer cores), and
  plugins take turns, so a busy plugin cannot hold up the others. A newer event still replaces a waiting one of the
  same kind. `plugins hooks` shows the queue: the limit, the plugins running, and how many deliveries are queued or
  debouncing.
- **Plugin actions no longer flood the MCP tool list** (#98). MCP lists at most 40 `bashcut_action_…` tools, with
  actions that can run on the current selection first, then the most recently run. Any other action is still found
  with `plugins actions` and run with `plugins run`, and an action's tool name keeps working when it is not listed.
  `plugins actions` takes a search text and `--plugin`, and reports when each action last ran.
- **One cache folder per project.** Preview proxies, waveforms, speed-ramp audio, still-image movies, loudness
  scratch files and agent frames now all live in `.bashcut/cache/`, which is excluded from Time Machine. Opening a
  project moves caches from their old `.bashcut/` folders (a quick rename, nothing is made again). The project's
  own data (history, autosave, library, plugins, skills, memo, chat) stays in `.bashcut/`.
- **Project caches are marked for git, and the plugin catalog copy moved to Caches** (#101). New and saved projects
  get a `.bashcut/.gitignore` listing what BashCut can make again (proxies, waveforms, ramp audio, stills, loudness
  scratch files and agent frames), so a project kept in git no longer picks up gigabytes of proxies; an existing file
  is never rewritten. The saved copy of the plugin registry is now in `~/Library/Caches/BashCut/Registry` instead of
  Application Support, which Time Machine backs up; an old copy is moved there once. Where everything lives is now
  documented in [Storage on disk](docs/reference/project-format.md#storage-on-disk).
- **Faster plugin catalog with many plugins** (#103). Opening the Text or Audio panel, the Plugins sheet or a
  project no longer reads every plugin's manifest and walks every file in every plugin folder on the main thread.
  Manifests are read again only when they change, and each plugin shows the result of its last file check;
  plugins not checked yet since launch are checked in the background and show **Checking…** meanwhile. Running a
  plugin still checks all its files first, and **Reload** checks them at once. With 1000 plugins a refresh takes
  ~33 ms instead of ~400 ms. `scripts/verify.sh perf` now also times the catalog with generated plugins.
- **Faster library on large libraries.** Placing or applying a library item no longer rewrites the whole
  `library.json` on the main thread: use counts are kept in `usage.json` and written in the background (older counts
  move there on the next change). Each stored file's SHA-256 is saved when it is copied in, so `library stats` no
  longer reads every file to find duplicates, and stats, adding or updating items with files, removing items and
  importing or exporting packs run off the main thread.
- **Approval prompt wording.** Approving an agent's library, knowledge or agent setup change no longer says it
  starts an export; the button reads **Approve** (exports keep **Approve and export**).
- **Agent knowledge stays in the project** (#100). The project memo and project skills are now always stored in
  the open project's folder, not in the agent workspace (where every project shared one memo) or the home folder
  (where a shared skill became global for Claude Code and Codex). Skills are linked only into the project's
  `.claude/skills` and `.agents/skills`. To reuse knowledge across projects, Agent Knowledge has **Notes for every
  project**, stored on this Mac; an older workspace or home memo is offered once to move there or into the project.
  Agents: `knowledge memo FILE --scope user` (asks for approval), `knowledge migrate [--to project]`, and
  `knowledge get` returns `userMemo`, skill paths and any `legacy` memo.
- **Text, Stickers and Effects come from the library** (#75). Their built-in items (6 text styles, 8 emoji stickers,
  Punch in and Reset framing) are now built-in library packs, so the panels render from data and also show text
  presets, stickers and effect presets saved in the project or on this Mac. Nothing else changes for users; agents
  can use them by ID (`library place fire`, `library apply punch-in`) and save improved copies with `library update
  <id> --as <new-id>`.
- **Library items for agents** (#74). Every library panel now has one item model: text presets, stickers, effect and
  transition presets, looks, audio and voices, each with tags, a pack, source and license, who made it, a version
  history and usage. Items live in the project (`.bashcut/library`, so they travel with it), on this Mac, in plugins
  or built in; built-in and plugin items are read-only, and improving one saves a new version or a copy. Agents:
  `library list|get|stats|add|update|remove|apply|place|import-pack|export-pack`; saving to this Mac's library
  asks for approval.
- **Link (developer mode), Reload and Replace…** (#83). When you add a plugin folder, the approval can install it as
  a link to your folder instead of a copy, so you can keep editing it; Installed shows the folder, and **Reload**
  restarts the plugin and checks its files again (changed files still need Trust; removing it keeps your folder).
  Copied plugins get **Replace…** to update them from a new folder or zip with the same id. Agents: `plugins install
  --path <folder> --link`, `plugins replace <id> --path <path>`, `plugins reload <id>`, and `linked` in `plugins
  list`.
- **Add plugins from a link** (#83). Add Plugin… now opens a sheet where you can paste a link: a `.zip` /
  `.bashcutplugin` file, a GitHub repo (`#tag`, `/tree/<ref>/<folder>`, or its `plugin.json`), or a GitHub release
  (its one plugin archive). Repo links are pinned to the commit they point at. `#sha256=<hex>` (or the SHA-256
  field) requires that exact archive. For private repos and servers, an access token per host is kept in the
  Keychain and sent only to that host. The approval shows the link and the commit or release it resolved to;
  Installed and `plugins list` (`source`) remember it. Agents: `plugins validate --url` and `plugins install --url
  [--ref] [--sha256] [--scope]`, and `ui open add-plugin`.
- **Add plugins that are not in the registry** (#83). Plugins › Installed (and Settings › Plugins) has **Add
  Plugin…**, which takes a plugin folder, its `plugin.json`, or a `.zip` / `.bashcutplugin` archive; dropping one on
  Installed works too. BashCut checks it first and names each problem with the field and the fix, installs a checked
  copy, marks it "Not from the BashCut registry · unsigned", and lets you install it for this Mac or only the open
  project, saying which copy runs when the same plugin is installed elsewhere. Agents: `plugins validate <path>` and
  `plugins install --path <path> [--scope user|project]`; only the user approves the install.
- **Plugins are grouped by category** (#63). Plugins › Browse has a chip bar (All, Agents, Captions, Voice, Audio…,
  each with a count) and, without a search, one section per category; each row shows its category with an icon.
  Plugins › Installed puts Updates Available and Needs Attention (not trusted, changed, outdated or missing a
  dependency) first, then the rest by category. Settings › Plugins groups plugin options by category, one collapsible
  plugin at a time, with a filter. A plugin's category comes from its registry listing, then the new optional
  `category` field in `plugin.json`, then its capabilities. Agents: `plugins search --category`, `plugins list
  --category` (each plugin now has `category`), and `ui view --plugins-tab --plugins-category`.
- Writing plugins links to `scripts/new-plugin.py` in `bashcut-plugins` (#84), which generates a working plugin
  (capability, action, hook, options or chat agent; Swift, shell, Node.js or Python) to start from.
- **Export progress is easy to see** (#62). While an export runs, the Export… button shows a progress ring and
  percent; clicking it opens the running export's details (file, step, queue) with Cancel and New Export… (⌘E still
  opens the Export sheet). A toast at the bottom right says when an export starts, is queued, finishes (Open,
  Reveal), fails or is cancelled, and names the agent that started it. The activity capsule is wider and tinted
  while exporting, and the Dock icon shows a progress bar. New UI actions for agents: `show.export-progress`
  (also `ui.open export-progress`), `export.cancel`, `export.dismiss-notice`.
- **A second export no longer fails on a taken name.** The Export sheet proposes the next free name (`long1-2`,
  `long1-3`…) when the project name was exported before, warns under Name when the typed name is already exported
  or queued (with a "Use long1-2" button) and disables Export until it is free. `export start` refuses a taken name
  before asking for approval, and every such error suggests a free name.
- **Sound analysis for agents, no ffmpeg needed.** `audio measure --media ID` returns a file's loudness (LUFS),
  true peak, loudness range and its energy share in the speech and presence bands (1–4 kHz), to choose music that
  sits under a voice. `media sync --media CAMERA --to SCREEN [--item ITEM]` finds the offset between two recordings
  of one session from their sound (or where a render plays inside a screen recording), checks both halves for
  drift, and with `--item` gives the matching source frame. The core Audio Analysis plugin (1.1.0) provides the new
  `audio.sync` capability and the band shares (`bands` on `audio.loudness`).
- `captions generate --from S --to S` transcribes one stretch of the media again; with `--replace` only the captions
  heard in that stretch are replaced. Providers get `startSeconds`/`endSeconds`. `review run` flags captions that
  look like a recognition loop (over 10 s, or one word repeated).
- **Crop and rounded corners** for video clips: the item's `crop` group (`left`, `right`, `top`, `bottom` as
  fractions of the picture, `radius` as a fraction of the visible part's shorter side) cuts the source before it is
  placed, for a presenter box over a screen recording.
- `clip motion --focus x,y,w,h [--focus-to x,y,w,h]` frames a rectangle of a clip's picture (a panel of a screen
  recording): BashCut works out zoom, pan and tilt for the canvas and keeps the picture's edges outside the frame.

- Use Nolan in the BashCut copyright notice to match the App Store listing.

- Add a public privacy policy covering local editing, optional integrations, network requests, and support.

- **Terminal agents from plugins** (plugin API 5). A plugin with the new `agent.terminal` capability adds an agent CLI
  (Gemini CLI, Qwen Code, opencode…) to the agent dock as a terminal tab next to Claude, Codex and Shell: in the +
  menu, the empty dock (Start / Continue / New conversation) and Handoff, with the icon from its manifest. The plugin
  answers `launch` with the command line (argv, a few variables, the folder to start in); BashCut gives the tab its
  own token and the `bashcut` MCP server, filters the environment to what the manifest declares, and links the agent
  kit's skills where the plugin asks, so skills stay in BashCut. An optional `session` op lets the next tab continue
  the project's conversation. Agents use `agent terminals` and `agent open <id> [--new]`. Spec:
  `docs/specs/12-terminal-agents.md`.
- BashCut is released under the MIT License (`LICENSE`).
- **Close Project** (the window's close button or ⌘W, File menu, the project name menu at the top left, ⇧⌘W) returns
  to the Welcome screen with its recent projects, as CapCut's editor returns to Home. Closing the window again on the
  Welcome screen quits BashCut; ⌘Q always quits. Unsaved changes are saved first, without asking; if the save
  fails (the file changed on disk) the project stays open. Agents use `project close` (with `--save-current` or
  `--discard-current` when there are unsaved changes) or `ui action project.close`; agent tabs stay open.
- BashCut tells you when a new release is out. Homebrew and downloaded copies check GitHub once a day when a project
  opens (Settings › General, on by default), and a newer release opens **Software Update** by itself, once per launch:
  the new version, its release notes and how to update (copy `brew upgrade --cask bashcut`, or **Download…** for a
  dmg copy), with **Skip This Version** (no reminders until a newer release) and **Remind Me Later** (ask again the
  next day). Until it is skipped, ☰ shows a dot and an **Update to BashCut …** item. **BashCut › Check for Updates…**
  (also ☰ and Settings › General) checks on demand. Nothing is installed automatically, App Store and TestFlight
  copies are not checked, and `scripts/run.sh` builds check only on demand (`BASHCUT_UPDATE_FEED` and
  `BASHCUT_UPDATE_INSTALL` let them try the prompt). New commands `app version` and `app update-check`, and UI
  actions `show.updates`, `show.about`, `app.update-skip` and `app.update-later`.
- `bashcut-mcp` accepts the `initialize` request of Codex 0.160 (tested with the CLI that ships in the ChatGPT app).
  Codex sends objects in `capabilities.experimental`, which the MCP SDK decodes as strings, so the handshake failed
  with -32603 and Codex had no BashCut tools although `agent setup codex` reported success. The server now ignores
  the client's experimental capabilities, which it never used, in every `initialize` until the client confirms the
  handshake, so a retry after a rejected `initialize` works too. `scripts/test-mcp-process.py` replays Codex's request.
- **Plugins** is a labelled toolbar button next to Review and Export instead of an item in ☰. Its dot shows plugin
  updates (cyan) or plugin edits to review (orange), and clicking it opens what needs attention.
- The agent dock asks to set up the agent kit when Claude Code or Codex is installed without it (or with an older
  one): **Set Up** / **Update** does what `agent setup claude|codex` does, **Details…** opens Settings › Agents
  (new `show.agent-kit` action, also Agent › Agent Skills… and ☰), and **Later** (`agent.kit-later`) hides it
  until BashCut has a newer kit.
- The detached agent window (BashCut Agent) uses the editor's dark appearance; its text was dark on dark before.

- The first clip sets the canvas. New Project's Frame starts at **Auto · from the first clip**: the first video or
  image placed on the timeline (drag, Append, Insert/Overwrite, import, or an agent's edit) sets portrait, landscape
  or square to match it, keeping the short side, in the same undo step as the clip, and the status bar says so.
  Picking a shape in New Project or changing it later (format menu, `project format`, `setFormat`) makes it final,
  and projects made before this keep their canvas. Projects store this as `canvasFromFirstClip`;
  `project create --canvas` defaults to `auto`.
- The viewer says which picture it shows. Its header is a **Timeline | Source** switch instead of "VIEWER" and
  "SOURCE" labels; Source names the Media clip, gets a cyan frame and a one-line hint (Mark In/Out, then E or Q;
  Esc to go back). Clicking, dragging, seeking or selecting on the timeline (and `ui seek` / `ui select`) returns
  to the timeline, so the viewer no longer keeps playing a Media clip while the timeline is edited, and Space plays
  the timeline again. Esc closes the source viewer; the new `source.show` action (Playback › Show Source Viewer,
  the Source segment) reopens the last clip.
- New projects have a default folder, `~/Movies/BashCut` (made on first use; visible in Finder and not behind a
  macOS privacy prompt like Desktop or Documents). New Project's Save in starts there instead of "Not selected", so
  Create works after typing a name, and shows paths like `~/Movies/BashCut` instead of only the last folder name.
  The folder a project is created in becomes the next default; Settings › General › Projects folder changes or
  resets it. Agents: `project create` no longer needs `--dir`, and `project folder [<path>] [--reset]` shows or
  changes the default. Sandboxed builds get the Movies folder entitlement.
- README (English and Vietnamese) Install covers Homebrew (`brew install --cask dongnguyenvie/tap/bashcut`), the
  notarized dmg/zip from GitHub Releases (with checksums and linking the CLI), and TestFlight; the header links the
  latest release.
- Developer ID builds (`scripts/build-release.sh`) are no longer sandboxed: they sign with
  `Configs/DeveloperID.entitlements` (microphone only, hardened runtime), so the bundled `bashcut` and `bashcut-mcp`
  run from any terminal; sandboxed helpers that inherit the app's sandbox were killed (SIGTRAP) there. The build
  fails if any Mach-O is sandboxed or the CLI dies on launch. App Store builds keep `BashCut.entitlements`. The
  release summary no longer prints the team ID.
- `scripts/publish-homebrew.sh` publishes a release from `scripts/build-release.sh` to Homebrew. It checks the
  zip (version, build, signature, Gatekeeper and stapled ticket), uploads the zip, dmg and `SHA256SUMS` to a GitHub
  release `v<version>`, and pushes `Casks/bashcut.rb` to the tap (`<owner>/homebrew-tap` by default). The cask
  installs the app and links `bashcut` and `bashcut-mcp`. `--dry-run` prints the cask without publishing; it is
  rendered by `scripts/lib/homebrew.sh`, tested in `scripts/ci/test-script-lib.sh`, and passes `brew style`.
- README (English and Vietnamese) links the public TestFlight beta: https://testflight.apple.com/join/XwsNZxre.
- Recent projects on the Welcome screen are named by their project folder, with the folder's location below,
  instead of all reading `project.bashcut`.
- The About panel lists the third-party packages in the shipped app, CLI and MCP server with their verbatim
  license texts, as their MIT and Apache-2.0 licenses require for any distributed build, free or paid.
  `scripts/update-acknowledgements.py` generates them from the resolved packages; `verify.sh test` checks they
  are current and that every resolved package is classified as shipped or not.
- One BashCut mark everywhere: `BashCutLogo` draws the shell prompt over a timeline as vectors, and
  `scripts/render-app-icon.sh` renders the app icon (now on the macOS icon grid: a rounded 824-point tile with a
  shadow, not a full square) and the README logo from it. The Welcome screen shows the mark beside the name with a
  shell-style tagline instead of a scissors symbol, and `scripts/run.sh` builds now carry the icon too.
- README follows a landing-page layout: logo, tagline and links, a screenshot of the sample project, About,
  What's inside, Install, How to Build, Verify, Related repositories and Documentation. Images live in
  `.github/assets/`. A Vietnamese README (`README.vi.md`) mirrors it.
- CI (`Build and verify`) runs only when triggered by hand, not on pull requests or pushes; the `xcode-tests`
  input chooses between running the Xcode test plan and only building its targets.
- Add release scripts. `scripts/build-release.sh` builds for distribution outside the Mac App Store: it archives
  with a Developer ID identity, checks every Mach-O for a secure timestamp (executables also for the hardened
  runtime), notarizes, staples and validates the ticket, then writes `BashCut-<version>.zip`, `.dmg` (and `.pkg`
  with `--pkg`) and `SHA256SUMS` to `build/release/`. `create-dmg.sh` and `create-pkg.sh` are its steps and also run
  alone. `scripts/deploy-testflight.sh` uploads a Mac App Store build to TestFlight.
- Shared shell helpers in `scripts/lib/` (`common.sh`, `signing.sh`, `notarize.sh`), tested under bash 3.2 by
  `scripts/ci/test-script-lib.sh` in `verify.sh test`. Account details (team ID, Apple ID, app-specific password)
  come only from the git-ignored `.env`; `.env.example` lists the keys.
- Split the ramp window envelope expression: Release (`-O`) archives failed with "unable to type-check this
  expression in reasonable time".

- Update the agent kit in the app: Settings › Agents checks bashcut-agent-kit's signed `releases.json` and offers
  **Download & Update** (`agent kit-check`, `agent kit-update`). Releases are verified (HTTPS from GitHub,
  first-party signature, SHA-256, one kit folder without escaping links) before they replace the built-in kit, and
  Claude Code and Codex are refreshed afterwards. Claude Code's row flags an older cached plugin version.
- Bundle the agent kit's tracked files in Xcode builds too (`scripts/bundle-agent-kit.sh`, shared with `run.sh`).

- Check plugin trust with an fts(3) walk that hashes raw lstat fields: a dev-linked plugin with node_modules
  (~13k files) answered option reads in ~150 ms and now ~45 ms. Every check still walks the whole tree.

- Stopping an export lets in-flight sample reads return before the reader is cancelled; only a read still
  blocked after 500 ms is interrupted. Cancelling a reader under a waiting read crashed AVFoundation under load.

- Run app test suites in parallel again, with only the Unix-socket suites in a separate sequential pass (~29 s
  instead of ~65 s). Five engine tests that depended on another test generating the fixture now await it.
- Pull-request CI compiles the Xcode app and tests without re-running the suites SwiftPM already ran; a
  manual run still executes the Xcode test plan. The SwiftPM cache is no longer re-uploaded on every commit.
- Localize the new ramp-audio clearing and preview-cache messages in Vietnamese. Tests report benchmark
  numbers through one `TestMeasurement` helper instead of scattered `print` calls.

- Name internal types after their role: `TimelineDryRun`, `DebugLogWriter`, the `SpeedRamp*` audio types,
  `ExportSampleTransfer` and `FileSignature`. Bound plugin secrets use `…/binding/<hash>` Keychain accounts.

- Render speed-ramp audio on a private queue instead of Swift's cooperative executor, publish cache files
  with an atomic rename, check reader outputs before adding them and decode sources with more than two
  channels as stereo. The cache folder is now `.bashcut/ramp-audio`, matching its storage entry.
- Bind plugin secrets to the options a manifest marks `bindsSecrets` instead of hard-coded Director option
  names. Saving a key for changed plugin code removes that installation's keys for older fingerprints.
- Run plugin processes with `PYTHONDONTWRITEBYTECODE=1` so bytecode never changes a pinned plugin tree.
  Dependency probes refuse inline code in combined, attached and long flags of script interpreters, while
  ordinary tools such as `grep -e` remain allowed.
- Rotate a custom `BASHCUT_DEBUG_LOG_PATH` beside its own name and record preview signposts under the
  `app.bashcut` subsystem.

- Keep abrupt audio gain changes on separate reusable composition lanes, preventing the native mixer
  from turning an adjacent -20 dB cut into a fade. Continuous-gain cuts still share one lane.
- Generate H.264/AAC test footage natively on demand, with exact 30000/1001 frame timestamps and isolated
  temporary storage. Clean-checkout tests no longer need ffmpeg or a manual fixture-generation step.

- Inject storage roots and inherited plugin environments in tests instead of changing process-wide
  environment variables. Plugin subprocess tests continue to verify that secrets are filtered out.

- Make the caption golden independent of lossy fixture backgrounds and use explicit sRGB in still-image
  test fixtures. CI retains failed snapshot images along with test logs.

- Check Undo/Redo availability through constant-time history accessors instead of copying both stacks.

- Include MCPBridge, Tools and the core benchmarks in strict SwiftLint verification.

- Add macOS CI for SwiftPM build/tests, CLI/MCP process tests, strict lint and Xcode tests on every PR.
  Verification logs and Xcode results are retained for failed-run diagnosis.

- Disable unconditional reader sample copies; configure H.264 High with source frame rate and a two-second
  keyframe interval, and optimize MP4 metadata placement for streaming. ProRes keeps its codec-specific
  settings. Private staging directories also contain encoder sidecars for complete failure/cancellation cleanup.

- Normalize exports from a lossless audio-only measurement pass, preserving the mixed gain, fades,
  keyframes and ramped audio while skipping video compositing/encoding. The final movie is still measured
  after encoding. On the synthetic five-minute fixture, measurement rendering drops from 9.886 to 0.264 seconds.
- Keep export partial filenames short even for long Vietnamese output names.

- Feed export audio/video on dedicated readiness-driven queues instead of sleeping 1 ms per transfer loop.
  Cancellation interrupts reads and drains callbacks before cleanup; asynchronous failures also terminate
  under backpressure. The synthetic five-minute 160×90 benchmark drops from 22.811 to 9.651 seconds.

- Export to a hidden partial file beside the destination, then publish the completed movie with an exclusive
  atomic rename. Cancellation and failures clean up only the partial; a destination created during rendering
  is preserved. MP4/ProRes publication, cancellation and destination-race tests cover the native writer.

- Prepare keyframe interpolation segments once per layer and binary-search them during arbitrary seeks.
  Sample all five picture properties together, preserving easing and hold boundaries while avoiding per-frame
  property dictionary lookups and repeated time conversion.

- Rasterize captions into their visible text/decorations bounds and cache the positioned CIImage across frames.
  A short 4K caption uses 303,104 bytes instead of 33,177,600; pixel tests cover all presets, outlines,
  shadows, Vietnamese/emoji, canvas edges and animated word variants.

- Reuse one synchronized color-cube filter per LUT, precompute custom-domain normalization and skip it for
  the standard 0–1 domain. Zero strength bypasses the graph. A 64³ LUT Debug graph benchmark drops from
  872.335 ms to 1.653 ms per 1,000 frames; domain/blend pixel parity and concurrent frame isolation pass.

- Skip neutral exposure and color-control filters, including LUT-only color dictionaries. A 1,000-frame
  Debug graph-construction benchmark drops from 10.004 ms to 0.361 ms; non-neutral pixel parity is tested.

- Reuse the ungraded comparison build for color-only edits when its drawing inputs and current media
  structure match. Build both variants concurrently on a cache miss; changed proxies/files and non-color
  edits invalidate reuse. File replacement identity is included in composition structure checks.

- Verify ramped media through native AVPlayer readiness/seeking and H.264/AAC export for both pitch modes,
  including exported duration, audio/video tracks and visible picture.

- Show speed-ramp PCM cache usage in Settings and CLI/MCP storage commands. Clearing ramp audio drains
  preview builds and releases both players before deletion, then restores the latest edit; exports wait until
  clearing ends. Supported 0.1× and 16× rates now have duration, pitch and PCM regression coverage.

- Prerender speed-ramped audio as one continuous PCM segment: bounded WSOLA alignment preserves pitch and
  native varispeed preserves resampler state when pitch follows speed. Source-signature/curve/trim/pitch caches
  avoid rerendering gain edits; cancelled renders remove staging files. Synthetic PCM tests cover preset
  boundaries, exact duration, source timing, low/high fundamentals, stereo phase and cache invalidation.

- Plan speed ramps adaptively per linear-speed span, using one piece for flat spans and bounding source-time
  error to a quarter source frame. Cache plans per item across edits and share them between picture and audio.
  Continuous prerendered audio now avoids separate rate processors at those visual piece boundaries.

- Key caption raster caches only on text and drawing styles, hashed once per text layer. Moving, trimming,
  duplicating or animating captions now reuses their images; canvas size and spoken-word variants stay distinct.

- Share video lanes between clips and non-overlapping transition holds, keeping sequential transitions
  on two video tracks per project layer instead of allocating a new track for each transition.

- Size independent preview/export asset LRUs to the active media count, retaining large projects across edits
  without exports evicting preview proxies. An 80-media Debug fixture opens 80 instead of 320 assets over four
  builds; median warm build time drops from 69.897 ms to 27.544 ms. Smaller projects shrink the cache again.

- Coalesce comparison scrubbing and playback drift correction through one seek queue per player.
  New targets replace pending seeks, and stale completions cannot affect a replacement player.

- Record preview build, readiness and player-swap intervals in Instruments and private debug logs,
  including interrupted stages, to separate composition work from player preparation.

- Observe preview readiness instead of polling, cancel obsolete observations promptly, and keep the last
  picture if a new player takes longer than 30 seconds. Stale build failures no longer replace current status.

- Replace failed or unready preview/comparison player items on rebuild, even when the media structure is
  unchanged. In-place instruction updates now require healthy ready-to-play items on both sides.

- Build previews immediately for discrete edits, undo/redo and automation. Only edits with a coalescing key
  retain the slider/drag debounce; a discrete edit cancels a pending coalesced build without waiting for it.

- Preserve RPC error codes and data through CLI and MCP. CLI writes a JSON error to stderr with distinct exit
  statuses; MCP supplies structured error content. Editor busy maps to -32003, and stale-revision errors
  include expected/actual revisions. Regression tests exercise real CLI/MCP processes against isolated sockets.

- Run an isolated real MCP process regression in the full verification suite: initialization, tool failure,
  EOF shutdown and private log flushing, without contacting an app or reading real session credentials.

- Keep debug-log handles open and serialize append/rotation across processes with a stable flock lock file.
  Writers detect another process's rotation before appending. MCP flushes on shutdown; Release logging is off
  unless explicitly enabled. `BASHCUT_DEBUG_LOG_PATH` permits isolated diagnostics and process-level tests.

- Redact sensitive command arguments and omit RPC results/error payloads from persistent diagnostics. CLI
  logging no longer records raw argv; chat, plugin options, operation payloads and arbitrary action parameters
  stay out of logs. Unified-log content is private, and log/rotation files use owner-only permissions.

- Add `timeline apply --dry-run` / MCP `dryRun`: validate a batch without mutating history, files or preview,
  and return the projected revision/duration plus changed items/tracks and added/removed tracks.

- Reuse audio composition tracks for sequential clips on the same project layer with the same pitch mode.
  Reset each clip's gain envelope and retain separate lanes for overlaps and different pitch algorithms.
  A 240-cut fixture uses one audio track instead of 240; build-to-player-ready median fell from 718 to 94 ms.

- Build frame instructions with an interval sweep that preserves compositing order and visits each layer's
  start/end once. A generated 1,000-caption Debug timeline improved from 390.82 ms to 16.69 ms median build.

- Index media and timeline items once per composition build, and resolve/load each media once per snapshot.
  Repeated cuts reuse the same source decision, still-image movie and asset metadata; later builds still
  detect new proxies. A 240-cut Debug fixture improved from 41.29 ms to 23.07 ms median rebuild time.

- Enforce plugin action confirmation at execution for UI, shortcuts and automation alike. Privileged dialogs
  expose `userOnly` and cannot be answered through `ui.respond`; cancellation never starts the plugin request.

- Include hidden files and Python bytecode in plugin fingerprints; reject symlinks leaving the plugin folder
  and dangling links. Cache validation now uses fresh inode, mode and nanosecond ctime/mtime metadata, so
  rewriting a same-size file and restoring its modification time cannot preserve an old approval.

- Scope plugin credentials to the installation root and complete fingerprint, as well as provider/endpoint.
  Trusting a same-ID project copy or a changed plugin does not transfer the original installation's secrets.

- Scope plugin trust, enable switches, hooks and local options to the canonical installation root. A project
  copy sharing an installed plugin's ID cannot inherit its approval or settings; catalog diagnostics identify
  the shadowed installation. Legacy ID-only approvals require review again because their origin is unknown.

- Bind plugin API keys to provider/endpoint settings. Switching destinations requires a key entered for that
  destination; legacy unbound keys must be re-entered. Plugins with secrets use user-only settings and ignore
  project option overrides, including overrides injected through raw timeline operations.

- Restrict chat tools to reviewed editing commands. Revoke chat tokens when agent edits are disabled, and
  check the preference on every host call before issuing or reusing a token.

- Refuse dependency repair when an approved plugin's files have changed, including disabled plugins. Recheck
  the full fingerprint before recipes start and require an explicit Trust action instead of silently repinning.

- Refresh bundled agent kits when their content changes, even at the same version and skill names. Validate the
  staged copy before replacing the stable folder so a failed refresh preserves the installed instructions.

- Cache parsed LUTs across composition rebuilds with a 64 MiB LRU budget and fresh file signatures. Build LUT
  catalogs once and avoid repeated item lookups; replacing or removing a LUT invalidates cached results.

- Require a live automation token for UI commands and chat mutations; after project switches, callers must read
  the new project before controlling it. Automated chat transcript exports stay inside the open project folder.

- Snapshot Vietnamese captions directly from the compositor before H.264 encoding; test player readiness and
  export metadata/non-black picture separately so encoder noise cannot fail caption layout checks.

- Require plugin trust before dependency health probes, including Doctor and automation. Install approvals list
  probe commands without executing staged archives or chosen folders.

- **A full Mac menu bar.** BashCut, File, Edit, Clip, Timeline, Playback, View, Agent, Plugins, Window and Help now
  carry every editor action with its shortcut, built from `UIAction` so menus, buttons and `ui.action` share one
  code path. File has Open Recent; Agent ▸ New Tab lists the ready chat agents; View has Library ⌘1–⌘8, Safe Area,
  Compare and the agent dock with check marks; Help links to the repository, plugin guide and issues (Info.plist
  `BCRepositoryURL`, `BCIssuesURL`, `BCContactEmail`; an empty key hides its item) and opens the logs folder.
  - New shortcuts: Settings ⌘,, Import Footage ⌘I, History ⌥⌘Z, Safe Area ⇧⌘', Compare ⌥⌘C, Speed Up ⌘],
    Slow Down ⌘[, Normal Speed ⌥⌘R, Unlink Audio ⌥⌘L.
  - Shortcuts without ⌘/⌥/⌃ (Space, I, O, ←, ⌫…) are shown in the menus but only run from a click, so typing in
    text fields and the timeline's own keys keep working. Editor items are disabled while a sheet is open.
  - On the timeline, ⇧F freezes the frame and N toggles snapping. File ▸ Close Window (⌘W) is added.
  - About BashCut shows the plugin API version, repository, issues and contact links.
- **A one-row toolbar in the title bar.** The project name (with an unsaved dot) opens a menu to reveal it in
  Finder or open another; undo, redo and the format stay; an activity capsule in the middle shows export progress
  (with cancel), work in progress, plugin edits waiting, or Saved/Edited with the revision and the export report.
  Review, Export… and the agent-dock toggle stay on the right; New, Open, Save, History, Plugins, Doctor and Settings
  move to a ☰ menu (with a dot for plugin updates or edits) and the menu bar. Empty toolbar space drags the window.
- **Command palette (⇧⌘P)** searches every menu-bar command, including recent projects, chat agents and plugin
  actions, ignoring case and Vietnamese marks; arrows and Enter run one. **Keyboard Shortcuts (⌘/)** lists every
  shortcut by menu plus the timeline-only keys. Both read the menu bar, so they never disagree with it
  (`ui open commands`, `ui open shortcuts`).

- **Slash commands and a better input in chat-agent tabs.** Enter sends the message; Shift+Enter or Option+Enter
  starts a new line, and Enter while typing with an input method (Vietnamese Telex) only commits the word.
  - Typing `/` opens a menu (arrows, Tab, Enter, Escape) with the app's commands, available for every agent:
    `/new` or `/clear`, `/stop`, `/settings`, `/copy`, `/export`.
  - The same menu lists `/skill:<name>` for each agent-kit skill, plus the plugin's own commands. Director adds
    `/compact`, `/model`, `/thinking` and `/session`.
  - Plugins list their commands with the `agent.chat` ops `commands` and `command`.
  - From the CLI: `chat commands` and `chat command "<line>"`.

- **Chat agents in the dock (plugin API 4).** A plugin with the new `agent.chat` capability becomes a tab in the
  agent dock: a chat whose model edits through BashCut's own commands (with the same checks, history and approvals
  as Claude Code and Codex), looks at the result with `ui frame` and follows the agent kit's skills.
  - The app side is generic; Director (`bashcut-plugins`) is the first such plugin.
  - Plugin API 4 adds the `secret` option type (Keychain; never listed or settable by agents) and the session
    host channel (`event` and `call` lines).
  - New commands `chat status|send|stop|reset|transcript` and `ui action agent.open-chat`.
  - Provider `priority` may now be left out of a manifest, as the plugin guide always said.

- **Settings in sections.** A sidebar splits Settings into General, Agents, Plugins and Storage, with each note
  under the setting it explains. Plugins lists the options of every installed plugin that has any (the same values
  as Plugins › Options… and `plugins option`) and links to Manage Plugins…. Agents open a section with
  `ui open settings` and `ui view --settings-section general|agents|plugins|storage`.

- **Removed the dock's model-API tab.** It sent one request to OpenAI or Anthropic and returned a script or a single
  timeline proposal, without tools, the agent kit or a look at the result, so it could not finish a video. Use a
  Claude Code or Codex tab instead (Codex also accepts `OPENAI_API_KEY`). The saved connection is forgotten on
  launch; an API key saved before stays in your Keychain (service `app.bashcut.model-api`) until you delete it.

- **Lighter rendering and Inspector during playback.** The Inspector no longer redraws on every played frame: only
  the *Keyframe at playhead* buttons follow the playhead (about 3% less CPU while playing with the Audio tab open).
  Text layers make their image cache key and keyframe anchor once instead of on every frame (the key alone cost
  0.7 ms per frame for a 200-word caption, 6.6 ms for 2,000 words), and the composition builds each text layer once
  rather than once per segment. Captions generated with word timings look only at the words near each cue instead
  of every word for every cue, and the timeline parses keyframes only for clips that have them.

- **Volume keyframes.** Audio clips and clips with sound can change volume over time: keyframe property `volume` in
  dB (like `volumeDb`, which it replaces while keyed), with the same eases as other keys, on top of fades and music
  ducking. Inspector › Audio › **Keyframe volume at playhead**, after which the Volume slider sets keys; `clip
  keyframe --property volume`. Audio items take only `volume`; text has none; motion presets stay for pictures.
  Keys show as diamonds on the timeline like the others.

- **Keyframes on the timeline.** A clip with keyframes shows a diamond along its bottom edge at each keyed frame
  (cyan on the selected clip), and scrubbing the playhead snaps to the selected clip's keys, so it lands on a key to
  change it. Keys left outside the clip by a trim are not drawn.

- **Faster preview for look edits.** Changing colour, text, opacity, framing, keyframes, volume or fades no longer
  reloads the preview player. The builder hashes what the composition plays where (`CompositionSnapshot.structure`),
  and when it is unchanged, the shown player takes the new instructions and audio mix and redraws the frame: about
  7 ms instead of about 110 ms with 40 clips. Trims, moves and speed changes still load the new composition behind
  the current picture.

- **Word-by-word captions.** A caption can show its words as they are spoken: **Highlight word** colours the word
  being said, **Karaoke** colours the words said so far, and **Reveal** makes words appear one by one (item field
  `wordStyle`, colour `textStyle.highlight`, default #FFD400). A transcription provider may return word timings
  (`wordsPath`), which are stored on each caption as `words` and follow the clip's trim and speed. Without them,
  timings are estimated from word length. Inspector › Text › Word by word (and *Use on all captions*), the Auto
  Captions picker, `captions words` and `captions generate --word-style`.

- **Keyframes and motion presets.** Clips, images and text can animate zoom, pan, tilt, rotation and opacity
  (item field `keyframes`: per property, keys `{frame, value, ease}` counted from the item's start; eases linear,
  in, out, inOut, hold). Inspector › Video/Text › **Animation** has presets: slow zoom in/out and pan left/right/up/down
  (Ken Burns for photos), and fade in and out, pop in, slide up and zoom punch for titles. **Keyframe at playhead**
  records every property there. Once a property has keys, its slider sets the key at the playhead. Agents use
  `clip motion --preset` or `--keyframes` and `clip keyframe`. Splitting a clip or trimming its start keeps the
  keys on the same picture. Clips also get a static **Rotation** (`transform.rotation`).

- **Still images on the timeline.** Import (or drag in, or `media import`) a JPEG, PNG, HEIC or other image: it
  becomes media of kind `image`, is placed for 3 s and can be trimmed to any length up to an hour. PNG
  transparency is kept, so stickers and logos sit over the clips below. Images fit or fill the frame like clips
  and take zoom, pan, tilt, opacity and color. The engine reads each image through a one-frame ProRes 4444 movie
  in `.bashcut/stills/`, remade when the image file changes.

- **Long plugin jobs no longer hit a fixed 120 s limit.** A session request now times out after 120 s
  *without a progress line*; each `progress` message restarts that window, up to 4 hours in total. A provider can
  declare `timeoutSeconds` (10–3600) for steps that stay silent longer; one-shot plugins use it as their whole
  limit.

- **Clips fit inside the frame in new projects.** A clip of another shape (portrait footage on a 16:9 canvas) was
  always scaled to cover the frame, cropping most of it. New projects now scale each clip by its longest side
  against the frame and show it whole with bars. The format menu switches the project between *Clips fit inside
  the frame* and *Clips fill the frame* (`project format --clips fit|fill`, project field `clipFill`), and the
  Inspector's **Fill frame** sets one clip (item field `fill`). Projects made before keep filling, so their
  zoom settings look the same.

- Fix: the agent dock did not show on the Welcome screen (no project open), so an agent could not be asked to
  create or open a project. The dock now sits beside the Welcome screen, whose recent-projects column narrows to
  make room, and agents are told that no project is open yet.

- Fix: `captions generate` placed captions at the media's own times from the start of the timeline. Captions now
  follow every clip where the media is heard (position, trim, speed, speed ramp); speech cut out of the edit gets
  none, and `--replace` replaces only the captions made from that media.
- Fix: approving **Install Dependencies…** for a plugin that was not trusted yet (a linked or copied folder) ran
  its setup but left it "Not approved yet". The approval now trusts those files, like installing from the
  registry.
- After `project open` / `project create`, the token that asked may edit at once (the result shows the new
  project); other tokens still read the project first.

- Fix: creating or opening a project closed every agent terminal, including the Codex or Claude tab that asked
  for it, so an agent could not create a project and then fill it. Tabs now stay open across project switches;
  each token must read the new project (`context get` / `timeline get` / `project get`) before its next edit,
  and open conversations are bookmarked for the new project.

- **Agent kit in BashCut.** The editing skills of `bashcut-agent-kit` ship inside BashCut and load in its Claude and
  Codex tabs (Claude: a skills-only plugin; Codex: links in its working folder). **Settings → Agents** shows the
  kit, can use another kit folder, and sets up Claude Code and Codex outside BashCut (plugin, skill links, MCP
  server). CLI/MCP: `agent status`, `agent setup in-app|claude|codex [--remove]` (approval required).
- `ui action agent.open-claude|agent.open-codex|agent.open-shell` opens a terminal tab like the dock's + menu (the
  only dock action without a command until now).
- Claude Code and Codex configuration folders moved with `CLAUDE_CONFIG_DIR` / `CODEX_HOME` are found even when
  BashCut starts from Finder (Settings, then BashCut's environment, then the login shell). In-app tabs get the
  variables, and resuming finds their sessions there; before, a moved folder meant a different login and no
  resume.

- **Edits stay fast on long timelines.** Tracks and items are stored typed instead of being rebuilt from JSON on
  every change, validation indexes transitions and media once instead of sorting a layer per transition, and a
  project that already passed validation is not validated again. At 1,000 items an edit takes 3 ms instead of
  24 ms. `swift run -c release bashcut-core-bench` in `Packages/BashCutCore` measures it.
- **Smaller, faster history journal.** Undo steps are saved as differences from the next state instead of full
  project snapshots: at 1,000 items a 200-step journal is 0.1 MB instead of 13 MB, saves in 35 ms instead of 1 s and
  opens in 70 ms instead of 5.5 s. Old journals still open.
- **The viewer no longer goes blank after an edit.** The new composition is prepared in its own player and swapped in
  once it shows the frame at the playhead; until then the previous picture stays. `ui frame` grabs from the new
  composition as soon as it is built (edit → frame about 210 ms).
- MCP `tools/list` answers in 0.1 ms instead of 35 ms: the command catalog is encoded once.

- **Faster agent round trips.** `bashcut-mcp` reads and writes stdio without the SDK's 10 ms polling and returns results
  as compact text only (the SDK re-decoded structured results slowly; compact JSON is also about a third fewer
  tokens): MCP calls dropped from 12–45 ms to 2–14 ms. Preview readiness and `ui frame` poll every 10 ms instead of
  100 ms, and the debug log no longer encodes whole results on the main actor. `scripts/bench-automation.py`
  measures it; numbers in `docs/status/implementation.md`.
- **Change the canvas of an open project**: the size in the toolbar is now a menu (Portrait 9:16, Landscape 16:9,
  Square 1:1), also `project format --canvas <c> [--resolution <r>]` and the new `setFormat` operation. One undoable
  edit; timing is kept and clip pan/tilt scale with the frame. Before, a project's format could never change.
- **Viewer zoom**: Fit, 25, 50, 100 and 200% from the viewer header (`ui view --viewer-zoom`); zoomed views scroll.
  Fit leaves a 12-point margin so a 16:9 picture no longer touches the panel edges.
- Fix: text was sized from the frame *width*, so titles grew 1.8× in landscape projects and ran off the frame. Text
  size is now a fraction of the short side (portrait looks the same as before), and a line wider than 90% of the
  frame shrinks to fit.
- The safe-area overlay follows the canvas: TikTok/Reels zones for vertical video, a 90% title-safe frame for
  landscape and square.
- `ui frame` waits for the preview to finish rebuilding after an edit instead of failing.
- Fix: a bad `atIndex`/`toIndex` said "must be an integer frame"; it now says it must be a layer position.
- `docs/reference/commands.md` lists every CLI command and MCP tool with its mode, how it runs and its parameters.
  It is generated from the command catalog (`scripts/update-commands.sh`) and a test fails when it is stale; the
  hand-written tables in the automation guide had fallen behind.
- **`ui frame [frame]`** renders the viewer picture at a timeline frame (the playhead by default) to a PNG and
  returns its path, without moving the playhead, so agents can look at their edits. It is the same capture as
  Ask's *attach viewer frame* (which had no command until now).
- `timeline get` also returns `transitions` and `markers` (sections); the text format adds one `TRANSITION` and
  one `MARKER` line each. Agents could not see the transitions they had added.
- Fix: `bashcut-mcp` sent list and text results (`timeline get --format text`, `review run`, `media list`,
  `ui seek`…) as `structuredContent` (first as the value, then as `null`), which MCP clients such as Claude Code
  reject; they are now text only and the field is left out.
- `clip speed` and `clip speed-curve` report `shortened: true` when a `keepDuration` change still had to shorten
  the clip because its source ran out.
- Fix: a plugin's file option (VieNeu's *Clone voice from*) squeezed its buttons to "C" in narrow panels; the file
  name and *Choose… / Clear File* now sit on their own lines.
- **Speed ramps** (CapCut Curve): Inspector › Speed › Curve and the clip menu offer Montage, Hero time, Bullet
  time, Jump cut, Flash in and Flash out with a preview of the curve; custom points through `clip speed-curve`
  or the `setSpeedCurve` operation. The clip keeps its source and its length follows the average speed; split and
  trim keep the ramp on the same source; linked sound follows; clips show 〰. Built from short scaled pieces, so
  no keyframe system is needed.
- **Reverse**: Inspector › Speed and the clip menu play a video clip backwards (with its linked sound) from a
  reversed copy rendered into the project's `reversed/` folder as a job; *Play Forward* restores the original.
  New `setSource` operation and `clip reverse` command; reversed clips show ◀.
- **Settings › Storage**: sizes of installed plugins, each plugin's data and downloads, the saved plugin catalog,
  this project's preview proxies and the audit log, with *Free Up* for what can be downloaded or made again and
  *Delete…* for a plugin's data (after a confirmation). New `storage get` and `storage clear` commands.
- **Plugin actions for agents**: agent instructions explain list → select → run → `jobs status`; the agent
  session context lists installed actions with their conditions and parameters; and `bashcut-mcp` lists one
  `bashcut_action_<id>` tool per installed action (input schema = its parameters), run through `plugins run`.
- **Core plugin `bashcut.audio-analysis`** ships inside the app (`Contents/Resources/Plugins`): `audio.loudness`
  (BS.1770-4 integrated loudness, EBU loudness range, 4× true peak) and `audio.beats` (spectral-flux onsets,
  autocorrelation tempo, dynamic-programming beats) with AVFoundation and vDSP. Loudness-normalized export and
  **Detect beats** now work without installing anything; installed providers with a higher priority still win.
  Built by `scripts/run.sh` and the Xcode project (`Plugins/audio-analysis/`).
- **Signed plugins**: registry archives signed with ed25519 (over their SHA-256) show *Signed by BashCut* or
  *Signed by <publisher>*; unsigned ones show a warning, and a signature that matches no key is refused. The BashCut
  key is compiled into the app; the registry cannot add first-party keys.
- **Yanked plugin versions**: a registry version marked `yanked` is never offered; users who have it see why, and
  Updates offers the newest good version.
- **Daily plugin update check**: opening a project checks the registry once a day (Settings switch, on by
  default); the Plugins button and menu show how many updates wait. Nothing installs without the user.
- **App Store channel**: sandboxed builds run only the plugins inside the app (no Browse, Updates or Install
  Plugin…, no user or project plugin folders). A bundled plugin now loses only to a higher version of itself.

- Plugins › Browse: the refresh button bypasses GitHub's 5-minute CDN copy of `registry.json`, so a just-published
  plugin shows at once; an empty list now says whether nothing is published, nothing matches or no plugin provides
  the capability yet.
- Fix: releasing the speed slider recorded the change twice, so one undo seemed to do nothing. Setting a clip to
  the speed it already has is no longer an edit.
- **Change speed** like CapCut: a clip's length now follows its speed (2× halves it, 0.5× doubles it) and later
  clips on its layer, and on its linked sound's layer, move with it; "Change clip length" off keeps the old
  behaviour. Linked picture and sound change together, and a clip is shortened to fit its source. Inspector ›
  Speed has presets (0.25×–4×), a slider and a field (0.1×–16×), the clip menu has a Speed submenu, clips show a
  "2×" badge, and **Speed up / Slow down / Reset speed** are editor actions. New `setSpeed` operation and
  `clip speed` command.
- **Plugin preflight**: before the install approval, BashCut probes the plugin's dependencies and labels each one
  *Available on this Mac*, *Installed during setup* or *Not available on this Mac*; a plugin that needs something
  this Mac lacks and cannot install is refused with a plain explanation, and the space estimate counts only what
  is missing. Installed plugins use the same labels instead of raw probe errors. Changing `pluginRegistryURL` no
  longer needs a restart.
- **Plugin install UX** (plugin API 3): dependency recipes run as a job with a progress bar (`::progress` lines),
  output and Cancel, in the plugin's filtered environment and process group; the approval shows the space needed
  and refuses when the disk is too full; **Install Dependencies…** (`plugins setup`) repairs a failed or cancelled
  setup; **Remove with Data** (`plugins remove --data`) also deletes the plugin's `BASHCUT_PLUGIN_DATA` and
  `BASHCUT_PLUGIN_CACHE` folders. Options gain `choiceLabels` and a `file` type with a file panel, and the Voice,
  Text and Audio panels show the selected provider's options. Trust now pins every file in the plugin folder.
  Development builds accept a `file://` registry and relax trust for symlinked dev plugins.
- Plugin providers now receive their plugin's option values as `options` with capability requests (such as the
  voice for `voice.synthesize`), and dependency commands may leave out `arguments`. First provider using this:
  `bashcut.vieneu-tts` (VieNeu-TTS v3 Turbo) in `bashcut-plugins`.
- **Plugin registry**: Plugins › Browse and Updates install and update plugins from the static `registry.json` in
  `dongnguyenvie/bashcut-plugins` (no server). Downloads are checked against the registry SHA-256, unpacked into a
  staging folder, validated and shown for approval before anything runs; updates keep the previous copy until the
  swap succeeds. Installed › Remove uninstalls user and project plugins. Panels without a provider offer
  **Find a plugin…**. New commands: `plugins search`, `updates`, `install`, `remove`. `scripts/run.sh` now writes the
  real app version into the development bundle.
- **Localized plugin text**: plugin `name`, option `title`/`help` and action `title`/`confirm` take a string (English)
  or a language map such as `{"en": "Opacity", "vi": "Độ mờ"}`, replacing the `titleVi` fields. BashCut shows the
  interface language, then the base language, then English.
- **Plugin API 2: actions, hooks, options, sessions and trust.** Plugins can add actions to the Plugins menu,
  toolbar, clip/track/timeline/media context menus, library panels and inspector tabs (`contributes.actions`, with
  `when` conditions, native parameter sheets and shortcuts) and subscribe to 19 editor events
  (`contributes.hooks`: project, edit, selection, playback, import, capability, export and job events; debounced,
  rate-limited and notify-only). A result proposes operations and the plugin's own `pluginData` entry; the app
  validates them and commits one undoable edit by the new `plugin` author. Hook edits wait for review (toolbar
  badge, `plugins proposal`) unless Settings › **Apply plugin hook edits without review** is on; Settings ›
  **Run plugin hooks** stops all hooks. Manifests can declare `options` (per user or per project) and
  `"transport": "session"` for one long-lived NDJSON process with progress and cancel. Plugins now run only after
  the user trusts their exact files (SHA-256 pins; installing pins them) and can be turned off per plugin or per
  hooks; `minApiVersion`/`maxApiVersion` mark outdated plugins. New commands: `plugins actions`, `run`, `hooks`,
  `proposal`, `options`, `option`, `set`; `ui actions`/`ui action` include plugin actions. Example plugin:
  `Fixtures/plugins/example.toolkit`. See `docs/guides/plugins.md`.
- **Adjustment layers** replace the New Project "Style preset" setting, which was stored but never used. An
  adjustment layer (Add Layer › Adjustment Layer, `layers add --kind adjustment`) holds items with only a color
  grade (look, exposure, contrast, saturation, LUT) that applies to every layer below them while they are on screen,
  like adjustment layers in CapCut or Premiere; captions above them stay ungraded and hiding the layer bypasses it.
  Filters › Add adjustment and `adjustment add` add one over the selected clip or 3 seconds at the playhead; a
  look or LUT with nothing selected does the same. New look: Vivid.
- **Style kits** (Filters › Style kits, `style apply`): one undoable edit adds a full-length adjustment with the
  kit's look (replacing an earlier kit's) and sets the kit's preset on every caption; titles, place cards and
  other presets keep theirs.
- **Custom looks and kits** live in the project (`looks`, `styleKits`) and show in the Filters library:
  `looks save` (from an item's grade and/or values), `looks delete`, `style save`, `style delete`. `adjustment add`
  takes `--exposure`, `--contrast`, `--saturation`, `--lut-strength` and `--lut`; commands gained a `number`
  parameter type with ranges published to MCP. `timeline get` lists `luts`, `looks` and `styleKits`.
- **Generated JSON Schema**: `docs/reference/project.schema.json` and `schema get` come from `ProjectSchema`,
  built from the same declarations validation uses (`TrackKind`, `ItemProperty`, `ColorGrade`, `TextPreset`).
  `scripts/update-schema.sh` regenerates it; a test fails when it is stale. `ProjectMigration` is the registry for
  future upgrade steps.
- **Project format reset to `bashcut.project/1`** (nothing is released yet): no migrations; text items use
  `textPreset` instead of `style`; tracks always store `name`; the project-wide `style` field and
  `project create --style` are gone. Agent instructions list color keys and ranges and warn that `setProperties`
  replaces the whole `color` object.

- Agent dock tabs: each tab shows its provider icon, the close button sits inside the tab (shown on hover or
  selection), the selected tab is outlined in cyan, API is a tab like the others, header buttons highlight on
  hover, and the terminal has a small inset instead of touching the dock edge.
- Sample project for contributors: `scripts/sample-project.py` generates synthetic media with ffmpeg and builds
  `build/sample-project/bashcut-sample` through the `bashcut` CLI, with every timeline case (linked clips, LUT,
  reframing, dissolve, freeze frame, 2× speed, gap, 4K HEVC proxy, picture in picture, captions, locked, hidden
  and muted layers, voiceover warning, music with beat grid and ducking, SFX, sections, an agent-changed clip),
  then checks it end to end (`check` re-runs the checks). See `docs/guides/sample-project.md`.
- Validation now rejects a clip's `color.lut` that is not a catalog ID (an object was accepted and then silently
  ignored by the engine).
- Faster playback and timeline drawing: the play controls and time under the viewer are their own view, so the
  editor no longer re-renders every playback frame; the timeline's current time is its own small label instead of
  redrawing the layer header; new filmstrip thumbnails redraw only the visible filmstrip rows; clips look up
  their media by ID; the beat grid is one path. The playhead is only written when it moves, and state used only
  for reference (`timelineGestureActive`, the zoom anchor) is no longer observed by views. The viewer no longer
  publishes itself to Control Center's Now Playing, which polled the player on the main thread during playback.
- The timeline arrow keys are editor actions: `left`/`right` run `playhead.previous-frame`/`playhead.next-frame`,
  and ⇧← / ⇧→ run the new `playhead.back-second`/`playhead.forward-second`, so `ui action shift+right` works.
- A CapCut-style timeline:
  - **Playhead:** a red playhead with a grip that you drag (on the grip, the line or anywhere on the ruler) with a timecode label, snapping and edge autoscroll. ← / → step frames, and playback turns the page.
  - **Hover and dragging:** hovered clips light up with trim brackets and move/trim cursors. Dragging a clip shows a see-through copy where it would land with a closed-hand cursor, a cyan target line, a yellow snap line, and a label with the new start, duration or change.
  - **Clips:** durations on clips; filmstrip thumbnails on the taller main layer (from proxies when present); clearer colors per layer and icons instead of emoji.
  - **Clip menu:** right-click Split, Delete, Lift, Freeze frame, Change framing, Unlink audio and Lock layer (new actions `clip.freeze`, `clip.change-framing`, `clip.unlink-audio`).
  - **Gaps:** hatched gaps on Main that can be selected and deleted (`timeline close-gap`).
  - **Drop media:** drag from the Media and Audio panels or from Finder onto a layer.
  - **Layer header:** pinned on the left with hide, mute and lock switches (`layers set`). Hidden layers leave preview and export, muted layers are silent and stop ducking music, and locked layers refuse edits.
  - **Performance:** the playhead, guides and labels are separate overlay views, so playback and scrubbing no longer redraw the whole timeline.
  - **Behavior change:** clicking a clip now selects it without moving the playhead.
- Timeline zoom works like CapCut: pinch on the trackpad or ⌘ + scroll zooms around the pointer, the buttons and ⌘= / ⌘− zoom around the playhead, and the frame under the pointer or playhead stays in place instead of the view jumping. The slider is logarithmic, zoom now ranges from 1 to 600 pixels per second (a whole long video down to single frames, with frame ticks on the ruler), and a new **Zoom to fit** button (⇧Z in the timeline, `timeline.zoom-fit`) shows the whole timeline. `ui view --zoom` accepts the new range and `--zoom-anchor <frame>`.
- Reorganize and rewrite the documentation: `docs/README.md` is the index; guides (`docs/guides/automation.md` with the full command list, `docs/guides/plugins.md`), reference (`docs/reference/project-format.md`, `docs/reference/third-party.md`), status (`docs/status/implementation.md`, `docs/status/mockup-parity.md`) and the design specs, all brought up to date with the code. `docs/extension-boundaries.md` is folded into the architecture spec.
- Open projects from Finder: double-click or **Open With → BashCut** on a `project.bashcut.json`, or drop the file or its project folder on the Dock icon, whether or not BashCut is running. BashCut is listed as an alternate app for JSON files and folders, never the default. Unsaved changes still get the discard prompt.
- M0 accepted on real DJI footage: `bashcut-bench` now measures scrubbing the way the viewer does (AVPlayer exact seeks) and can preview through proxies (`--proxies`); 20 HEVC clips play with no dropped frames, scrub at p95 19.6 ms (8.9 ms with proxies) and export at 9× real time (results in `docs/status/implementation.md`). The viewer scrubs with chase-time seeking: while one exact seek decodes, newer playhead positions only replace its target, so dragging never queues stale frames.
- Make preview proxies for heavy footage (M-5). Importing HEVC, larger-than-1920 px or high-bit-rate video now queues a small H.264 copy (at most 960 px, a keyframe every 10 frames, same frame times) in `.bashcut/proxies`; proxies are made one at a time in the background, the viewer switches to each one as it is ready and exports keep using the originals. `media proxy [MEDIA_ID] [--force]` and the Media panel's **Create Preview Proxy** menu make one by hand, the media tile shows "Proxy" or "Making proxy…", and `media list` reports each media's proxy state (46 tools).
- R6, contributing guide: `CONTRIBUTING.md` explains the build layout and gives a one-file template (with its registry and test) for agent providers, model adapters, commands and UI actions, plugin capabilities and timeline formats. R6 is done, which completes the refactor plan.
- R6, build and tests: `Package.swift` is the single source of targets and `project.yml` links its library products instead of redeclaring the core modules; `scripts/verify.sh xcode [build|test]` builds or tests the generated Xcode project. Tests are split into one target per module (`Tests/BashCut<Module>Tests`, and Project/Plugin/Import/Interchange in the core package) with shared fixtures (`BashCutTestSupport`, `BashCutProjectFixtures`) and an apply→undo→redo round trip for every edit operation. The core package no longer declares the unused snapshot-testing dependency, so `swift test` stops rewriting its `Package.resolved`.
- R5c: timeline formats are `TimelineExporter`s (OpenTimelineIO, SubRip) and `TimelineImporter`s (legacy edl.json) listed in `TimelineFormats`; OTIO export and EDL import go through them. The import report sheet is generic (`TimelineImport`: counts, mismatch note, warnings) and `edl import` adds `sourceDuration` to its report. R5 is done.
- R5b: the engine reads media through a `MediaSource`. `ProxyMediaSource` (the default) uses `.bashcut/proxies/<media id>.mov|.mp4` for preview when present and always the original for export; `RenderEngine.build` takes a `purpose`. `CompositionBuilder` now keeps opened assets and their loaded tracks across builds (up to 64, least recently used dropped, reloaded when the file's date or size changes), so preview rebuilds after an edit no longer reopen every clip.
- R5a: plugin capabilities are `CapabilityAdapter`s (transcription, beats, loudness, voice synthesis, one file each) run by `CapabilityService.run`, which owns validation, provider resolution, the request folder and provenance. Plugin calls go through a `PluginTransport` protocol (the process runner is the one-shot transport), so tests and future session transports plug in without changing the service.
- `scripts/run.sh` signs `build/BashCut.app` with a stable identity (`BASHCUT_SIGN_IDENTITY`, else the first Apple Development identity; ad hoc with a warning when there is none), so macOS stops asking for Desktop folder access after every rebuild. SwiftPM resource bundles now go in `Contents/Resources`.
- R4b, step 1: move editor view state (timeline zoom and reveal, snapping, safe area, agent dock, library panel, Inspector tab and every editor sheet flag) out of `ProjectDocument` into a tested `EditorUIState` in `BashCutDocument`; `LibraryTab` moves there too, and its match with the `ui.panel` choices is now a test instead of a startup assert. No behavior change.
- R4b, step 2: the viewer (program and comparison players, playhead, composition rebuilds, color compare) moves into `PreviewController` in `BashCutDocument`, tested with a counting fake engine.
- R4b, step 3: `ExportController` in `BashCutDocument` owns the export queue, the last export report (moved into the library with its `export.status` JSON), export history, the loudness project patch and OTIO writing; the document keeps only panels, messages and the edit.
- R4b, step 4: `FileSyncController` in `BashCutDocument` owns saving against the last bytes read, autosave, the folder watch and disk-conflict state; the document applies the reloads it reports. Tests cover saves, outside edits (reload and conflict) and conflict resolution.
- R4b, step 5: `SettingsModel` in `BashCutDocument` holds Settings preferences (workspace, default agent, agent edit and external-agent switches, export auto-approval, default export preset, interface language) and recent projects. Each change is saved at once under the existing `UserDefaults` keys, so current preferences carry over.
- R4b, step 6: `AutomationController` in `BashCutDocument` owns the command registry with its audit log, the socket server and the external-agent token file; the document registers its handlers on it. `CommandRegistry.author(for:)` reports who a token edits as.
- R4b, step 7: `AppServices` (render engine, settings, automation endpoint) is the composition root; `AppServices.live()` builds the app's and `ProjectDocument(services:)` creates its per-project controllers from it. R4 is done: `ProjectDocument` went from 64 to 28 stored properties and keeps history, the single `commit` and the command handlers.
- Replace the agent dock's "Resume session ID" field with **Continue Claude/Codex** and **New conversation** buttons; BashCut keeps finding and saving the last conversation per project on its own, and users never see session IDs.
- Fix fixed-size sheets (Plugins, Doctor, History, agent changes, external changes, skills and memory) floating their content in the middle when it is short; content now starts at the top and the empty Plugins state fills the sheet.
- Fix the Media panel's source picker label wrapping one word per line in the narrow library panel.
- Close the remaining UI-only gaps: `luts import` (Filters, Import .cube…), `edl import` (Welcome, Import from edl.json…), `project recents`, `doctor run`, `plugins health`, `knowledge get` / `knowledge memo` / `knowledge skill`, and `voice speak --keep-takes` to keep every take and place the chosen one. New actions: show/undo/dismiss the agent change notice, open or reveal the last export, clear recent projects; `ui view --inspector` switches Inspector tabs (45 tools).
- Fix a crash when importing a .cube LUT: the copy combined `.atomic` with `.withoutOverwriting`, which Foundation rejects with a trap.
- Fix the app no longer answering automation requests while an agent-started open panel or alert was showing (`ui action cmd+o`).
- Let agents do everything the editor's buttons and shortcuts do: every toolbar button, menu item and keyboard shortcut is a `UIAction` (ID, title, shortcuts) that the views bind to and `ui action <id|shortcut>` runs through the same code (`ui action cmd+b` splits, `ui action timeline.zoom-in` zooms). `ui actions` lists them with their shortcuts and enabled state. `ui view` reads and sets timeline zoom, snapping, safe area, color compare and the agent dock, and scrolls the timeline to a frame (`--reveal`). `ui source <media>` opens the source viewer with in/out marks, and `ui select --track` selects a layer (37 tools).
- Add ⌘= / ⌘− and zoom buttons to the timeline; Delete, Shift-Delete and `s` in the timeline are listed actions too.
- `context get` reports `dirty`, `conflict`, `busy`, `saving` and the selected layer; `ui open external-changes` shows the disk-conflict sheet. Boolean CLI options accept `on`/`off`.
- Agents can no longer approve a plugin install from the `plugin-install` sheet; like export approval, they can only cancel it.
- `export status` describes the running export while one renders (`job`, `step`, `progress`, `preset`, `path`, `includedSRT`), with the previous receipt under `lastExport`; exports no longer write an empty `.srt` when the timeline has no captions.
- Rewrite older `../../…` media paths that point into the project's linked `footage` folder (or any top-level folder link) to `footage/<file>` when a project opens, as one undoable "Relink media paths" edit that is saved with the project.
- Let agents drive every dialog like the user: all alerts and open/save panels go through `ModalCenter`, and every sheet and popover is reported too. `ui dialog` lists open dialogs with stable option IDs, `ui respond <option> [--path <file>]` answers the topmost one (a path fills a file panel), and `ui open <dialog>` shows a sheet such as Settings, Export or Doctor. The export approval sheet can only be declined by agents; approving stays with the user unless confirmation is turned off in Settings (33 tools).
- Add a Settings switch, "Run agent exports without confirmation" (off by default), that runs privileged agent commands (`export start`, `export otio`) at once instead of showing the approval sheet; they answer `approval: "approved"` and are audited as auto-approved. Only the user can change it in Settings.
- Queue exports in the background (E-1): starting an export while one renders queues it instead of refusing, in the app and through `export start`. Exports render one at a time from the project as it was when requested; the status bar shows the current step, progress and queued count, `export status` lists the queue with job IDs, and `jobs status`/`jobs cancel` now cover exports as well as plugin jobs.
- Add the `BashCutDocument` library with `JobCenter` (one job list for capability calls and exports), `ExportRequest`, `ExportPipeline` and `ExportQueue`, covered by tests with a fake render engine.
- Make agent terminals and model APIs pluggable: each terminal program is an `AgentProvider` (Claude, Codex, Shell) and each model API a `ModelAdapter` (Responses, Chat Completions, Anthropic), registered once; the dock menus, Settings picker, resume bookmarks (now keyed by provider ID, same file format) and session discovery come from the registries.
- Launch terminals with an allowlisted environment instead of the whole app environment: locale, home, proxy and certificate variables plus each provider's own (`CLAUDE_*`, `CODEX_*`, `OPENAI_API_KEY`); Claude still never receives `ANTHROPIC_API_KEY`.
- Store media picked from the linked `footage` folder (or any top-level folder link) as `footage/<file>` instead of a `../../…` path into the link's target, so projects keep working when moved with their footage link.
- Add `project create`, `project open` and `project save` CLI/MCP commands sharing the wizard, open and save code; they never show modal dialogs and refuse to drop unsaved work without `--save-current` or `--discard-current` (30 tools).
- Let agents outside BashCut edit without copying a token: the app writes a 0600 automation token file that the CLI and MCP read automatically, attributed to a new `agent` author that survives project switches; a Settings switch turns it off or rotates it. Exports still require in-app approval.
- Keep overflow layers in creation order (after the last layer with the same role), add new video layers behind text layers, and name the moved layer in band errors.
- Add an Edit menu (Cut, Copy, Paste, Select All) so ⌘X/⌘C/⌘V/⌘A work in text fields and the embedded Claude, Codex and Shell terminals, and a Copy/Paste/Select All right-click menu on terminals.
- Add a `media import` CLI/MCP command that adds a media file through the same probe as the Import button and can place it on a layer (27 tools).
- Add a shared debug log (`~/Library/Logs/BashCut/debug.log`) written by the app, CLI and MCP bridge: launches, project opens and layer repairs, committed and rejected edits, layer placement decisions, media imports, timeline gestures and automation requests.
- Make each left-rail library tile clickable across its whole area, not only on the icon and label, and add a `ui panel` CLI/MCP command to open a panel (26 tools).

- Enforce layer rules in core validation: visual layers stay above audio layers, exactly one undeletable main layer, no overlapping items on one layer, and no audio media on visual layers. Older projects are repaired when opened.
- Place and move clips CapCut-style through a shared `LayerPlanner`: an occupied range spills onto the next free layer of the same role or a new layer next to it, with linked sound following. Imports, the library, timeline drags and overlapping SRT cues all use it.
- Add `layers add`, `media place` and `timeline move` CLI/MCP commands (25 tools) backed by the same code as the UI.
- Fix the layer up/down buttons moving audio layers the wrong way on screen, and keep layers inside their visual or audio band.

- Declare every automation command once in `CommandCatalog.specs` (name, mode, parameters, CLI binding, sync/job/approval). The registry validates requests against the spec before handlers run (types, ranges, choices, defaults, unknown parameters); handlers are `async`. The `bashcut` CLI parser, the 22 MCP tools and the agent instructions are generated from the same specs, and a consistency test guards them.
- Fix `bashcut_timeline_apply` rejecting calls without `label`: the schema now advertises the `"Agent edit"` default and the server applies it.
- Agent instructions no longer name fixed track IDs (`v1`, `t1`); they tell agents to read track IDs and roles from `bashcut timeline get`. `bashcut help` lists every command's usage, and CLI argument errors print that command's usage.

- Route every history mutation (UI, automation, model API, captions, LUTs, generated results, external reloads) through one `ProjectDocument.commit` that enforces conflict/busy/revision rules and records agent diffs consistently; `history` is now read-only outside that choke point.
- Look tracks up by role (`Project.track(role:)`, `TrackRole`, `placementOperations`) instead of fixed `v1`/`t1`/`a2`/`a3`/`a4` IDs, so renamed, reordered or added layers keep working; the audio library lists the project's real audio tracks.
- Serialize `EditOperation` in one `"op"`-keyed codec in core, shared by agents, model APIs and the history journal. Journals written by earlier builds are discarded with the existing "History could not be restored" warning; project files are unchanged.
- Cap undo history at 200 steps, hide the `Deque` storage behind `canUndo`/`undoEntries`/`lastUndo`, and expose snapshot inverses through `HistoryEntry.before`.

- Make plugin calls cancellable without blocking Swift's cooperative pool: providers start in their own process group, cancellation and timeouts terminate the whole group, including helpers they spawned.
- Serve automation clients concurrently on a dedicated accept thread and client queue, so an idle or slow client no longer stalls other agents.
- Merge continuous Inspector input (slider drags, typing) on the same field into one undo step through history coalescing in core.
- Add `docs/specs/10-refactor-plan.md` with the structural audit and refactor rounds R0–R6.

- Route every plugin call through a shared `CapabilityService` module used by the Voice, Text and Audio panels, normalized export and automation, so provider resolution, health checks, output confinement and provenance are identical for users and agents.
- Add authenticated `captions generate`, `beats detect` and `voice speak` CLI/MCP commands that run as cancellable background jobs and apply one undoable agent-attributed edit, plus `plugins list` and `jobs status/cancel` (22 MCP tools).
- Use `grep` instead of ripgrep for `scripts/verify.sh` failure summaries, since ripgrep is not a required tool.

- Persist the latest 20 export metric reports per project, restore the latest report after reopen and compare duration, size, cuts, captions, tagged speech coverage and LUFS with the previous export in UI and automation status.
- Discover matching local Claude and Codex sessions without loading full histories, persist their IDs per canonical project and automatically bookmark newly launched terminal sessions.
- Record voiceover directly from the macOS microphone as a project-local 48 kHz mono WAV, show elapsed time and input level, validate it and insert it undoably at the playhead.
- Attach a bounded current-viewer PNG from ⌘K to Claude/Codex terminals by local path or to configured model APIs using provider-native multimodal request bodies.
- Let the Agent dock detach into a resizable window while preserving live Claude, Codex, Shell and API sessions, then reattach cleanly when the project closes.
- Show red timeline badges when voiceover is less than 0.3 seconds from tagged speech, with the same layer-aware rule exposed through Review and agents.
- Add an undoable Preserve Audio Pitch speed control, using AVFoundation spectral processing or intentional varispeed in both preview and export.
- Add rendered Place Card, Hook Title and Chapter Card presets to the Text library and Inspector, sharing the same cached Core Text output in preview and export.
- Add a synchronized Viewer Before/After split backed by a non-mutating comparison composition that bypasses color adjustments and LUTs.
- Add deterministic Wide/Medium/Close/left/right Change Framing presets in core and Inspector, using the same validated properties available to agents.
- Add optional provider-based two-pass loudness normalization: measure a temporary mix, apply target gain with a −1 dBTP ceiling, verify the final export, persist mix gain/provenance undoably and expose results through UI, CLI and MCP status.
- Add a three-take Voice workflow with provider-scored or pacing-scored results, isolated audio preview, best-take selection, legacy single-output plugin compatibility and cleanup of discarded generated assets.
- Add frame-accurate automatic music ducking under tagged Dialogue and Voiceover, with track-level level/attack/release controls and one shared preview/export gain envelope that composes with clip fades and volume.
- Add an external-change comparison sheet covering project settings, media, tracks and stable timeline-item additions, removals and modifications before choosing which version to keep.
- Add Footage, Project and Shared media-source filtering with symlink-aware footage classification.
- Add modular legacy `edl.json` import with cut, timing, picture-borrow, dialogue, transform, tag, split-subtitle, voiceover and section mapping plus a post-import comparison report.
- Add modular OpenTimelineIO export with overlap-preserving lanes, gaps, text generators, markers, speed effects and BashCut metadata, available from UI and privileged CLI.
- Add stable undoable dissolve, whip, blink, zoom, spin, shutter and wipe transitions rendered identically in preview/export, with UI duration controls and agent operations.
- Add project-scoped `.cube` 3D LUT import/catalog, validated and undoable clip application/strength, agent operations and shared Core Image preview/export rendering.
- Add an embedded `bashcut-mcp` stdio server using the official MCP Swift SDK, with 16 structured tools and ephemeral Claude/Codex session configuration over the existing authenticated automation socket.
- Add stable, undoable section markers with an editable timeline band, boundary dragging and Claude/Codex wire operations.
- Record and display source resolution, frame rate, duration and audio presence, with offline media badges.
- Add reciprocal linked A/V items for video sound, atomic paired move/trim/split/slip/roll/delete, Inspector unlinking and agent wire support.
- Add deterministic magnetic Main-track reorder with linked Dialogue synchronization and agent wire support.
- Add debounced media hover-scrubbing, event-driven project-file monitoring and rendered freeze frames controlled from the Inspector.
- Persist separate Claude/Codex resume bookmarks per project and add context handoff between embedded terminal providers.
- Resolve `@assets/...` media consistently through the configured workspace with traversal confinement across library, plugins, preview and export.
- Added a first-launch welcome screen with persistent recent projects and stale-file cleanup.

- Upgrade projects to schema v2 with dynamic ordered video/image, text and audio layers, layer controls, vertical timeline scrolling and compositor ordering across text/video tracks.
- Reuse AV assets and composition lanes when building large timelines.
- Add before/after agent diffs, ◆ markers, Undo/Show Changes UI and history restoration for Claude, Codex and model API edits.
- Add Agent Knowledge for shared project memo and skill management across Claude and Codex.
- Launch Codex idle on GPT-5.6-Luna/low with a socket-scoped permission profile and a stable app-support workspace, avoiding security-scoped project-directory stalls.
- Add an out-of-process plugin manifest/catalog, a reviewed installer for optional capabilities and dependencies, dependency health checks and a bounded process RPC runtime with a filtered environment.
- Connect the Voice panel to replaceable `voice.synthesize` providers with project-level selection, output confinement, audio validation, provenance and undoable insertion.
- Connect Auto Captions to replaceable `captions.transcribe` providers with source/language input, confined SRT output, provenance and atomic replace or append.
- Add replaceable `audio.beats` detection, validated undoable beat grids, timeline rendering, beat snapping and agent wire support.
- Add persistent Settings for workspace, default agent, agent edit permission, export preset and UI language, plus Doctor checks for agent CLIs, the automation socket, project structure and plugin health.
- Add capability-based provider declarations and undoable project overrides so voice, transcription and other optional providers can be replaced without changing feature code or timeline data.

- Add mockup-based export options for TikTok, YouTube 1080p/4K, Quick Draft and ProRes, with real bitrate/container settings, background progress/cancellation, optional SRT, post-export receipts and `bashcut export status`.
- Add token-gated `bashcut export start` for embedded Claude/Codex/Shell sessions, with a concrete in-app approval sheet; denied requests write nothing and approved requests use the normal export pipeline.
- Add a native New Project wizard with canvas/resolution/FPS, content language, style, destination and optional footage reference. Publish complete folders without overwriting existing paths; preserve the open document on failure.
- Document functional gaps against the HTML mockup in docs/status/mockup-parity.md.

- Add off-main-actor stereo waveform analysis and bounded memory/disk caching, timeline peak drawing aligned to source trim/speed, refresh/progress/error controls and generated-audio regression tests.
- Fix waveform invalidation by reading fresh file attributes instead of cached URL metadata.

- Add UTF-8 SRT import/add/replace/export to the Text library and CLI, with frame conversion, bounded parsing, one-step undo and subtitle regression tests.

- Add atomic rolling trims and source slips in core, Inspector, timeline gestures and agent wire commands; Shift-Delete lifts without ripple. Add mixed-FPS, bounds and undo regression tests.

- Rebuild the native editor around the mockup: library rail, source viewer with In/Out and insert/overwrite, Inspector tabs, scroll/zoom/snap/drag timeline, safe area, review and history.
- Add text presets, emoji text stickers, color/opacity/audio controls, render-value validation and regression coverage for source placement.
- Add SwiftTerm Claude/Codex/Shell sessions, authenticated local socket, bundled CLI, author badges, atomic API edits and metadata-only audit records.
- Add configurable Responses/Chat Completions/Anthropic model clients, Keychain credentials, editable Python/Shell generation and explicit script execution.
- Fix the app/CLI executable collision on case-insensitive macOS disks, thumbnail layout, timeline hit testing after scroll, and stale model generation handling.
- Expand English/Vietnamese resources and refactor command/render/edit functions for strict SwiftLint.

- Bootstrap the separate BashCut repository, XcodeGen configuration and SwiftPM build path.
- Add lossless schema-v1 project data, validation, atomic edits, revision checks and session undo/redo.
- Add a native editing harness and shared AVFoundation compositor for reframing, Vietnamese captions, audio and H.264 export.
- Add core and engine tests, generated media fixtures and verification scripts.
- Add M1 project persistence: autosave/recovery, saved undo/redo, external-file reload/conflict handling and storage tests.
