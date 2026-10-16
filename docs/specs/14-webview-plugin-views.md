# 14 — Webview plugin views (research, #406)

**Status: research, revised for plugin API 11 (2026-10-16).** **Recommendation: no-go for now; build it only when a
named plugin needs to draw something declarative views cannot, using the design below.** Declarative views
(`contributes.views`, [plugins guide](../guides/plugins.md) › Plugin panels and views) stay the default and the only
kind shipped.

The first version of this note (2026-10-13) was written against API 8. Since then API 10 took `views[].kind` for
`panel`/`tool`, and API 11 added `window` views, `split`, `nav`, `grid`, grid drag-to-download, `colorPicker`,
`fontPicker`, `viewUpdate` pushes and overlays. This revision re-grounds the design on those, re-measures the cost
with a throwaway prototype, and adds file access, JavaScript injection and the process model to the security review.

## What was asked

A `webview` view kind: a `WKWebView` that shows a plugin's own HTML, with no network by default, files only from the
plugin folder, and a narrow bridge (`bashcut.call`, `bashcut.event`) over the same host channel and allow-list as
declarative views. Plus a security review, the memory and CPU cost per view, and a go/no-go.

## What declarative views already cover (API 11)

| Need | Covered by |
|---|---|
| Browsers and pickers with a sidebar, results and an inspector | `window` location + `split` (2–3 columns) + `nav` + `grid` with load-more |
| Libraries of thumbnails, sounds and takes | `grid`, `list`, `audio`, `image`, `imageCompare` |
| Online results placed on the timeline | `drag: "download"` tiles, `libraryItem` answers |
| Forms and settings | `textField`, `textArea`, `toggle`, `picker`, `slider`, `colorPicker`, `fontPicker` |
| Progress and live status | streamed `render` events, `viewUpdate` lines outside a request |
| Marks on the timeline and viewer | overlays (`range`, `marker`, `region`) |

What still cannot be drawn: free drawing and direct manipulation (a node graph, a curve or envelope editor, a
waveform editor with handles), custom charts, rich text editing, and a live preview of HTML content (for example a
HyperFrames composition while it is designed). None of the plugins in `bashcut-plugins` asks for these today; the
most likely first request is the HTML-composition preview, since the `graphics.render` plugins already produce HTML.

## Design (when it is built)

### Manifest

`views[].kind` is taken (`panel`/`tool`, API 10), so a webview is a view with a `webview` object instead of a new
kind. Everything else about the view (`id`, `title`, `location`, `icon`) stays as it is.

```json
"contributes": {
  "views": [{
    "id": "composer", "title": {"en": "Composer", "vi": "Soạn"}, "location": "window",
    "webview": {"entry": "ui/index.html", "minWidth": 600}
  }]
},
"features": ["views.webview"]
```

| Field | Rules |
|---|---|
| `webview.entry` | A relative path to an `.html` file inside the plugin folder; no `..`, no absolute path, must exist and be pinned by trust |
| `webview.minWidth` | Optional, 320–1600 points |
| `location` | `window`, `dock` or `sheet` only. Not `panel` (225 pt is too narrow to be worth a web process), not `inspector` (rendered again on every selection), not `kind: tool` |

- Needs `apiVersion` 12 and the `session` transport; host feature `views.webview`. At most 2 webview views per plugin.
- A host without `views.webview` lists the plugin as outdated only if the manifest's `features` names it; a plugin
  that also works without it ships a declarative view with the same `id` for older hosts (same pattern as `window`
  with `minApiVersion`).

### Loading and isolation

- A `WKURLSchemeHandler` for `bashcut-plugin://<plugin-id>/<path>` serves files from the plugin folder only: the path
  is standardized, symlinks are resolved, the result must stay under the resolved plugin root, and the host must be
  the view's own plugin id. MIME type by extension from a fixed table; anything else is `application/octet-stream`.
  Files are read from the trusted tree, so a file changed after trust is refused like any other changed plugin file.
- No `file://`: no `loadFileURL(_:allowingReadAccessTo:)`, `allowFileAccessFromFileURLs` stays off. Media the page
  shows (thumbnails, takes) comes through the bridge as `bashcut-media://<token>` URLs the host minted for a file
  the plugin's own view answers already named, never as paths the page chooses.
- `WKWebsiteDataStore.nonPersistent()` per view: no cookies, storage or caches kept or shared between plugins.
- `javaScriptCanOpenWindowsAutomatically` off, no `WKUIDelegate` file panels or `window.open`, element fullscreen
  off, media needs a user action, `isInspectable` only in development builds or with developer mode.
- Every HTML answer carries this Content-Security-Policy header, which the page cannot loosen:
  `default-src 'none'; script-src bashcut-plugin:; style-src bashcut-plugin: 'unsafe-inline'; img-src bashcut-plugin:
  bashcut-media: data:; font-src bashcut-plugin:; media-src bashcut-media:; connect-src 'none'; frame-src 'none';
  form-action 'none'; base-uri 'none'`. No inline scripts and no `eval`: the plugin ships its JavaScript as files.
- A `WKContentRuleList` blocks `http(s)`, `ws(s)`, `ftp` and `file` loads as a second wall behind the CSP (one rule
  per scheme; content rule lists do not accept `|` in `url-filter`).

### Navigation and downloads

- `decidePolicyFor navigationAction` allows only `bashcut-plugin://<own id>/…` in the main frame; everything else is
  cancelled (links, `location.href`, `data:` and `blob:` documents, files dropped from Finder). A later version could
  hand an `https` link to the default browser after a confirmation naming the plugin.
- `navigationAction.shouldPerformDownload` and responses WebKit cannot show are cancelled; no `WKDownloadDelegate`.
  A plugin that saves a file does it in its process, or asks the host through `bashcut.call`.

### Bridge

One `WKScriptMessageHandlerWithReply` named `bashcut` in the page world, and a document-start user script that
defines a frozen `window.bashcut`:

| Page API | Goes to | Answer |
|---|---|---|
| `bashcut.call(method, params)` | The same `PluginViewModel.hostChannel` → `perform` path as a `call` line: `PluginCommandSession.allowedMethods`, author `plugin`, `ownPluginRefusal`, `plugins.invoke` only for `uses`, `cli` | A promise of the command's result or `{code, message}` error |
| `bashcut.event(type, value)` | The plugin's process as `view.event` with `"event": {"node": "page", "type", "value"}` (same queue: one request per view, later events wait, a newer event of the same `type` replaces a waiting one) | A promise of the answer's `message` (any JSON); `state`, `notify` and `close` work as for declarative answers |
| `bashcut.on(name, fn)` | — | `message` (the plugin pushed data), `context` (selection or playhead moved; debounced 120 ms), `theme`, `locale` |
| `bashcut.view` | — | `{plugin, view, locale, theme, state}` at load |

- The first `view.render` of a webview view is sent as today; its answer's `message` (not `body`) is the page's first
  data, so a plugin uses one code path for both kinds. The plugin pushes later data with the existing `viewUpdate`
  line carrying `message` instead of `body`; the host posts it to the page (same 60 ms coalescing and per-plugin
  limits: 512 KiB per update, burst of 20 refilled at 10 a second).
- The host answers only messages whose `frameInfo` is the main frame of the view's own `bashcut-plugin://<id>` origin.
  Bodies are JSON, at most 1 MiB, and at most 50 `call`/`event` messages a second per view; more fail fast.
- Host → page uses `callAsyncJavaScript(_:arguments:in:contentWorld:)` with the payload as an argument, never a
  string built into script source, so nothing the plugin or a project contains is evaluated as code.
- The page never reaches the plugin process or the automation socket directly; there is no port, socket or URL for
  it to reach.

### Lifetime and process model

- WebKit runs each web view's page in its own `WebContent` process (sandboxed by WebKit, stricter than the app's
  own sandbox) plus one shared `GPU` and one shared `Networking` process. The app's main actor only creates the view
  and relays bridge messages.
- The web view is created when its view comes on screen and released when it is hidden or its window closes; a
  window view keeps its last `state` (as declarative window views do), not its web process. At most 3 live web
  views app-wide; opening a fourth releases the oldest hidden one.
- `webViewWebContentProcessDidTerminate` (crash or jetsam) shows "This view stopped" with **Reload**, and counts
  towards the plugin's health like a crashed session; the app and other views are unaffected.

### User control

- Webviews are a per-plugin switch in Settings › Plugins, **off by default** and **not** turned on by
  "Trust plugins automatically" (which is on by default and would otherwise accept new HTML and JavaScript without
  a look). Turning it on is user-only, like Revoke Trust and turning hooks on. With the switch off the view shows
  "This view shows web content. Allow it in Settings" with a button, or the plugin's declarative fallback.
- The view's frame (title bar of the window, dock tab, sheet header) always names the plugin and shows a "web" badge
  that the page cannot cover or restyle, since the page is clipped to its view.

## Security review

| Risk | Mitigation | Measured in the prototype | Remaining |
|---|---|---|---|
| Network (exfiltration, tracking, remote code) | CSP `connect-src 'none'`, `default-src 'none'`, rule list, navigation policy | `fetch('https://…')`, `WebSocket('wss://…')`, an `https` iframe and `location.href = 'https://…'` all blocked; the page stayed on its own URL | WebKit bugs. The plugin process can reach the network anyway, so the page adds no new reach |
| Local files | Scheme handler bound to the resolved plugin root and own id; no `file://` | `fetch('file:///etc/hosts')`, `bashcut-plugin://<id>/../../../../etc/hosts` and another plugin's id refused | Nothing beyond what the plugin process can already read |
| Inline or injected script (a project string, a file name, a transcript ending up in markup) | CSP without `'unsafe-inline'`/`'unsafe-eval'`; host → page only as JSON arguments | An inline `<script>` did not run; `eval` threw `EvalError` | DOM XSS inside the plugin's own page is the plugin's bug, but it can only reach the same bridge the page already has |
| App commands | Same allow-list, author `plugin`, own-plugin checks, `uses` for `plugins.invoke`, rate limit, origin check | Bridge round trip measured (below), no new methods | Same as declarative views and actions |
| Downloads | Navigation policy, `shouldPerformDownload` cancelled | An `<a download>` of a `data:` URL was cancelled as a navigation | — |
| Clipboard | WebKit needs a user gesture; no extra entitlement | `navigator.clipboard.readText()` and `writeText()` without a gesture both refused (`NotAllowedError`) | Copy and paste in the page's own text fields work as in any text field; a page can write the clipboard on a click |
| New windows, popups, fullscreen | Preferences off, no `WKUIDelegate` | `window.open` returned `null` | — |
| Phishing UI (a page drawing a fake BashCut dialog or "Enter your API key") | Off-by-default switch, frame names the plugin, "web" badge | — | **Real and new.** HTML can imitate any UI; declarative views cannot. A key typed there bypasses Settings' `secret` options and the Keychain. This is the main reason for no-go |
| CPU and battery | Release when hidden; WebKit throttles hidden pages | A page spinning in `requestAnimationFrame` used **83 % of a core** while visible and **0 %** when its window was off screen | Nothing public caps a visible page's CPU; it competes with playback decoding and export |
| Review | Trust pins every file by digest | — | Reviewing minified JavaScript is much harder than reading a JSON tree; auto-trust would skip the review entirely without the separate switch |
| Process model | Page in WebKit's sandboxed `WebContent` process | Each view got its own `WebContent`; GPU and Networking shared | A WebKit bug that escapes its sandbox is the same exposure any app embedding WebKit has |

## Cost

A throwaway Swift prototype (not in the repository; source in the session notes) loaded a 200-row list page with a
1 s timer into `WKWebView`s configured as above (custom scheme, non-persistent store, CSP, rule list, reply handler),
on Apple silicon, macOS 15, two runs each with the window off screen and on screen (transparent). Memory is RSS from
`ps`.

| Step | Host process | WebKit helpers | First paint |
|---|---|---|---|
| Before any web view | 24 MB | — | — |
| 1 view | 66 MB (+42 MB: WebKit frameworks, mapped once) | 70 MB: GPU 28, WebContent 29, Networking 12 | 320–370 ms |
| 2 views | 66 MB | 100 MB (+30 MB WebContent) | 95–105 ms |
| 4 views | 67 MB | 161 MB (+30 MB per view) | 86–110 ms each |
| 4 views idle 5 s | 0.0–1.8 % CPU | 0.0–0.1 % CPU each | — |
| All 4 released | 68–70 MB (frameworks stay) | 78 MB: one WebContent kept warm, GPU and Networking stay for the app's life | — |

- Bridge: 1000 sequential `bashcut.call` round trips (echo, no command) took 252 ms with the window on screen
  (0.25 ms each) and 641 ms off screen (WebKit throttles hidden pages). Not a bottleneck; the command behind a call
  costs far more.
- A declarative view for comparison: the plugin process and its JSON tree, drawn by the app's own SwiftUI. Measured
  with `BASHCUT_PERF=1 swift test --filter PluginViewSessionPerfTests` on the same machine: a 10-component round trip
  p50 0.3 ms, the largest 2000-component view p50 22 ms, a host call 0.06 ms, the main-actor timer late p99 2.3 ms
  while an inspector view follows the selection; no WebKit processes and no framework load.
- Net: the first webview costs about **110 MB** (42 MB in the app that never comes back, 70 MB in helpers of which
  about 40 MB stay after it closes), each further live view about **30 MB**, and the main actor stays near idle. That
  passes #402's main-actor rule but not its "small steady cost" intent for a feature no plugin needs yet.

## Decision

**No-go now.** The design is safe enough to build (the prototype confirmed the network, file, inline-script,
navigation, download, clipboard and popup lockdown), and its main-actor cost is fine, but:

1. no plugin needs it: API 11's window views, split, nav, grid, drag-to-download, pickers, view updates and overlays
   cover every plugin UI asked for so far;
2. it adds one risk without a technical fix (a page that imitates BashCut and asks for secrets), made worse by
   auto-trust being on by default;
3. it costs about 110 MB the first time, 30 MB per extra view, and an unbounded share of CPU while visible.

**Go when** a named plugin needs free drawing, custom charts, rich text or a live HTML preview that cannot be done
as declarative components, overlays or a rendered image. Then build it as below, in this order, behind
`views.webview` and the off-by-default per-plugin switch.

## Implementation breakdown (if go)

Plugin API 12 (`views[].webview`, host feature `views.webview`, the `message` field of view answers and `viewUpdate`).

| # | Ticket | Size | Done when |
|---|---|---|---|
| 1 | Manifest: `views[].webview` (`entry`, `minWidth`), allowed locations, `apiVersion` 12, host feature `views.webview`; validation and `plugins validate` messages | S | Invalid entries, locations and API versions are refused with clear reasons; older hosts list the plugin as outdated only when `features` names it |
| 2 | `PluginWebViewHost`: scheme handler (root, id, symlinks, MIME, trusted files only), CSP header, rule list, non-persistent store, navigation/download/UI policies, `bashcut-media:` tokens | M | Unit tests over a generated plugin folder: traversal, other id, symlink out, changed file, `file://`, `https`, `data:` navigation, download all refused |
| 3 | Bridge: `bashcut.call` through `hostChannel`/`perform`, `bashcut.event` through the view queue, `on` pushes, origin check, size and rate limits, `callAsyncJavaScript` arguments only | M | Tests with a fake plugin: allow-list and own-plugin refusals match declarative calls; oversize and flood fail fast; pushes coalesce at 60 ms |
| 4 | Lifetime: create on show, release on hide, 3 live views app-wide, crash placeholder with Reload, `window`/`dock`/`sheet` hosting | M | A perf test opens and closes 20 times without growing helpers beyond one warm WebContent; a killed WebContent shows the placeholder |
| 5 | User control: per-plugin "Show web content" switch (user-only, not set by auto-trust), frame badge, Settings and Plugins sheet rows, `plugins list --views` shows `webview` and the switch; localized EN/VI | S | Off by default on fresh install and after auto-trust; agents cannot turn it on |
| 6 | CLI/MCP parity: `plugins view` returns the page's last `message` and state, `plugins view-event --type <event>` sends a page event, so agents and tests drive a webview view without a browser | S | Commands documented in `docs/reference/commands.md`; tests use a generated plugin |
| 7 | Docs and sample: plugins guide section, `bashcut-plugins` sample webview plugin with a declarative fallback, `new-plugin.py --webview` | S | Sample passes `plugins validate`; guide lists the CSP and limits |
| 8 | Bench: extend `.local/scripts/bench-plugin-views.py` and the perf suite with first-paint, RSS of host and helpers, and idle CPU of 1/3 live views | S | Numbers recorded in the PR; main actor within #402's idle baseline |

Tickets 2 and 3 can run in parallel after 1; 4 needs 2; 5–8 after 3 and 4.
