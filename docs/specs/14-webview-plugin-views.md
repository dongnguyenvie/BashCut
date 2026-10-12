# 14 — Webview plugin views (research, #406)

**Status: research. Decision: no-go for now** (revisit when a plugin needs something declarative views cannot draw).
Declarative views (`contributes.views`, `docs/guides/plugins.md` › Plugin panels and views) stay the default and the
only kind shipped.

## What was asked

A `webview` view kind: a `WKWebView` that shows a plugin's own HTML, with no network by default, files only from the
plugin folder, and a narrow bridge (`bashcut.call`, `bashcut.event`) over the same host channel and allow-list as
declarative views. Plus a security review, the memory and CPU cost per view, and a go/no-go.

## Design (if it is ever built)

- Manifest: `views[].kind: "webview"` with `entry: "ui/index.html"` (a file inside the plugin folder), host feature
  `views.webview`, `apiVersion` 8. Only `panel`, `dock` and `sheet` locations (never `inspector`, which re-renders on
  every selection).
- Loading: a custom URL scheme handler (`bashcut-plugin://<plugin-id>/…`) that serves files from the plugin folder only,
  after resolving symlinks, with a MIME type by extension. No `file://` access (`allowFileAccessFromFileURLs` off), no
  `loadFileURL` with a read-access folder.
- Isolation: `WKWebsiteDataStore.nonPersistent()` per plugin (no cookies or storage shared across plugins or kept),
  JavaScript allowed, `javaScriptCanOpenWindowsAutomatically` off, no `WKUIDelegate` file panels, media autoplay off.
- Network: blocked with a `WKContentRuleList` that blocks every `http(s)`/`ws(s)` load, and a Content-Security-Policy
  the scheme handler adds to every HTML answer: `default-src bashcut-plugin:; script-src bashcut-plugin:;
  style-src bashcut-plugin: 'unsafe-inline'; img-src bashcut-plugin: data:; connect-src 'none'; frame-src 'none';
  form-action 'none'; base-uri 'none'`. A plugin that needs data from the network fetches it in its own process and
  passes it through the bridge (the process is already where network access is reviewed).
- Navigation: `decidePolicyFor navigationAction` allows only the plugin scheme and same plugin id; everything else is
  cancelled (links to the web open nothing; a later version could hand `https` links to the default browser after a
  confirmation). Downloads (`WKDownload`) are cancelled.
- Bridge: one `WKScriptMessageHandlerWithReply` named `bashcut`, injected as `window.bashcut = {call(method, params),
  on(event, fn)}`. `call` goes to the same `PluginViews.perform` path as host-channel calls (allow-list, author
  `plugin`, own-plugin checks, `plugins.invoke` only for `uses`), limited to 1 MiB per message and N calls per second.
  Events the app pushes (`viewUpdate`-style data, theme, locale) go through `evaluateJavaScript` with JSON only. The
  plugin's process is reached through `plugins.invoke`/a `view.event`-like request, never directly from the page.
- Clipboard: `navigator.clipboard` read blocked by the CSP-less default (needs a user gesture and permission in
  WebKit); writes allowed (copy a value), which matches what a text field allows.
- Lifetime: the web view is created when its view is on screen and torn down when hidden (its WebContent process
  exits), so a closed panel costs nothing. At most one live webview per plugin and two app-wide.

## Security review

| Risk | Mitigation | Remaining |
|---|---|---|
| Plugin page reaches the network (exfiltration, tracking) | Content rule list + CSP `connect-src 'none'`, no `http(s)` navigation | WebKit bugs; the plugin process can reach the network anyway, so this adds no new capability |
| Page reads local files | Custom scheme serving only the plugin folder; no `file://` | None beyond what the plugin process can already read |
| Page calls app commands | Same allow-list and author `plugin` as the host channel, own-plugin checks, rate limits | Same as declarative views |
| Phishing UI (a page drawing a fake "Enter your API key" or a fake BashCut dialog) | — | **Real and new**: HTML can imitate any app UI; declarative views cannot. Secrets entered there would bypass Settings' secret options |
| Clickjacking / overlays outside the view | The web view is clipped to its view; no window opening | — |
| Code from elsewhere (CDN scripts) | CSP `script-src bashcut-plugin:` | Trusting pins the files; a page still runs whatever JavaScript the plugin ships |
| Trust surface | Pinned by the plugin tree digest like other files | Reviewing HTML/JS is much harder than reviewing a declarative tree |

## Cost

Measured with a small offscreen `WKWebView` loading a 200-item list page (Apple silicon, an ad-hoc Swift script,
one run, not a full benchmark): the first web view raised the host process from 15 MB to 62 MB RSS (+47 MB of WebKit
frameworks and caches) and started three WebKit helper processes (WebContent, Networking, GPU) totalling about 68 MB.
Each further view adds roughly one WebContent process (typically 30–60 MB). Startup to first paint was several hundred
milliseconds, off the main actor but visible as a blank panel. A declarative view of the same list costs well under
1 MB and parses in under 1 ms (`scripts/verify.sh perf`, PluginViewPerfTests: the largest 2000-component view parses
in about 3 ms).

CPU: an idle page with a 1 s timer is near zero, but the app cannot bound what a page does (animation loops,
`requestAnimationFrame`); WebContent runs out of process, so the main actor stays free, but it competes with playback
decoding and export for CPU and GPU.

## Decision

**No-go now.** The perf rule of #402 (main actor near idle, small steady cost) would hold, since WebKit runs out of
process, but each live view costs about 100 MB the first time and tens of MB after, and the security review leaves one
new risk without a good fix: a page can imitate BashCut's own UI and ask for secrets. Everything plugins asked for so
far fits declarative views with this round's additions (colour and font pickers, view updates without a request,
overlays, drag and drop, inspector views).

Revisit when a concrete plugin needs free drawing (a node graph, a waveform editor) that declarative components and
overlays cannot express. If built: gate it behind `views.webview`, a per-plugin user switch in Settings that is off by
default ("Allow this plugin to show web content"), the design above, and a banner in the view's frame naming the plugin.
