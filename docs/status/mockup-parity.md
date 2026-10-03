# Mockup parity

How far the native app matches the interactive mockup, area by area. The reference is
[`mockups/bashcut-ui.html`](../../mockups/bashcut-ui.html), last checked against the native views on 2026-10-02. The
mockup uses sample data and several inert controls, so this table tracks working native behavior, not matching
buttons. Passing core tests is not evidence of UI parity.

| Area | Working in the native app | Remaining mockup behavior |
|---|---|---|
| Project | Welcome and recent projects, New Project wizard and folder creation, open from Finder or the Dock, legacy EDL import and report, open/save, recovery, external-change differences, undo/redo/history, Settings, Doctor | — |
| Media | Footage/Project/Shared source filter, file search, thumbnails with hover-scrub, offline badges, resolution/FPS/duration/audio metadata, source preview with In/Out, insert/overwrite, background preview proxies with tile status | Speech search, survey badges |
| Audio | Import and insert into music/SFX/voiceover, volume, mute, fades, automatic ducking under tagged speech and voiceover, source waveforms, provider-based beat detection and beat snapping | Shared catalogs, preview player, license and credit metadata |
| Text | Six rendered presets including Place, Hook and Chapter cards, editable styling, SRT import/replace/export, provider-based Auto Captions | Word animation |
| Stickers | Emoji text inserts | Graphic assets, overlay drag and drop, animation |
| Effects | Static framing changes | Recipe catalog, animated zoom, speed ramps, flash, score banners |
| Transitions | Hard cuts plus rendered Dissolve, Whip, Blink, Zoom, Spin, Shutter and Wipe with adjustable duration | — |
| Filters | Exposure/contrast/saturation, basic looks, project-scoped `.cube` import and catalog, per-clip LUT and strength, shared preview/export rendering, Before/After split | Thumbnail previews for imported looks |
| Voice | Record 48 kHz WAV voiceover with a live level meter, import takes, or generate three takes from a healthy provider; validate, preview, score, select and insert one with provenance | Clone and enroll |
| Viewer | Shared render engine, Before/After color split, seek, play, frame step, safe area, chase-time scrubbing, proxy playback | — |
| Inspector | Role tags, manual framing and reframe cycle, color, caption styling, audio, constant speed with optional pitch preservation, freeze frame, roll/slip | Demucs |
| Timeline | Dynamic ordered video/image, text and audio layers, linked Main/Dialogue editing, magnetic reorder, freeze frames, section band, vertical scroll, waveforms and beat grid, zoom buttons, log slider, pinch and ⌘-scroll zoom around the pointer, zoom to fit (⇧Z), clip/beat snapping, move/trim/split/ripple/lift, agent marks | — |
| Agent dock | Claude/Codex/Shell terminals, detachable window, ⌘K Ask, frame attachment for terminals, MCP bridge plus CLI fallback, automatic resume and handoff, default agent and edit permission, selection context, quick actions, privileged export approval, Show Changes, shared skills and memo; every UI action and dialog reachable from 46 CLI/MCP commands | — |
| Plugins | Versioned manifests, project/user/bundled discovery, capability and dependency display, reviewed install plans, process RPC, health probes, Voice/Text/Audio integrations | Signed catalog, remaining feature-panel wiring |
| Review | Structural issues and navigation, red timeline warnings when voiceover is within 0.3 s of tagged speech | Measured loudness, silence and speech coverage; automated fixes |
| Export | TikTok, YouTube 1080p/4K, Quick Draft and ProRes presets; background queue with progress, queued count and cancel; optional SRT; persistent receipts and CLI status; comparison with the previous export; optional provider-based LUFS/true-peak normalization; OpenTimelineIO export | Measured speech/silence analysis, metadata and credits |

## Native verification

The New Project wizard and the Quick Draft export sheet and receipt passed native smoke tests. Native interaction
checks are still outstanding for waveforms, the standalone SRT file pickers and modifier-key trim gestures. See
[implementation.md](implementation.md) for verification details and remaining work.
