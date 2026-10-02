# Mockup implementation audit

Reference: `mockups/bashcut-ui.html`, checked against native views on 2026-10-02.
The HTML uses sample data and several inert controls. This table tracks working native behavior, not just matching buttons.

| Area | Working in the native app | Remaining mockup behavior |
| --- | --- | --- |
| Project | Welcome/recent projects, new project settings/folder creation, legacy EDL import/report, open/save, recovery, external-change differences, undo/redo/history, persistent Settings and Doctor diagnostics | — |
| Media | Footage/Project/Shared source filtering, file search, thumbnails with hover-scrub, offline badges, resolution/FPS/duration/audio metadata, source preview, In/Out, insert/overwrite | Speech search, survey badges |
| Audio | Import/insert into music/SFX/voiceover, volume, mute, fades, automatic music ducking under tagged speech/voiceover, source waveforms, replaceable-provider beat detection and beat snapping | Shared catalogs, preview player, license/credit metadata |
| Text | Six rendered presets including Place/Hook/Chapter cards, editable styling, SRT import/replace/export and replaceable-provider Auto Captions | Word animation |
| Stickers | Emoji text inserts | Graphic assets, overlay drag/drop and animation |
| Effects | Static framing changes | Recipe catalog, animated zoom, speed ramps, flash, score banners |
| Transitions | Hard cuts plus rendered Dissolve, Whip, Blink, Zoom, Spin, Shutter and Wipe with adjustable frame duration | — |
| Filters | Exposure/contrast/saturation, basic looks, project-scoped `.cube` import/catalog, per-clip LUT application and strength, shared preview/export rendering, synchronized Viewer Before/After split | Thumbnail previews for imported looks |
| Voice | Record 48 kHz WAV voiceover with a live level meter, import existing takes, or select a healthy plugin provider; generate three compatible takes, validate/preview/score/select one and insert it with provenance | Clone/enroll |
| Viewer | Shared render engine, synchronized Before/After color split, seek/play/frame step, safe area | — |
| Inspector | Role tags, manual framing plus deterministic reframe cycle, color, caption styling, audio, constant speed with optional spectral pitch preservation, freeze frame, roll/slip | Demucs |
| Timeline | Dynamic ordered video/image, text and audio layers, linked Main/Dialogue A/V editing, magnetic Main reorder, freeze-frame clips, editable section band, vertical scroll, waveform and beat-grid drawing, zoom/scroll/clip-and-beat snap, move/trim/split/ripple/lift, agent marks | — |
| Agent dock | Claude/Codex/Shell PTYs, detachable resizable window, current-frame attachment for terminals and multimodal APIs, ephemeral official-SDK MCP bridge plus CLI fallback, automatically discovered project-scoped resume bookmarks and handoff, default agent and edit-permission settings, API script/edit proposals, selection context, quick actions, privileged export approval, before/after Show Changes, shared skills and project memo | Remaining command parity |
| Plugins | Versioned manifests, project/user/bundled discovery, capability/dependency display, reviewed install plans, process RPC runtime, dependency health probes and Voice/Text/Audio integrations | Signed catalog and remaining feature-panel wiring |
| Review | Structural issues and navigation, including red timeline warnings when voiceover is less than 0.3 seconds from tagged speech across layers | Measured loudness/silence/speech coverage and automated fixes |
| Export | TikTok, YouTube 1080p/4K, Quick Draft and ProRes presets; background progress/cancel; optional SRT; persistent receipt and CLI status; tagged speech coverage; comparison with the previous export; optional provider-based two-pass target-LUFS/true-peak normalization with final measurement; UI/CLI OpenTimelineIO export | Multi-job queue, measured-speech/silence analysis, metadata/credits |

The New Project wizard and Quick Draft export sheet/report passed native smoke tests. Native interaction checks remain outstanding for waveform, standalone SRT pickers and modifier-key trim gestures. Passing core tests is not evidence of UI parity. See [implementation-status.md](implementation-status.md) for verification and the full roadmap.
