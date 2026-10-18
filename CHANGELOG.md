# Changelog

- Set the first TestFlight candidate version to 0.0.1 (build 1).
- Add the Mac App Store category, sandbox entitlements, and BashCut app icon required for TestFlight validation.

## [Unreleased]

- **Stacked text lines no longer touch, whatever the preset or line height.** A hook title "AI DỰNG HẾT / TRÊN TIMELINE" drew the dot below "Ự" into the circumflex of "Ê": lines were spaced `lineSpacing` × the mean font size (1.0 for `hook-title`) without measuring ink, and the 1.4× emphasis line made it worse, so agents patched each title with `lineHeight`. `TextRenderer.stack` now keeps each baseline gap at least the ink the two lines reach toward each other (glyph outlines, so stacked Vietnamese marks count, plus the outline and an emphasis plate) and 0.06 font sizes; lines with room keep the tight preset spacing. A `background` plate now reaches the top line's marks and the bottom line's descenders, and the place card's plate follows the lines' positions.
- **A review no longer passes while a stage the plan requires is still pending.** A tutorial's recipe required the effects stage (zooms onto the panel each line names), but the stage stayed `pending`, the agent reused one zoom on every screen shot, and `review run` passed and was logged as the review stage anyway. Now every stage the plan marks `required: true` before review (effects, sound, visuals…) must be `done` or `skipped` with a reason in the current run before an agent can mark review done (`run append stage --stage review --status done`), request G5, or make a final export: else `stage_pending`, with `data.stages` (`{id, status}`) and `remediation.command` `run checklist`. A passing `review run` is not logged as the review stage meanwhile and lists them in `stagesPending`. The user's G5 approval still overrides, and the user is never blocked.
- **Cut a span of time out of the whole timeline in one edit (`timeline cut-range`, op `rippleDeleteRange`).** `trim` and `delete` with `ripple` move only their own layer and linked sound, so removing a 3 s restart from a talking head whose camera sound sits unlinked on A1 under its picture on an overlay left "overlaps" errors, and an agent built it by hand in 159 ops (trims, deleted and split captions, every later item on every layer moved, the music bed's end trimmed, markers rewritten). `{"op":"rippleDeleteRange","from":F,"to":T}` (and `bashcut timeline cut-range --from F --to T`, MCP `bashcut_timeline_cut-range`, with `--dry-run`) now cuts `[F, T)` out of every layer: items inside go, items over an edge are trimmed, a clip over the whole span is split and its parts joined at F (linked picture and sound alike, the right parts relinked), text and captions stay one item and lose the words and keyframes inside (the text keeps the words left), and everything later moves left by T−F with the markers, sections and beat grid. A music layer's bed keeps its source running and loses its tail instead (`continuous` names other layers, `none`/`[]` splits beds too); `tracks` limits the cut, with the layers of linked partners. Transitions on removed cuts go, one after a split clip moves to its right part. The command returns the new duration and `cutsInsideWord` like `timeline apply`'s dry run.
- **Focus lands where the viewer can see it, and plan.cut frames shots by rectangle.** `clip motion --focus` centred the rectangle in the whole frame, so in a 9:16 tutorial with the camera across the top half the named panel landed under the camera, and agents worked out zoom, pan and tilt by hand (every screen shot of one project got the same pan 0, tilt −480, zoom 1.9). Focus now frames into the band of the frame that stays visible: by default (`--within auto`) the part no opaque, unrotated picture on a higher layer covers edge to edge at that frame (a camera across the top leaves the bottom half; a full-canvas graphic or a picture-in-picture does not count), or `--within full`, `top-half`, `bottom-half`, `left-half`, `right-half`, or `x,y,w,h` in canvas shares or pixels. The rectangle is fitted to the band and centred in it, no picture edge comes inside the band, and the result gives `within`, the band used. plan.cut clips, covers and overlays take `focus` ([x, y, w, h] in source pixels), `focusTo`, `focusKeys` ([{at (source seconds), rect, move}]: one panel after another, each held until the next and eased in over `move`, 0.5 s by default), `within` and `ease`; `plan apply` resolves them with the same code into zoom, pan and tilt keys (the row's other keyframes stay), `plan check` rejects a focus next to zoom, pan, tilt or their keyframes and warns with `focus-key-outside` about a key outside the source its shot plays.
- **`plan apply` keeps keyframes, framing, gains, text style and ripple cuts made by hand, and says what it keeps and what it would overwrite.** After an apply, edits made on the timeline were not in plan.cut, and applying again silently undid most of them: a title's `lineHeight` or text fixed by hand, a `transform` set by `clip motion`, a dialogue gain raised with `clip volume` when the row gave a `volumeDb` (−3 dB came back over +8 dB), a music level set by hand, and every ripple cut (a 3 s stumble cut out of a clip came back, and the voiceover after it slid out of sync). Every built item now records what the build itself set (`planBuilt`), and a later apply merges three ways: a field changed by hand that the list did not change since stays as set by hand; one the list changed too takes the list's value. Merged are `volumeDb`, `muted`, fades, `crop`, `keyframes`, `backdrop`, `fill`, `color`, a title's `text`, and `transform` and `textStyle` key by key (a hand `lineHeight` stays while the list moves `positionY`). A clip cut, split or trimmed by hand keeps its pieces (with their IDs) while its row gives the same range, and the clips after it follow; a line, title, graphic or sound moved by hand keeps its start unless the list moved it too. The music bed keeps a level set by hand while the list asks for the same bed, and is then not measured again (`keptHandLevel`); a measured level is recorded apart (`planMeasured`). plan check, `plan apply --dry-run` and `plan apply` report `handEdits: {kept, overwritten}`, by item, entry and field, with the hand's and the list's value. Items built before this record count what differs from the new build as by hand while their row is the one stored in plan.cut, and as the list's when the row changed. A row's `null` picture field still clears a hand edit. Captions: every cue of a media deleted by hand (a screen recording under the voice) now stays deleted too, while a media transcribed since the last apply still gets its captions (built clips record `planCaptioned`), and plan captions no longer go on a clip of the same media placed by hand (a camera picture-in-picture). Two caption bugs that made `plan apply` fail or mislabel cues are fixed: regrouped cues of a sped-up clip overlapped by a frame ("overlaps … on layer t1", so no apply could build), and every regrouped cue took the media and look of the first cue it replaced instead of the cue its words were heard in.
- **An export with 2–4× clips no longer freezes partway.** Sound sped up 2–4× was still time-scaled by the composition (only faster sound was rendered offline), and with twelve such clips a 180 s timeline froze near 144–148 s on every export, mix measurement and `audio measure --timeline` ("Rendering stopped answering", the bar stuck at 80%); removing the clips there only moved the freeze to the next scaled one. An export (and mix measurement) now renders every sound that is not at 1× offline, like a speed ramp; preview still scales up to 4× so editing does not wait for a render. A stall report now also says where each lane stopped and whether it was blocked in a read or waiting for the writer ("video at 143.73 s waiting for writer; audio at 144.20 s blocked in read").
- **A batch preset saved from the CLI runs from the Batch window.** `batch presets pipeline.json --name X` kept a relative `projectsFolder` (and kept inputs, with `--keep-inputs`) as written; `batch run` resolved it against the pipeline file's folder, but the Batch window had nothing to resolve it against, so a run from the window tried to create `/projects` and every item failed with "volume is read-only". `batch presets` now takes `base` (the CLI sets it to the pipeline file's folder, as for `batch run`) and saves those paths absolute (`BatchPipeline.resolvingPaths(against:)`); without a base a relative path is refused. A preset saved before this fix is refused at Run with a message naming the relative path, instead of failing every item.
- **Batches of many items: checks before the run, retry from the failed step, resume after a quit, time left and a notification.** A batch of 50 clips used to import, caption and cover every clip and then fail each one at translate when no key was set, lose its state on quit, and give no sign of how long it had left. Now: **Run** (and **Retry**) first checks each plugin step's keys (the plugin's own `options.check` with the stored key, so a server on this Mac that needs none passes), input files that do not read or play (**Skip Them, Run N**), and free disk space against a rough estimate, and asks only when something is wrong; `batch run` returns the same findings as `warnings` and shows them in the approval. **Retry Failed (N)** in the queue and **Retry** on a row (`bashcut batch retry [ID] [--items 2,5]`, approved once) run failed, cancelled, skipped or interrupted items again in the projects they made, from the step that did not complete. Runs are saved to `Application Support/BashCut/Batch/Runs.json`; quitting while one runs asks first and saves it interrupted, and the next launch offers **Resume**. The queue shows an overall progress bar, time elapsed and an estimate of the time left (also `elapsedSeconds`, `remainingSeconds` and `retryable` in `batch status`), the Dock icon shows items done, a notification says when it ends, and the Mac does not idle-sleep while it runs.
- **An export no longer fails when an H.264 clip follows a 10-bit HDR clip.** Clips on one layer that do not overlap shared one composition track whatever their format, and after a 10-bit HEVC HLG clip (a Sony demo used to its end) AVFoundation gave the compositor no picture for the 8-bit H.264 clip after it, so the export stopped at the join with "source frame missing" (the other order worked). Clips now share a video lane only when their pictures decode alike: the same codec, bits per component and transfer function (`VideoCompositionLanes.decoderKey`, read once per media).
- **`plan apply` keeps sound, speed, music and caption edits made by hand.** Applying the list again rebuilt its items from scratch, so every speed ramp (`clip speed-curve`) and `clip speed` was reset, a music bed trimmed or extended by hand went back to the length of the edit, footage an agent had muted (or set to −96 dB) was heard again, and caption cues deleted as junk (background chatter) came back whenever the captions were rebuilt; agents re-did these after every apply. A later apply now puts back on the rebuilt items, by item ID: a clip's speed or ramp unless the list gives `speed`; `volumeDb` unless the list gives it, `muted`, `fadeIn` and `fadeOut`; and the bed's span while the list plays the same music from the same `from` (the bed's level stays the list's or its measured one). Built items record what the build itself set (`planAudio`, `planSpeed`, `planMusic`), so a value the list drops is dropped from the item. Rebuilt captions leave out the words a built clip played with no caption of that media over them, so cues deleted by hand (or words cut out of one) stay deleted, while speech a clip plays for the first time gets its captions; a muted clip gets none. Regrouping now reads the old cues as they were before the apply, not after a speed rebuilt in the same apply had retimed them.
- **An export no longer freezes when a sped-up clip follows another clip at the same volume.** Clips on one layer that touch and keep the same gain share one audio lane; when the later one was sound the composition time-scales (a constant speed up to 4×), AVFoundation's audio mix output could stop answering at the join, and the export failed with "Rendering stopped answering" (a 38 s timeline froze at 17.3 s once two clips went from -60 dB to the -96 dB of their neighbours; at -60 dB they had been on their own lane). A time-scaled clip now never touches another clip on its audio lane: it starts a new lane, and the next cut does too.
- **A text plate never turns into an ellipse, and `plan check` warns about plate sizes given in pixels.** A text style's `background` (and an emphasis `plate`) takes `padding` and `radius` × font size, but nothing said so where agents read it, so an agent wrote `"radius": 20` meaning pixels: the plate drew 20 font sizes round, Core Graphics rounded each axis on its own and the hook title sat on a large oval. The corner radius is now capped at half the plate's short side (at worst a pill); the agent instructions and `plan check` say "× font size, not px"; and `plan check` reports `plate-units` (a warning) for a background or plate `padding` or `radius` above 2.
- **A fresh clone builds in Xcode again.** `project.yml` asked for SwiftTerm `from: 1.20.0`, so a checkout without a gitignored workspace `Package.resolved` got SwiftTerm 1.99.0, and `scripts/verify.sh xcode` failed in `TerminalSession.swift` ("'AgentTerminalView' has no member 'getTerminal'"). SwiftTerm is now pinned to exactly 1.20.0 in both `project.yml` and `Package.swift`, the version the root `Package.resolved` already had.
- **Captions follow a speed change, and a sped-up clip no longer ends inside the next word.** `clip speed` (and `clip speed-curve`) left the captions where they were: at 1.5× a 58-frame clip became 39 frames, but its captions stayed on the old 58 frames and the clips it rippled lost theirs too, so review reported a gap at the end. Captions made from a media (`captionMedia`) are now mapped through the clip they were heard in whenever the edit changed that clip's speed or position — the sped clip and the clips its ripple moved — with their word timings, as linked sound already was; one that would land on a caption left on its layer goes to the next caption layer. Typed captions, and captions after other edits (trims, moves, ripple deletes), still stay where they are. The new length is now rounded down instead of to the nearest frame (58 / 1.5 = 38.67 → 38, not 39), so the out edge never plays past the source it played before: 39 frames played 0.04 s into the next word and review flagged `cut-in-word`.
- **Emoji no longer fail the glyph check.** Every emoji sticker or emoji in a title made review fail with an error such as "Arial-BoldMT has no glyphs for “🎉”", although Core Text always draws emoji in Apple Color Emoji. The check now leaves emoji out (emoji presentation characters and sequences such as ✨, ❤️ and 1️⃣), and still reports letters a font cannot draw.
- **Emoji stickers are sized and placed like image stickers.** `library place` of an emoji sticker (and placing one from the Stickers panel) used its text preset's size and place, so 🎉 came out caption-sized right on top of the captions, and `--position` and `--size` were ignored with a note. An emoji sticker now gets `textStyle` size, positionX and positionY from the sticker's size (0.3 of the frame width by default) and position (the centre by default, inside the safe area), as image stickers do.
- **Plugin keys and link tokens are kept in a file, not the Keychain (for now).** `secret` plugin options and per-host link tokens are stored as plain JSON in `~/Library/Application Support/BashCut/plugin-secrets.json` (mode 0600), same keys as before. Reading them from the Keychain blocked on an access prompt whenever the app's signature differed from the one that saved them (a dev copy against the release), so `plugins options` and anything reading a key hung until the prompt was answered. Keys saved in the Keychain before are not carried over: enter them again in Settings › Plugins.
- **Captions no longer show the last word before a clip.** A clip whose first frame falls a few milliseconds before its first word (a 59.94 fps source rounds 8.70 s down to frame 521, 8.692 s) showed the end of the word before it in its caption ("But today's all…" for a quote starting at "today's"): the line was kept whole within 0.05 s of the clip's edge, and word timings were tested after clamping to the clip. Caption placement now keeps only the words whose middle is inside the clip's source span, before clamping, as `transcript words --heard` does, and rebuilds a line whenever that leaves one of its words out.
- **Library, media and Settings › Plugins searches ignore accents and đ.** `library list --query`, the library panels' search, the Media panel's search and the Settings › Plugins filter matched only case-insensitively, so "chu do" did not find "Chữ đỏ" (and "DÍSSOLVE" did not find "Soft dissolve"). They now fold both sides with `String.searchFolded`, like the other searches since the structure cleanup.
- **Second structure cleanup.** A new batch step's parameters come from one place: `BatchRunner.newStep` starts from the step catalog's starter params, fills the required ones and puts a tool card's settings on top (`toolStep`, one tool→command map), so the batch window's catalog steps, the export step and the tools' **Many projects / files…** no longer each build their own (a catalog step now also gets its required parameters filled like any other new step). `library place` and `music replace` share the loop tiling (`Project.tiledAudioItems`); the batch, agent, Knowledge and plugin-view windows share one dark window setup and background colour (`AuxiliaryWindow`, `Color.editorBackground`). `PluginRecipeRunner` is `PluginCommandRunner`, with the label always given (it also runs export steps), and export steps validate their command with `PluginCommand.validate()`. Size splits: `ExportView+Rows`, `PluginSecretField`, and `ProjectSetup.freeName`/`folderName(_:)` in core.
- **Structure cleanup after the batch, export-steps and option-check work.** Export steps keep App Nap off like the export itself (#350 covered only the export queue). The batch's messages come from one list in core (`BatchMessages`): the throw sites word them through it and the batch window translates from it, so rewording a message can no longer silently drop its Vietnamese. `plan check --save` now counts as an edit in the agent's activity steps, not only in the token check. One search-fold (`String.searchFolded`) replaces eight copies; batch export, the Export sheet and `export start` share the preset check, the steps-then-export path and the step list; misplaced types moved to their own files (`DocumentBatchHost`, `BatchQueueStatus`, `BatchMessage`, the option check, the clip blur/mosaic compositing).
- **Mosaic and soft edges on a clip (`pixelate`, `feather`).** Two more picture fields for video and image clips, after the crop: `pixelate` turns the picture into square cells (the cell size as a share of the short side, 0…0.1), and `feather` fades its edges out over a share of its shorter side (0…0.5), so a cropped copy that hides text blends into the picture around it instead of showing a rectangle. With `blur` they make the usual pixelated-subtitle look. Host feature `clip.mosaic`.
- **Blur a clip or image (`blur`).** A new item field softens a video or image picture after its crop: `blur` is the Gaussian radius as a share of the picture's short side (0…0.2; 0.02 softens, 0.04 makes text unreadable), kept opaque to the crop's edges. Crops are now cut at whole source pixels (rounded inwards): a fractional edge left its row partly transparent, which showed the layer below along the edge and, once blurred, through most of a thin strip. A copy of a clip cropped to one area with `blur` blurs just that area, such as subtitles burned into the footage (Translate Captions uses it to cover them). `timeline apply` `setProperties` sets it; host feature `clip.blur`.
- **Plugin keys: saved ones show as saved, and a plugin can check a key before it is saved.** After **Save**, a plugin's API key field went back to "Not set" until Settings was reopened, so a saved key looked lost and was typed again. A stored key now shows as dots with **Saved** (the button becomes **Replace**) right after saving. A `secret` option with `"check": true` has Settings send the typed key to the plugin (`options.check`, with the plugin's other option values) and show its answer under the field while it checks: a refused key ("This looks like an OpenAI key", "Gemini refused the key") is not saved unless the user chooses **Save Anyway**, an accepted one is saved with the plugin's message. Host feature `options.check`; a plugin that cannot answer gets its key saved unchecked.
- **Dev builds stop asking for Desktop access again and again.** `scripts/run.sh` now signs with a Developer ID Application identity when the keychain has one (else Apple Development, or `BASHCUT_SIGN_IDENTITY`). macOS keeps one privacy grant per bundle ID, so a dev build signed with Apple Development and the installed release signed with Developer ID took the grant from each other and both asked again on every switch.
- **Batch window: drive it through MCP/CLI alone, messages in Vietnamese (#658).** `ui respond --dialog sheet:batch` gets `add-step:<action>` (the ＋ Add step catalog), `remove-step-N`, `move-step-N-up|down` and `load-preset:<name>`; `ui dialog` lists the steps by label. The pipeline checks and runner failures the window and its queue show ("Give at least one step", missing inputs, refused steps, failed steps) are now translated to Vietnamese.
- **Agent calls stay fast while an export runs (#350).** A BashCut window in the background was put to sleep by App Nap while the encoder used the CPU, so an agent's calls during and right after an export waited 0.6–3 s (`context.get` in the feature bench). BashCut now keeps App Nap off while an export runs (which also keeps the Mac from idle sleep mid-export) and while it serves each automation call. `context.get` reads the media's analysis and transcript cache files off the main thread in one step instead of one main-thread hop per media. Only the user's own export opens the export report sheet: an agent's export shows the toast, now with a **Report** button (and during a run, the result card as before), because the sheet's open animation holds the main thread.
- **Batch window: build, save, run and follow a pipeline without the CLI (#597).** File ▸ Batch… (`ui action open batch`) opens a window with three columns — inputs (drop videos, folders or projects, or Add…), the pipeline's steps (＋ Add step lists the core step catalog by group (build, fix, check, export), the tools, every command a batch may run by area and the plugin actions) and the selected step's settings in the same tool card as the Tools panel — with the batch settings (template canvas, projects folder, on failure, output name) under them and the queue below: item, step, progress, result (files written, review issues, the failure), and Open to fix, Reveal or Cancel. Run is the batch's approval; Save Preset stores it without inputs and Presets loads one. A tool card's **Run on** gets **Many projects / files…**, which opens the window with that tool and its settings as the first step. Agents read the window with `ui dialog` and answer `sheet:batch` (add-inputs, save-preset, run, cancel, open-N, reveal-N).
- **Batch fixes over many projects (#598).** Three new whole-project edits, each one undo step, CLI and MCP, and each usable as a batch step: `captions replace FIND --with TEXT` replaces text in every caption on the caption layers (case ignored unless `--match-case`, whole words unless `--whole-word false`; word timings kept when the word count stays, else estimated; no match is `replaced: 0`, not an error; `--dry-run` lists the changes); `captions style` restyles every caption with a library text preset (`--preset`), textStyle fields (a JSON file) and/or `--word-style`; `music replace --media ID|--library ID` swaps the music bed for a new sound over the same span on the same layer (ducking kept), with the old level and fades, repeating a shorter sound unless `--loop false`. Applying a brand kit (`library apply <brand>`) and re-exporting (the batch `export` step with `presets`) already existed. `BatchStepCatalog` (core) lists the built-in steps (import and place, auto captions, the four fixes, review, export) with starter params for the batch window's Add step. Chat agents may run the three new commands.
- **Batch pipelines: the same steps over many files or projects (#596).** A pipeline is plain JSON — `inputs` (media files, folders or projects), `template` (canvas, resolution, frame rate, language, brand kit and output presets), `steps` (a command or plugin action ID with its params; `{input}`, `{name}`, `{project}` and `{media}` are filled per item), `onFailure` (skip the item or stop), `concurrency` and `outputName` (`{name}-{preset}`). `bashcut batch run pipeline.json` asks the user once to approve the whole batch, then each input becomes a project (a new one from the template for a file, with its folder linked as footage; the project itself for a project input), its steps run through the same command handlers as the CLI as jobs in the job center, the project is saved and the built-in `export` step writes one file per preset. `batch status [--wait]` reports every item's project, outputs and per-step state, job and error; `batch cancel` stops the batch and its running job; `batch presets` saves, lists, reads and removes pipelines in the user store (`Application Support/BashCut/Batch/Presets`), and `batch run --preset NAME --inputs …` runs one. Steps that need approval (`export start`), open projects or do not exist are refused before anything runs. Items run one at a time in the open app (no headless runs; `concurrency` is reported as asked and used). Batch commands are not held by the read-after-switch rule, so the agent that started a batch can still cancel it.
- **All assets search (⇧⌘F).** One search field over the editor finds across the whole local library (every kind, built in, plugin packs, this Mac and the project), the project's media and its selects, listed in one popover grouped by kind (Project media, Selects, Sounds, Library clips, Stickers, Text styles, Effects, Transitions, Looks, Voices, Brand kits) with a count per group. Every word must match, ignoring case and Vietnamese diacritics; a name that starts with the query ranks first, a match only in the pack, tags or path last. ↑↓ choose; Return or a click uses the result as its panel does (places it at the playhead, appends media, places a select, puts an effect or transition on the selected clip); after moving with ↓, Space previews it (plays a sound, opens footage or a select's range in the source viewer, shows other items in their panel). **Search online** opens Online resources searching for the same words (or the plugin search sheet when only a `library.search` provider is installed). **All assets** beside a panel's search field opens the same search with the panel's text. Also View › Search All Assets…, the UI action `show.assets` and `ui open assets`.
- **Export several outputs in one go, and see draft graphics before a final export.** The Export sheet lists the project's outputs (`output.presets`) as checkboxes with each one's picture, the primary on; **Export N outputs** queues one export per checked output, each named `name-<preset>` (`trip-tiktok.mp4`, `trip-shorts.mp4`), and each lands in the export history. A project without outputs keeps the preset picker. Every disabled checkbox says why on one line under it (no captions, no music, no `audio.loudness` plugin, with **Find a plugin…**), and **Target loudness** sits in the label column with the stepper beside its value. `export start --presets tiktok,shorts` does the same for agents under one approval (`--preset` still exports one); the result lists `exports` with each preset, output and job, and `--wait` waits for the last. When a final export (any preset but quick-draft) covers graphics a plugin rendered as drafts, the sheet says so ("3 graphics are drafts") with the plugin's final render to run (`bin/graphic plan --final` or `rerender --all --final`) and a Copy button; the user's own export still goes ahead. `review run` and `plan check` report a `graphic-draft` warning per draft media with its items and that command (#593, part of #634).
- **Plugin API 12: export steps, and Finalise and Export for draft graphics (#634).** A plugin can contribute `contributes.exportSteps`: a blocking step (a file inside the plugin, e.g. `bin/graphic rerender --all --final`) that runs before a final export whenever its `when` holds (`media.data.graphics.draft`: a media file a timeline item uses has that value set; media without it never counts). `export start` runs matching steps first (the approval lists them; `--no-steps` skips them and the `graphics_draft` guard refuses drafts as before), then checks the export guards again and exports; its `job` is the steps' job (`export.steps`), whose result names the export jobs, and `--wait` waits through both. The Export panel's "N graphics are drafts" notice gets **Finalise and Export** when a ready plugin has a matching step. While a step runs, the export counts as running: the toolbar ring and progress popover follow its `::progress` lines, `export status` reports `state: preparing`, and **Cancel Export** stops it with nothing exported. The step edits through the app's own `bashcut` (`BASHCUT_CLI`) with a short-lived token that edits as the plugin, so its change is one undo step; a step that fails, times out (`timeoutSeconds`, default 30 min) or leaves its `when` true fails the export with the plugin, the step and its last output. Host feature `exportSteps`.
- **plan check --save keeps a by-ID patch without building (#631).** `plan check --patch P` merged the patch but saved nothing, and `plan apply --patch` refuses while the check has an error, which a voice-led list always has before the graphics stage (`graphic-no-media`) or the voice stage (`no-take`); agents turned the patch into whole lists for `project set-data plan --merge` with a script. `plan check --patch P --save --base-rev N|last` now saves the merged list as `plan.cut` in one undoable edit when its only errors are those two, and refuses with the other problems otherwise; the result is the check's with `rev` and `saved`. With `--save` the check needs a session token like any edit.
- **Timeline clips are coloured by what they are, and names keep their ending.** Every clip on an overlay was the same blue, so a rendered graphic, a .mov and a formula card looked alike. A clip's fill now says its kind — footage teal, graphic indigo (a still, a rendered overlay without sound or with alpha, or a plan's graphic row), text amber, audio green, voice purple (voiceover and dialogue layers), adjustment grey — and the same colour heads the Inspector. The layer's role (main, overlay, captions, titles, music, SFX…) is kept as a thin stripe along the clip's bottom edge, and a speech shot on Main keeps its own. Clip titles are cut in the middle instead of at the end ("isom…canvas.mov" rather than "isometr…"), and hovering a clip shows its full name.

- **Inspector and agent are separate columns.** They were two tabs of one right column, so selecting a timeline item while the agent worked brought the Inspector forward and took the agent away. Now the Inspector sits beside the viewer and the agent dock has its own full-height column at the window's right edge; each shows or hides on its own (⌃⌘I and ⌘J, or the two toolbar buttons next to the menu), and selecting or editing never changes which columns show. A popped-out agent leaves no column in the editor window until ⌘J brings it back. `ui view --right-tab inspector|agent` shows that pane and leaves the other as it is; `ui view` no longer reports `rightTab` and `rightColumn` (read `inspectorPane` and `agentDock`).

- **plan apply keeps hand edits and moves picture-in-picture with its clip.** Grouped captions now survive an apply that changes the clips: `captions group` marks its cues with how they were grouped (`captionGroup`: the rule, or `{manual: true}`), and when an apply rebuilds the captions the new ones are grouped the same way — by the same rule at the new cuts, or, for chosen groups, keeping together the words heard in the stretch of source one grouped cue held (before, 28 groups came back as 21 generated cues). A `backdrop`, `crop`, `keyframes`, `fill` or `color` set by hand on a built clip, cover or overlay (`clip backdrop`, `clip keyframe`, a reframe) stays through later applies unless the list sets it; a clip, cover or overlay row can set them itself, and `false` (or null) clears one set by hand. Clip rows take `overlays: [{media, from, offset, seconds, zoom, pan, tilt, backdrop, crop, keyframes, fill, color}]`: pictures on an overlay layer, muted, built with the clip and moved with it when earlier clips change length; the clip's own media plays in sync with it by default (a speaker picture-in-picture over a screen recording no longer drifts from the sound after a re-apply). A `--patch` entry's `after` or `before` (another entry's ID) puts a new or moved clip there instead of at the end.
- **captions group breaks at cuts.** Rule mode (`--max-chars --max-seconds --break-gap`) no longer joins words across a cut between clips on Main into one caption ("nó sẽ xem nè, tức là nó" spanning two clips); `--break-at-cuts false` joins them as before.
- **Word times stay out of measured silences.** Whisper often stretches a word over the pause next to it, so `plan check` widened a clip's edge across a 3 s silence `media speech-map` had measured (255.85 → 253.04 s). Every reader of a stored transcript (plan check and apply, captions, `media transcript`, selects, review) now sees the words kept out of the silences longer than 0.3 s that `media.analyze` measured: a word running into one ends where it starts, one starting inside starts where it ends, one across it keeps its larger side; nothing changes when speech and floor do not separate. `media transcript` reports `wordsKeptOutOfSilences`; `media speech-map` still compares the recognizer's own times.
- **audio mix-measure fails with a reason instead of completing empty, and reports progress.** A stem that comes back without a loudness curve, or silent although its layers hold sound (a failed render), now fails the job with the reason instead of completing with `musicUnderSpeech: null`; a null that is real comes with `musicUnderSpeechReason`. `jobs status` shows the job's progress and the stem and timeline second being rendered. `--near` is described as the window around each sound effect where the voice is read.
- **Review: contrast on the text's own plate, reframed cuts and accepted issues.** Text with its own background (`textStyle.background`, opacity 0.5 or more) is rated by its fill (and word-state fills) against the plate laid at its opacity over the picture behind (`basis: ownPlate`), so yellow on a 92 % black plate over a dark screen recording reads about 9:1 instead of 2.56:1. A cut between two framings of the same media (zoom 10 % apart, pan a tenth of the width, another crop, framing keyframes) that measures little change is info ("Cut between two framings of one picture"), not a jump cut. Issues kept with `review accept` are left out of `review run`'s list (their IDs in `acceptedHidden`, counted as accepted) unless `--accepted` is given.
- **Small CLI fixes.** `media analyze --media A,B` takes a comma list; `media transcript` says its `words`/`phrases` are counts and that `--as words` lists the words; `textStyle.positionY` is described as the baseline height from the bottom (0.86 is near the top); a plan clip's speed over 16 says how to make a longer time-lapse.

- **Cancelling a stuck export or mix measurement no longer crashes BashCut; a stalled render fails with where it stopped.** `jobs cancel` on an `export.start` or `audio.mix-measure` that hung crashed the app (`EXC_BAD_ACCESS` at 0x0 on `app.bashcut.export.stream.0`): half a second after the stop the reader was cancelled while a stream thread still waited inside `copyNextSampleBuffer`, and AVFoundation freed the wait condition under it. The transfer now never cancels the reader or writer under a read: a stop the read outlives by 2 s ends the job at once (the queue moves on) and the reader and writer are released when that read returns. A render that writes no frame or sound for 60 s fails as "Rendering stopped answering near 6.42 s of the timeline…" instead of hanging forever.
- **Clips sped up past 4× no longer hang export and mix measurement.** AVFoundation's offline audio mixer deadlocks on compressed (AAC) sound scaled past about 8× (a 14.4 s span at 16× hangs every time, on any file), so a 16× time-lapse of a screen recording stopped every export at 0 % and every `audio mix-measure`; the export's video waited for that sound. Sound faster than 4× is now rendered offline at its constant speed by the speed-ramp renderer (cached like ramp audio) instead of being scaled in the composition.
- **A 720p quick draft keeps picture-in-picture and pans in frame.** Exporting at another size than the canvas (quick-draft of a 1920×1080 edit) used `transform.pan`/`tilt` and their keyframes, which are output pixels, unscaled, so a corner picture-in-picture at pan 763 sat outside the 1280 px frame. The export, and `setFormat`, now scale pan and tilt, keyframes included, with the frame.
- **plan apply answers even when measuring the music bed stalls.** The bed's level measurement is bounded to 20 s; past that (or on any error) the bed keeps the fallback level and the report's `music.reason` says to set `music.volumeDb` or run `audio mix-measure`, instead of the call timing out at 30 s without applying.

- **Templates and quick actions go to the user's agent, and automation leaves Last used alone.** With no agent or chat tab on show, a quick-start card (Daily vlog…) or a quick action (Survey footage, Rough cut, Write VO…) now opens New brief with the request, whose **Start & send** starts the default agent (Last used, else Claude Code) and sends once it is ready, instead of opening the first chat agent (AI Editor); a plain Shell tab on show no longer gets the request pasted either. `agent open` from the CLI or MCP (benches, tests, other agents) no longer changes **Last used**, so a bench that opened Codex no longer turns the dock into "Start Codex" / "Tell Codex what to make…" for a user of Claude Code.
- **A project opens on the Agent tab.** The right column now starts on **Agent** instead of **Inspector**, so the setup card and the agent are what a project opens with. A tab picked later (or the Inspector brought forward by selecting a timeline item) stays for the projects opened after it in the same window.
- **The setup card follows the picked agent, and Update brings Claude Code's kit up to date.** The agent dock's setup card is about the agent the user picked — the shown Claude Code or Codex tab, else the dock's default (Settings, or Last used) — instead of every agent CLI on the Mac: with Claude Code picked it says "Set up BashCut for Claude Code", its step ① counts and installs only Claude Code's kit, and a Codex without the kit no longer holds it back; it covers both only when the pick is neither or its CLI is not on this Mac. `ui view` reports the card's `agentSetup.agents`. Update (the card's and Settings › Agents › Claude Code's) now always runs `claude plugin update` after `claude plugin install`: Claude Code 2.x answers install with "already installed" and exit 0, so the plugin kept its old recorded version (e.g. 0.1.24 against kit 0.1.54) and the row stayed "Older kit set up: update it" after every Update. After the card's Update only the CLIs are checked again, not the plugin registry, so "Installing…" ends as soon as the kit is set up.
- **New brief takes footage.** The sheet has a **Footage** row: **Project media · N** when the project has media, a chip per added file or folder (a folder shows its count of video, audio and picture files; ✕ removes it) and **Add files or folder…**, a panel that takes both. Files and folders can also be dropped anywhere on the sheet. Templates made from what was shot (vlog, travel, food, short, talking head, clips, review, ad, montage, tutorial) show the row and say so in orange while there is no footage at all; explainer, news, promo, B-roll and a request written from scratch show it as optional; other edit and finish templates show it only once footage is added. The request is sent with a last line `Footage to import: \`~/trip/\` (folder, 42 media files), …` for the agent to import, shown under the request before sending. Recent briefs keep their footage, so sending one again brings it back. `ui respond footage` on the `ask` sheet opens the panel for agents and tests (answer it with `ui respond --path`).
- **The agent dock's brief bar and setup card.** Under a terminal or plugin view tab, New brief is now a full-width bar that looks like a message field — "Tell Claude Code what to make…" (vi "Giao việc cho Claude Code…") with ⌘K on the right — instead of a small pencil icon; the quick actions stay above it and chat tabs keep their composer. The "1 setup step for the agent" row is replaced by a two-step card, "Set up BashCut for Claude Code · 1 of 2 done", open the first time a kit version is seen: ① **BashCut skills** ("Claude Code learns how to cut, caption, review and export in BashCut") with **Install skills** / **Update** (what `agent setup` does), then "✓ v<kit>"; an agent tab that was already running gets **Restart Claude Code tab**, which closes it and starts it again on the same conversation so the CLI loads the new skills. ② **Editing tools** (captions, Vietnamese voice, motion graphics, stock search, with the download size from the registry) with **Install…**, which opens Plugins › Browse with the Recommended (starter) bundle's approval — the button form of `/bc:setup`, without the agent; it is done when the bundle's default plugins are installed and healthy. A step that does not apply (no agent CLI, no registry) is left out of the count; when the last step is done from the card it stays, all ticked, until **Done**, and the chat agent's API key row stays as an extra row. **What's this?** opens Settings › Agents; **Later** (`agent.kit-later`) folds the card into a **Setup 1/2** chip in the dock header until a newer kit, and the chip opens it again. New UI actions `agent.setup-show`, `agent.kit-install`, `agent.tools-install` and `agent.restart-tab`; `ui view` reports `agentSetup` (done, total, skills, tools, kitVersion, card: open/collapsed/chip/hidden, restartTabs).
- **BashCut accepts Claude Code's Bypass Permissions warning in its own sheet.** BashCut starts Claude Code with `--dangerously-skip-permissions`, so on a config that never accepted it Claude showed "WARNING: Claude Code running in Bypass Permissions mode … No, exit / Yes, I accept" in the dock. The folder sheet now also says that BashCut runs Claude in Bypass Permissions mode and that Allow accepts it once for every project; when the folder is already trusted it asks "Let Claude run commands without asking?" on its own. Allow writes `skipDangerousModePermissionPrompt: true` to Claude Code's user `settings.json` (in `$CLAUDE_CONFIG_DIR` or `~/.claude`), as Claude's own "Yes, I accept" does, merged and replaced in one step; the older `bypassPermissionsModeAccepted` in `.claude.json` also counts. With a fresh config folder, one Allow now starts Claude without any menu. Only the user answers (`agent-folder-trust`, `userOnly`); Not now does not start Claude.
- **BashCut asks before an agent works in a new folder.** Before Claude Code or Codex starts in a folder it does not trust yet, a BashCut sheet asks "Let Claude Code work in “folder”? It can read, edit and run files there." with **Allow** / **Not now**. For Claude Code, when the project sits in BashCut's projects folder outside a git repository, **Always for every project in “Projects”** is ticked by default, so one Allow trusts the whole projects folder (Claude Code also trusts the folders below a trusted one) and later projects are not asked again; untick it to trust only this folder. Codex always starts in BashCut's own `agent-workspace`, so it is asked once. Allow records the answer where the CLI reads it, so its own trust menu never shows: Claude Code's `projects[<folder>].hasTrustDialogAccepted` in `.claude.json` (`$CLAUDE_CONFIG_DIR` or next to `~/.claude`), Codex's `[projects."<folder>"] trust_level = "trusted"` in `$CODEX_HOME/config.toml`, keyed by the git root or the folder, under the path as given and with symlinks resolved. The file is merged and replaced in one step, keeping its other keys, comments and permissions; a `.claude.json` that is not JSON or a `config.toml` with an inline `projects` table is left alone. Trust is checked again right before each launch and written again without asking when a running CLI saved over it. Not now does not start the agent. Only the user answers: `ui dialog` lists it as `agent-folder-trust` with `userOnly`, and `ui respond` refuses it. When the write does not take, the CLI's menu shows and New brief still waits for it as before.
- **New brief picks its agent and waits until it is ready.** The sheet's footer has a **To** menu next to Send: the open agent tabs and chat agents, then **Start new** for each agent (Claude Code, Codex, terminal plugins). Without a pick it sends to the chat or agent tab on show, else the default agent's tab, else it starts the default agent (**Start & send**) — never to a plain Shell tab, and Send is no longer disabled when no agent runs. A started or busy terminal gets the brief only once it takes input: it has printed and stayed quiet for 0.8 s and shows no menu (Claude Code's and Codex's "trust this folder", any "Enter to confirm"). When a menu shows, the sheet closes so it can be answered in the dock, the status bar says so, and the brief follows the answer; it is recorded in Recent only once pasted. The footer shows **Starting …** / **Waiting for …**, Cancel stops a waiting Send, and a failure (CLI not installed, agent quit, chat agent still answering) stays in the sheet with the brief. Settings › Agents › **Default agent** gains **Last used**, the new default: the agent last opened or sent a brief to, else Claude Code (before, Codex). Handoff to a new tab waits the same way instead of a fixed 0.7 s.
- **Agent A/B bench.** `scripts/bench-agents.py` runs one editing brief with the Claude Code and Codex agents launched exactly as the app launches them and compares tokens, context over time, tool calls by name (`context get` counted apart), wall time, idle wake-ups, questions to the user and the final `review run`; a manual bench, never part of the tests. First results are in docs/status/implementation.md.
- **Finalising draft graphics keeps the draft audit (#634).** After `bin/graphic plan --final` or `rerender --all --final`, the critic's draft audit of the drafts still counts, so the export no longer stops at `audit_missing` for a second audit. The timeline fingerprint counts an item that shows a plugin graphic (media with `data.graphics`) by the graphic's recorded inputs without `draft`, `fps` and `frames`, its in-point in project frames, and "to the end" when it plays to the render's last frame, instead of by its media ID, so the draft→final swap (new media, rescaled in-point, a played-through length off by a frame) leaves it unchanged. New variables or any other edit of the item still make the audit stale.
- **Final exports refuse draft graphics (#634).** An agent's `export start` with any preset but quick-draft now fails with `graphics_draft` when a timeline item uses media a graphics plugin rendered as a draft (`data.graphics.draft: true`, HyperFrames `--draft`: 15 fps, faster capture). The error lists each draft's media, name and items in `data.drafts`, and `remediation.command` is the plugin's final render: `bin/graphic plan --final` when every draft is a `plan.cut` graphic's media, else `bin/graphic rerender --all --final`. It is checked before the draft-audit guard; quick-draft exports and the user's own exports are not blocked, and media without `data.graphics` is ignored.
- **New brief replaces Ask agent; the dock suggests what to do next.** ⌘K now opens **New brief** ("Giao việc"): 25 request templates in three groups (Make a video 13, Fix the edit 8, Finish 4), each with an SF Symbol, the agent kit recipe it belongs to, chips and text fields instead of `[brackets]` (chips take an **other…** value), and an editable request whose hand edits survive chip changes until **Reset to template**. Templates that fit the project carry **FITS** and come first, the rest are dimmed; the search ignores case and accents ("dich" finds "Dịch phụ đề"). The list also has **Recent** (last five sent in the project, `.bashcut/briefs.json`) and **Saved** (**Save as template**, every project on this Mac). The project state (none, footage, one long talk, timeline, selection) drives the dock: an empty tab or chat shows quick-start cards for it (the first wide) and **All templates (25) →**, and the buttons under the input change with it (New project/Open…; Survey footage, Rough cut, Write VO; Cut short clips, Remove silences, Captions; Review, Export draft, Grade; Fix this clip, Replace shot, Review this part), running the editor action where one exists. The chat input has **Templates**, **Frame** and **Expand…**, and `/` lists the chat commands and the templates under headings, inserting the filled request with the first empty field selected. The separate Ask agent… button is gone, the agent skills and API key banners are one **N setup steps** row, and the Workspace… row moved to the dock's + menu. `ui view --chat-draft TEXT` puts text in the shown chat agent's message box as if typed (a leading `/` opens the menu), so agents and tests can drive the composer.
- **Music bed at one fixed level; ducking only for long silences (#630).** A `plan.cut` music without `duck` is now one fixed bed: `plan apply` renders the built edit's speech and the bed at 0 dB, measures both and sets the bed's `volumeDb` `underVoiceDb` (default 16 dB) under the voice's integrated loudness, and turns the Music layer's ducking off; the result's `music` reports `voiceLUFS`, `musicLUFS`, `underVoiceDb` and the chosen `volumeDb` (−20 dB with the reason when there is no voice or the measurement fails). `volumeDb` in the list is kept as given. Ducking comes on only with `duck: true` or `duckDb`, and then gaps between lines shorter than `duckMinGapSeconds` (default 2.5 s) keep the music down, so it rises only in a long silence instead of pumping between lines. Music layers get the same hold as `duckMinGapFrames` (unset is 2.5 s, 0 rises in every gap; Inspector › Audio › Hold gaps under). Review no longer suggests turning ducking on (`ducking-*` is gone) and instead warns about a pumping bed (`music-pumping-<track>`: rises in gaps under 2.5 s more than 4 times a minute, fixed with the hold); `audio mix-measure` adds `musicBeds` per Music layer (ducking, rises, shortRises, movesPerMinute, pumping).
- **Plugin view layouts `split` and `nav`, and dragging online results (P2-A2, #590).** A `split` component lays 2 or 3 columns side by side with `widths` in points or `"flex"` (`[200, "flex", 280]`); below 900 pt its fixed columns fold into disclosures, and when it is a view's whole body in a window, sheet or dock tab it fills the height with each column scrolling on its own (`views.split`). A `nav` component lists groups of entries with an icon and a count and sends `select` (`views.nav`). A grid tile with `drag: "download"` (an online result not in the library yet) can be dragged onto the timeline: on drop the view gets a `drag` event, the plugin downloads the item and answers with `libraryItem`, and BashCut places it where it was dropped while the view stays open (`views.drag`). `plugins view-event --type drag` sends the same event and returns the `libraryItem` without placing it.
- **Plugin API 11: plugin views in a window of their own (P2-A1, #589).** A plugin view can say `"location": "window"`: it opens in a non-modal window (75% of the editor window, at least 900×600, size and position remembered per view), so the timeline stays editable while it is open. Closing the window keeps the view's components, inputs, state and scroll position until the project closes or switches (a sheet still starts fresh). **Dock** shows the same view over the viewer instead (**Undock** or Esc leaves it). `ui dialog` lists the window as `plugin-window` with `"window": true`; it never blocks `ui action` or other dialogs and is answered by id (`ui respond --dialog sheet:plugin-window:<plugin>/<view> dock|undock|close`); `plugins list --views` adds `windows` and `docked`. A window view needs `apiVersion` 11; older apps keep the plugin's previous (sheet) version through `minApiVersion`.
- **plan apply no longer stacks a second set of captions after captions group; clip volume (#628).** `captions group` dropped the `planCut` mark from the cues it made, so the next `plan apply` (even a music-only `--patch`) did not see them as its captions, built a fresh set from the transcript and every cue showed twice. Grouped cues now keep the mark, and built captions carry `planCaptions`, a digest of what was generated: a later apply that would generate the same cues keeps the ones on the timeline, hand-grouped or not (`captionsKept: true`), and one that would generate different cues replaces them all. Speech captions the plan did not build where its captions go (grouped before this fix, or from `captions generate`) are an error naming them, never a second set. New `bashcut clip volume [<item>] [--items a,b] --db <dB> --base-rev <rev>` (MCP `bashcut_clip_volume`) sets `volumeDb` on clips and their linked sound in one undo step, skipping items without sound. An unknown `timeline apply` op now names the nearest one (`setItemProperties` → did you mean `setProperties`?).
- **Transitions in plan.cut (#623).** A clip or graphic row takes `transition` (the cut into it) and a title or graphic row `enter`/`exit` (its own In and Out), each `"kind"`, `"kind:frames"`, `{kind, duration, easing}` or `"none"`. `plan apply` keeps the cut transitions and In/Out set by hand (`clip transition`, the inspector) on the items it rebuilds — a captions patch or a `graphic plan` re-render no longer drops them — unless the list sets them or the row is gone. `plan check` lists every entry it cannot read in one result (`entry-invalid`, one per entry) instead of stopping at the first, and reports `transition-no-cut` and `transition-too-long`.
- **Agent run panel fits the timeline.** On a short timeline the run panel no longer grows over the viewer (its header was hidden) or crowds the agent change toast: the toasts keep their size and the panel's stages scroll in the height left. Stages a plan adds have names (Visuals, Graphics, Stock images…); any other stage ID shows as words.
- **No AI labels or licence records by default.** Review no longer warns about a generated picture without a disclosure label (`ai-undisclosed`) unless the user turns on `review.credits`; `image disclose` is for when the user asks. Agents record no licence, source or author unless the user asks (#620). AI disclosure is the platform's upload toggle.
- **Effect previews play on hover (P2-B3).** An effect preset's saved GIF (from `library save-selection`) now shows its first frame in the Effects panel and plays only while the pointer is over the tile, in the grid and the list, like the transition tiles (same tile, N4); a preset without a GIF keeps its icon. Before, every GIF played all the time.
- **Transition preview cache cleanup.** The first time the Transitions panel shows after launch, it deletes, off the main thread, the cached previews (GIF and poster) in `~/Library/Application Support/BashCut/TransitionPreviews` that no built-in kind and no transition preset (of any scope) shows any more — after a motion or easing change or a removed preset — and half-written files left by a render that stopped. Past 32 MB (about 250 previews) the previews shown longest ago go too. A preview that is rendering is never deleted. The Filters panel's look stills are kept in memory only, so they need no cleanup.
- **Transitions as the In and Out of text, stickers and overlays.** An item that is not part of a video cut — a caption, a title, a sticker, a graphic, an overlay clip — can use any of the 39 transition kinds as its own entrance and exit: the item's new `enter` and `exit` fields (`{kind, duration, easing, motion}`), played inside its own frame (the text box or the placed picture), so an iris opens on the text itself and a wipe takes it away. The exit plays the kind's outgoing side; a wipe, shape or slide runs backwards, and a whip or zoom also fades the item. It works with keyframes and the animation presets, preview and export draw it the same way, a cut transition at the same clip edge wins, and a split keeps the In on the left part and the Out on the right. Inspector › Video and › Text have In and Out pickers grouped like the Transitions panel, with length and easing; clicking a Transitions tile with a text or overlay item selected, or dragging a tile onto one, sets its In. `bashcut clip transition --side in|out|both --kind K` does the same; agents use `setProperties`.
- **Looks on the current frame and moving transition previews (P2-B3).** Each tile in the Filters panel (library looks, LUT looks and the project's 3D LUTs, in grid and list) shows the viewer's frame at the playhead with that look applied, graded the way export grades a clip. The still is small (320 px), drawn when a tile shows, cached per frame and look, and dropped when the playhead settles at least 6 frames away or the timeline changes; nothing is drawn while playing or scrubbing, and an empty project uses a sample still. Each built-in transition (all 39 kinds) and each transition preset gets a looping preview that plays on hover: it is rendered on this Mac the first time it is shown, from two bundled sample stills (about 9 KB, drawn by `scripts/make-transition-samples.py`) through the compositor's own clip path, and kept in `~/Library/Application Support/BashCut/TransitionPreviews` keyed by the motion data and easing, so a preset with its own `motion` gets its own preview. Nothing is downloaded. The tile shows the kind's icon until the preview is ready, then the frame that shows the move best. Built-in transitions and library presets now use the same tile (N4). Online resources' `fetch_luts.py` gives LUT looks readable titles ("Bleach bypass 1", "Kodak T-Max 400") and keeps the file stem as the ID.
- **39 transitions in groups.** The Transitions panel groups the built-in kinds as Fade, Whip, Wipe, Shape, Crash, Roll, Arc, Infinite, Screen, Seamless and Stylized (the technique names of eyecannndy.com/technique/transition, plus its most used cut techniques: flash cut, light flash, double exposure, colour shift, kaleidoscope) and adds 29 kinds: `flash`, `dip-black`, `double-exposure`, `whip-right`, `whip-up`, `whip-down`, `wipe-right`, `wipe-up`, `wipe-down`, `barn-door`, `slide`, `slide-up`, `iris`, `diamond`, `crash-zoom`, `crash-out`, `roll`, `roll-right`, `arc`, `arc-right`, `infinite-zoom`, `infinite-out`, `screen-in`, `screen-out`, `blur`, `seamless-zoom`, `flicker`, `color-shift` and `kaleidoscope`. `whip` now smears the picture along the move. Transition `motion` gains the properties `blur`, `blurX`, `blurY` (motion blur), `zoomBlur`, `revealFromRight`, `revealFromTop`, `revealFromBottom`, `revealCenter`, `iris`, `diamond`, `hue`, `saturation` and `kaleidoscope`, so a custom kind can use them too. Preview and export draw them the same way.
- **Resizable, widenable library panel with tile size, list view and drag to the timeline (P1-10).** Drag the panel's right edge to resize it between 300 and 520 pt (372 pt by default on a screen of 1680 pt or more, 300 pt below; it gives way to the viewer in a small window); the expand button in its title widens it to 760 pt over the viewer with a category sidebar (All, Recent, Favorites, Mine, each pack), and Esc or the same button leaves it. The Text, Stickers, Effects, Transitions and Filters panels get a footer with a tile-size slider and a grid or list switch, remembered per panel; text styles, effects, looks and transitions now show a picture with their name under it in the grid, and a "+" on hover places an item at the playhead. Every library tile can be dragged onto the timeline: sounds, stickers, text styles, looks and clips are placed where they land, and an effect or transition is used on the clip under the pointer (or the selection). New: `ui view --library-width|--library-wide|--library-layout|--library-tile-size` and `libraryLayout` in the view state.
- **Library home view with Favorites and Recent (P1-9, D5).** Each library panel opens on a short home view instead of one long grid: Recent (the last 20 items placed or applied in this project, any scope; kept per project, so it starts empty in another one), Favorites (starred on this Mac, global, so they follow you to every project), then one section per pack with two rows of tiles and "See all n ›" (the section headers fold; a pack's plugin and folder badges are hidden inside it, and saved packs come before shipped ones). A star on every tile (on hover) and in the context menu adds or removes a favorite. Under the search field, chips All, Mine, Packs (with counts) and Online (opens the plugin search; a search with no match offers it too) replace the Scope filter, and the Media panel's source menu is now chips with counts (Footage, Project, Shared, Selects, Clips). New: `library favorite <id> [--scope] [--off]`, `library list --favorites|--recent`, `favorite` on `library list`/`get` items, and `ui view --library-source mine|packs --library-collection recent|favorites`. Favorites (`favorites.json`) and Recent (`recent.json`) keep unknown fields; moving an item between the project and This Mac keeps its star.
- **An empty Agent tab with one obvious action, and a one-line skills banner (P1-8).** Before any agent runs, the tab shows one primary button (Start or Continue the default agent), an Other agents menu (AI Editor and the other chat agents, the other terminal agents, New conversation) and the one-line explainer, instead of a column of buttons. The agent skills banner shows its full card the first time a kit version is seen, then takes one line ("Agent skills: Set Up · Details…", Later as before) until a newer kit comes out.
- **The Inspector names what is selected, shows only the tabs that apply, and shows the project when nothing is (P1-7).** The header has the item's kind colour bar, its name (caption text, file name or adjustment look, never the UUID), "Graphic · V2 Graphics" and the range as timecodes with the length (`00:12:05 – 00:15:20 · 3.5s`); the ID is in the context menu (Copy ID). A graphic (a still or an overlay without sound) has Video and Color tabs only, a clip Video, Audio, Color and Speed, text and captions Text and Video, audio Audio and Speed, an adjustment layer Color; a tab that does not apply falls back to the first one without changing `ui view --inspector`. With nothing selected the Inspector lists the project: format and platform (the toolbar's menus), frame rate, how clips sit in the frame, length, sections (the Sections popover) and outputs.
- **One right column: Inspector and Agent as tabs (P1-6).** The fixed 220 pt Inspector and the resizable agent dock are one column of 300 pt (340 pt from a 1680 pt window) with an Inspector tab and an Agent tab; the Agent tab shows a dot while the agent works (orange when it waits for you). On the Inspector tab the column sits beside the viewer and the timeline spans the full window width, which gives the viewer about 628 pt at 1280×800 (445 before); on the Agent tab it runs the full height beside the timeline, because a terminal needs it. Pop out moves the agent into its own window, where the tab says "Agent is in its own window"; selecting a timeline item brings the Inspector forward unless the Agent tab was picked in the last 2 s; ⌘J selects the Agent tab and a second ⌘J hides the column. `ui view --agent-dock` and `--inspector` work as before, `ui view --right-tab inspector|agent` selects the tab, and the view state adds `rightTab` and `rightColumn`
- **A status bar with a jobs indicator, and notices that clear (P1-5).** The bar under the editor now shows the selection (`1 selected · formula`, `3 selected`), the project length, and — only while something runs — `▶ 2 jobs` (one job shows its progress). Click it for a popover with each running job's progress, Open (its tool in the Tools panel, else the run panel) and Cancel; the run panel's job rows are the same view. A one-off notice (`ui action notify`, "Captions generated", an error) still appears in the bar but clears after 8 s instead of staying until the next one. Online resources' **Open** action no longer answers "Opened Online resources" (plugin 0.0.3)
- **A Tools panel: Auto captions, Voiceover, Beat detection and plugin tools (P1-4).** The Tools tile in the rail opens a list of tools with the selected tool's card under it. A card has a title and provider badge, the main fields, **Advanced (n)**, **Run on** (Selected clip or This project for captions and beats; the clip's own part of the source is transcribed or analysed) and Run, and captions and beats now run as background jobs. The forms moved out of the Text panel (Auto Captions, with Import and Export SRT under Advanced) and the Audio panel (Beat Detection), so Text opens on the text presets and Audio on the audio library; Voiceover keeps its takes and recording controls. A plugin's `kind: tool` view and its `tools` actions are listed too: an action shows as a card with its parameters, the `advanced` ones folded. Open one with `ui action panel captions|voice|beats` or a tool id
- **The rail: eight asset panels, Tools, and More (P1-3).** The left rail now lists Media, Audio, Text, Stickers, Effects, Transitions, Filters and Brand (⌘1…⌘8), a divider, **Tools** (⌘T) and, when a ready plugin has a panel, **More** — a popover with one row per plugin panel (Online resources and the rest), which opens in the library column as before. Voice left the rail: Voiceover is the first tool in Tools, together with each plugin's `kind: tool` views and `tools` actions (`ui action panel voice` still works and opens that tool; `ui action panel tools` opens the panel; `ui view` reports the shown `tool`). In a window shorter than 900 pt the tiles drop their labels (tooltips instead), so every item fits at 1280×800. The `panel.*` action placements are unchanged, and `panel.tools` is new. Plugin shortcuts can no longer take ⌘1…⌘8 or ⌘T
- **Developer mode hides the sample plugins (P1-2).** Settings › General › Developer (off by default) controls the example plugins: a plugin whose manifest says `"category": "sample"` (the Views Example) no longer gets a tile in the rail, a dock or Inspector tab, menu, toolbar, context-menu or panel actions, or a Plugins › Browse card until it is on. The plugin stays installed, and `plugins list`, `plugins run`, `plugins show-view` and the MCP tools still reach it, so tests and agents are unaffected. `docs/guides/plugins.md` lists `sample` as a category
- **Plugin API 10: tool views, the `tools` placement and `advanced` options (P1-1).** A plugin view can say `kind: tool` (listed in the Tools panel, no rail container needed), an action can use the `tools` placement (its `params` become a tool card), and an action parameter can be `advanced: true` (kept under "Advanced"). All three default to the old behaviour, so existing manifests decode and run as before; a manifest that uses them with an `apiVersion` below 10 is invalid. The host lists the new `tools` feature, and `docs/guides/plugins.md` and the architecture spec describe the contract. The Tools panel itself follows in later changes
- **A timeline toolbar in four groups, folded empty layers, and no empty capsules on top (P1-11).** The strip over the timeline is now Split and Delete, a compact Add menu (the four layer kinds, moving or deleting the selected layer), Snap, Sections and Waveforms with labels, and zoom with Fit; every button's tooltip names its shortcut, and Ask agent stays in the Agent menu. Layers without clips fold into one row under the last layer ("V1, V3, A1 empty", a count in the compact header) that shows them on click; the main layer and the selected layer are never folded, and "+ Add track" ends the list. The layer header is wide (names) from a 1280 pt window until you drag or switch it. In the top toolbar the activity capsule is gone: the project name carries a save dot (green saved, grey edited, revision in its tooltip), the Agent capsule shows only while the agent works, waits or has finished, and the Export report link moved to ☰
- **Toasts stay clear of the agent dock; Export stays cyan in an inactive window.** The agent change and export toasts now sit at the bottom right of the timeline, instead of over the agent input or the viewer transport; "1 timeline change" is singular (English plural variants, Vietnamese unchanged); the Export button keeps its cyan fill when the window is not active.
- **The viewer shows where a vertical picture ends, and one timecode everywhere.** The program frame gets a thin 1 pt border (stronger while Safe area is on), so a 9:16 picture no longer melts into the black panel. The transport bar, the full-screen preview, the source viewer length and the section list now show `mm:ss:ff` like the timeline (`00:00:00 / 00:50:15`) instead of decimal seconds.
- **Names under sticker tiles, and no blank tile.** Sticker and clip tiles in the Library show the item's name under the picture (one line, middle cut, full name on hover) and are wider to fit it; a tile whose picture is missing or will not load shows its kind's icon instead of an empty box. A transparent graphic movie (a placed flow diagram, a mind map) used to draw its empty first frame as a grey tile: the tile now takes a frame from the middle of the movie that has something in it, and falls back to the icon when none does. The plugin mark is dropped from items under a plugin's own heading, which already names it.
- **A larger plugin sheet.** Sheets for plugin views (Online resources and other `location: sheet` views) open at 1100×720 (at least 900×600) instead of 480×520, so a results grid shows 3 rows of 4 tiles or more and gains columns as the sheet grows, and the plugin name next to the title is hidden when it only repeats the title.
- **Plugins are trusted automatically by default.** Settings › Plugins › Trust plugins automatically (on by default) installs, links and sets up plugins without the "Install …?" / "Set up …?" sheet, also when an agent runs `plugins install`, `plugins setup` or installs a bundle, and plugins in the user plugin folder are trusted as they are and again after their files change, so a linked plugin needs no Trust after Reload. Plugins that come with a project still ask, and a plugin turned off stays off. Turn the switch off to approve every install and change as before.
- **Plugin view grids and `cli` host calls (#567).** Plugin views (API 8) get a `grid` component (host feature `views.grid`): tiles of list-style items with a thumbnail filled to `aspect` (or an SF Symbol), a coloured badge, an audio preview, a title, a subtitle and up to three buttons, `cellWidth` 64–320, one or several `selected` ids, `empty` text and a `more` load-more button; cells send `select` and `action` like list rows, the load-more button `click` with value `"more"`, and cells drag like list rows. View and action requests may make the host call `cli` with `{"argv": [...]}`, the words after `bashcut`, which runs that command exactly like a direct call (same allow-list and own-plugin rules), so a plugin's scripts that shell out to `bashcut` run unchanged through a stand-in on their PATH; `jobs.wait` is now allowed for plugins too.
- **Generated illustrations with a style lock and AI disclosure (#550).** A new `image.generate` plugin capability (core knows no model): `image generate` sends every scene of a video in one job (a JSON file of `[{id, prompt}]`, or `--prompt`) with the project's style lock and frame size, adds each picture to the media pool with `generated: true` and its prompt, and returns paths, media IDs, failed scenes and one contact sheet. `image style` keeps the lock (`illustration` {style, references, seed, disclosure}) on the project; a brand kit may carry one too. `image disclose` puts the disclosure label (the lock's or the brand's) over every generated picture that lacks it, and review warns (`ai-undisclosed`) until it does. `image generate-list` lists the generated pictures, the lock and provider availability; `doctor` says what to install when no plugin provides `image.generate`. Plugin authors: see `image.generate` in docs/guides/plugins.md.
- **Mascot poses from a photo or one reference (#551).** `library brand-pose <kit> --pose wave --image photo.jpg` cuts the subject out (`vision.cutout`), saves it as a sticker and stores it as the kit's pose; `--generate --pose think,point` makes the missing poses with an `image.generate` provider from the kit's first pose (or `--reference`) and cuts them out, in one job. The brand kit sheet has the same as From picture… next to New pose.
- **Measuring many library sounds at once, and frames of files outside the project (#566, #556).** `library analyze` takes several IDs separated by commas and measures them one after the other in one job (result `items` [{id, item, measured, notes} or {id, error}], `analyzed`, `failed`); an audio.loudness, audio.beats or audio.energy provider busy with another job is now waited for (up to 5 minutes) instead of refused with "already running". Music also gets `beatConfidence` (0…1, when the beat provider gives one) and `energy` {rangeDb from its quiet to its loud parts, liftAt, peakAt seconds}, saved in the item's params, so a bed is chosen by numbers. `media frames --file /abs/video.mp4 [--count N|--at S,…] [--size PX]` reads frames of a video that is not project media (a stock candidate) with AVFoundation, so candidate sheets need no ffmpeg. Live run (kit over-fetch): 105 sounds measured by one job; 12 photo slots × 8 and video tiles of 3 frames.
- **My voices: saved cloned voices, labelled apart from presets (#532).** The Voice panel has a voice picker with My voices (saved clones) first, then each provider's presets, each labelled "Name · Clone|Preset · Plugin", and "+ Clone a voice…": record now, choose a file or use the selected clip; BashCut picks the best clean stretch inside the provider's reference range (most speech as Apple's on-device sound classifier hears it, so talk over street noise counts, with levels as the fallback; fewest pauses, no clipping, no music; refuses a source that is too short, too quiet, mostly silence, clipped or with music under the voice, with the reason), shows the window and its checks, previews a test sentence with the clone, and saves it after the consent box (my own voice / I have permission) and a name. Clones live in `~/Library/Application Support/BashCut/Voices/<id>/` (voice.json and the trimmed reference.wav) and work in every project; choosing one sets the project's `voiceClone`, a preset sets its plugin's `voice` option as before. Providers declare `providers[].clone {minSeconds, maxSeconds, formats}` (host feature `voice.savedClones`, API 9; `clones: true` alone means 3–8 s), and a line said with a saved clone sends `reference {path, voice, name, language}` with `cloneConsent: true`; providers that do not clone never get one. CLI/MCP: `voice clone-add --name N --from MEDIA|FILE [--at S --to S] --consent own|permission [--language L] [--provider P]` (asks the user before saving), `voice clone-list`, `voice clone-remove ID` (asks too), `voice use ID|default`, `voice speak --voice ID`, and `capabilities get --voices` rows carry `kind` (preset|clone) and `source` (provider ID or my-voices) plus `projectVoice`. A second speaker is not detected yet.
- **No false socket timeouts on slow calls.** The CLI and MCP bridge gave up after 10 s and reported "Socket closed or timed out" though the app finished the call: in a bench run `project create` answered in 10.0 s while the app was busy and `review verify all` took 11–14 s re-sampling the picture, so the agent re-ran them (once two `review verify` at a time). Calls now wait 30 s, `review.verify` 115 s like `review run --measure`, and a late answer says the call may still finish and to check its result before running it again.
- **Recent projects you can tell apart and search (#529).** File › Open Recent and the toolbar's project menu add the parent folders to entries that share a name (`project — b2`, `project — lesson1`), and end with View All… (⌃R, also on the Welcome screen): a window in the command palette's look that lists the last 50 projects (the menus keep 8) with the project name, a shortened path and when it was last opened, and searches them by name or path as you type, letters in order. ↑/↓ move, Return opens, ⌘Return reveals in Finder, Esc closes; each row has × to remove it and a menu with Reveal in Finder and Copy Path; a project whose file is gone is greyed out with a warning icon. `project recents` now returns those rows (`name`, `path`, `lastOpened`, `exists`) instead of bare paths, takes `--query` and `--remove PATH`, and `ui action project.show-recents` opens the window. The list from earlier builds carries over, without names or dates until each project is opened again.
- **Full-screen preview (#530).** The viewer's transport bar ends with a full-screen button (View › Full Screen Preview, ⌥⌘F, `ui action viewer.fullscreen`) that plays the edit alone in a borderless window over a whole screen, on a second screen when there is one: the program picture aspect-fit on black at the screen's size, with the safe-area and plugin overlays when the viewer shows them. It shows the viewer's own player, so the playhead, play state and audio are the same and nothing decodes twice; the viewer shows a note meanwhile. A transport (play/pause, scrubber, time, loop, close) appears when the pointer moves and hides with it. Space plays, ←/→ step a frame (⇧ a second), J/K/L play back, stop and forward (again for 2× and 4×), and Esc or ⌥⌘F return to the editor at the same frame. `ui view` reports `fullScreen`.
- **Layer labels in the text timeline.** `timeline get --format text` (and the timeline the chat agents get as context) starts each item line with its layer's label (`V1 MAIN c1 0-90 …`, `A3 MUSIC …`), so the `--track V2` an agent passes matches what it read.
- **J/K/L in the editor, and J that plays backwards (#530 follow-up).** J did nothing in full-screen preview: AVPlayer refuses a negative rate on BashCut's compositions though the item reports it can play in reverse, and the one-second fallback never ran. J now plays backwards on a frame clock (silent; again for 2× and 4×, stops at the start), K stops and L plays forward (2×, 4×), in full screen and now also while the timeline has keyboard focus, from Playback › Play Backwards / Stop / Play Forwards, and as `ui action playback.shuttle-back`, `playback.stop` and `playback.shuttle-forward` (or `ui action j`/`k`/`l`). `ui view` reports `playing` during reverse too.
- **Compact layer header with V1/A1 IDs (#531).** The timeline's layer header is 78 pt by default instead of 140, so the clips get the room: per layer a short ID (V1… visual layers from the back, A1… audio layers from the top; Main's chip is filled), its icon and small hide or mute and lock switches. Hovering the ID shows `V3 · Captions`, double-click renames the layer, and the selected row shows its name. Drag the header's right edge out for full names (Timeline › Compact Layer Header or `ui action timeline.header-compact` toggles; the width is remembered, and `ui view` reports `headerCompact` and `headerWidth`). The IDs come from the layer order and are not stored; the Inspector, the clip menu's Lock item and the Audio panel's layer picker show them, `timeline get` reports each track's `label`, and every `--track` accepts a label (`layers set A1 --muted`). Solo is not offered: layers have no solo switch yet.

- **Placeholders for blocks being made (#534).** A slow block shows at once where it will land and fills in when ready: a voiceover take placed with `voice speak --choose` (at its frame on the Voiceover layer, sized from the text) or replacing an item, captions over the clips of their media, and a `graphics.render` of a plan.cut graphic at the span the plan gives it (new `PlanCut.graphicSpans`); each as a dashed item with a moving shimmer and its state ("Graphic · rendering 40%", "Voiceover · queued, 1 ahead"). Media that converts, makes a proxy or is transcribed gets a badge on its library tile with progress; a render or take with no place yet gets its own library tile. Where the playhead is over a placeholder the viewer shows a neutral card with its label. A failed placeholder stays with the error, Retry (runs the same command again) and Remove; a running one can be cancelled from its menu. Placeholders are derived by the app from the commands and jobs it already runs: agents declare nothing, and nothing is saved in the project or exported.
- **What the agent changes, where it works (#534).** Items an agent adds or changes flash briefly on the timeline; a run panel step that changed items has Jump (selects them, moves the playhead and scrolls there, as Show Changes does). Follow mode (`ui action run.follow`, on for each new run the panel follows) scrolls the timeline to the agent's placeholder or latest change and turns off as soon as you scroll the timeline. While an agent works, the clips attached as its scope show as an orange dashed band ("Agent's scope"), so it is clear where editing is safe.
- **Agent button and live run panel (#534).** The toolbar has an agent button that shows what the agent is doing (idle, working with the current stage or job, waiting for you, finished); a click opens the run panel and a second click closes it (`ui action run.toggle`), in any state, also when no stage was reported. The panel lists the agent's recent steps (the edit, UI and privileged commands it sent, following the jobs they started: queued, running with progress, done or failed with the error) and the other running jobs with Cancel, points to the question card when the agent waits for an answer (or names the gate, held edit or approval it waits on), and has Stop (`ui action run.stop`: cancels the agents' jobs, stops chat turns and presses Escape in the terminal agents that sent requests in the last two minutes). All of it is derived by the app from the requests and jobs it already sees: agents send nothing extra, and no command result, `jobs status` or the agent instructions grow.
- **Setting the language after creation.** `project format --language <tag>` (none clears it) sets the content language, which the kit tells agents to do once footage is transcribed; no command could. A transcript made while the project has no language keeps the language the provider heard (Whisper returns it), is reused, and `plan check` warns `content-language-unset` naming it (`project format --language en`). Live run: a prompt naming no language left the project without one.
- **Recipe form editor.** The effect preset recipe editor has a Form view beside JSON: a row per step with its op (a menu) and its fields as text (nested values such as `keys`, `patch` or `textStyle` as compact JSON; `$name` references and text fields stay text), steps added from a menu, removed and moved up or down. Both views edit the same recipe and are checked as typed; Save writes what `library update <id> --params` saves. An older `{patch}` preset shows as one patch step.
- **Drag library items out of plugin views (#408).** A plugin list row or `image` with `libraryItem` (a library reference, `scope:id`) can be dragged onto the timeline, where it is placed like `library place <reference> --at-frame <frame>`: the same lookup and placement (sticker, clip, sound, text preset, look), one undo step per item, on the layer under the pointer when it takes the item. CLI parity is `library place`.
- **Plan entries cite their facts.** Any `plan.cut` entry (clip, voiceover line, title, graphic, sound) may give `facts: [key]`, the project facts (`knowledge set-fact`) or claims (`knowledge set-claim`) it rests on; `plan check` warns `unknown-fact` with the keys for one that is neither, so a typo or a fact never recorded shows before the build.
- **Plugin review checks outlive the session.** The issues a plugin's `review.check` reported were lost when BashCut restarted, so `review run` showed none until `review measure` ran the checks again; they are now kept in `.bashcut/cache/review-measurements/<content key>-plugins.json` beside the picture and loudness measurements, found again for the same content, and shown only while that plugin's check is still installed and enabled. A measure where a check failed or timed out is not kept.
- **`export reveal-output`.** The result card's per-file Reveal in Finder icons had no command; `export reveal-output [--export ID|index|path]` reveals that export (the latest by default) and refuses a file that is gone. Left out of the agent instructions (it is for the user watching).
- **Backdrop and speed for several clips.** The multi-selection Inspector has the Backdrop picker (blur, colour, dim; Mixed when the clips differ) and Speed (presets and a typed value, with the shared Change clip length setting). Speed applies to every selected clip as one undo step with the single-clip rules: each clip's length follows its speed and its layer ripples, linked sound follows, freeze frames and items without media are left out. `clip speed --items a,b,c --speed 2` does the same and returns each clip's new speed and length and the skipped items.
- **Recipe editor errors in Vietnamese.** The effect recipe editor's "not valid JSON", "must be a JSON object" and "not a valid recipe" messages were always English; they are localized now (the checker's detail, which names JSON keys, stays as written).
- **Library media show the item's name.** A sticker, clip or sound placed from the library was labelled by its content-named copy (`library-<hash>.x2.mov` for an animated sticker) on the timeline, in the Media panel and the viewer; the media now keeps the item's name as `label` (new optional media field) and shows it. Media placed before keep their file name and are still reused.
- **`project set-data` answers in one line.** It echoed the whole stored value (a merged plan reached 700 KB in a live run); it now returns `{key, bytes, keys, rev}` (keys: the value's top-level keys), and `--echo` returns the value as before.
- **Cover titles read at phone size.** `export cover --title` (and the Export sheet's Save Cover) drew the title at its timeline preset's caption size (bold-outline 0.055 of the short side, about 3 % of a 9:16 cover's height); it now defaults to 0.12 of the short side (about 7 %), a starting point that `--title-size` (0.02–0.4) overrides; a long title still shrinks to fit the width.
- **`--base-rev last` survives a background conversion.** When an AV1/VP9 conversion landed and relinked its media to the converted copy, the revision moved and the agent's next edit with `--base-rev last` failed as stale though nothing it edited had changed; the relink now carries `last` forward for every session that had seen the revision before it (one that had missed a real edit is still stale).
- **Stage progress reports are never gated.** `run append stage --stage cut --text … --eta …` (status started, the command's own help example) was refused with audit_missing while G2 was skip and no strategy audit existed; only marking the rough-cut stage done needs what G2 needs now.
- **Voice checks keep the "phẩy" of a decimal Whisper splits.** Whisper writes "ba phẩy ba cây số" as two words, `3` and `,3km`; the comma was dropped, so every correct take of a line with a decimal scored under 1 with "phẩy" missing and agents re-voiced or inspected it. A number followed by `,3`/`.3` is now read as one decimal. **`skills get bc:review`** (and `bc-review`) finds the kit skill: agents see kit skills by those names (Claude Code, Codex) and the call failed with "No skill named".
- **Plugin font pickers fit the Inspector.** A `fontPicker` put its label beside the menu, so a long label (HyperFrames' "Name font (empty keeps the design font)") left the menu a few pixels wide in the Inspector; the label now sits above a full-width menu.
- **`ui view --media-source clips`.** The Media panel's Clips source (library footage) could not be chosen from the CLI or MCP.
- **`plan check` names the built edit's review errors.** The check already reviewed the edit as it would be built but only listed it under `review`, so an agent reading `problems` found captions under TikTok's caption bar only after rendering every graphic and building; one problem `review-errors` (warning) now counts them by kind with the first one's detail. `bashcut --version` answers like `app version` instead of "Unknown command".
- **Export sheet Cover row fits.** The cover title field showed its title as a second label and shrank to a few characters, and Save Cover at Playhead was cut off; the field and preset sit on one line and the button under them. The multi-selection Inspector's frame range is in Vietnamese too.
- **`ui action open quick-edit`.** The Quick Edit › Other… sheet could not be opened from the CLI or MCP ("Unknown dialog"), though `ui dialog` and `ui respond` handled it.
- **The result card counts the exported file's issues.** The card counted the review issues when the export landed, before the file itself was measured, so a black or silent stretch in it (`delivered-…`) was missing: the card said "No issues left" while `run status` and `review run` listed an error. It counts again once the file is measured.
- **Converted footage keeps its name and its place.** A clip converted on import (AV1, VP9) showed as `<media id>.mov` on the timeline, in the Media and Selects panels and the viewer's source label, and was listed under Project instead of Footage; it now shows the imported file's name and stays under Footage.
- **Two Vietnamese strings.** The agent change notice ("%lld timeline changes") and the Inspector's frame range of the selected item were always in English.
- **Text › Lines shows what a line inherits.** A line without its own font or colours showed the preset's font ("Preset (Arial Black)") and colours, while it draws with the title's own; it now shows *Title's look (System-Black)* and the title's colours.
- **Plugin views can list a capability's providers.** A view's host call `capabilities.get` was refused (not on the plugin command boundary), so the Views Example's Voice tab offered only "BashCut's choice" even with VieNeu TTS installed; plugin views and actions may now call it.
- **`export status` reports a failed export.** After an export failed, `export status` still said `completed` with the previous file, so a caller polling it never saw the failure or its error (which names the frame and item since the render-error change). It now says `failed` with `error`, `failedAt`, the preset and path, and the previous receipt under `lastExport`, until a later export finishes.
- **Dry runs show the request ID again.** `voice speak --dry-run --request-id X` (and every other provider command's dry run, `library search/generate` too) returned the request without its `requestId`, so the request a dry run showed was not the one a real run sends; it is in `params` again.
- **Recipe editor for effect presets.** Edit… and Duplicate & Edit… on an effect preset show its recipe (steps and parameters) as JSON, checked as it is typed; Save is refused with the reason while it is not a valid recipe. `library update <id> --params` (or `--as` for a built-in) saves the same object from the CLI and MCP.
- **Animated effect previews.** Saving a clip's effect as a preset (`library save-selection --kind effect-preset`, Save selection as…) now stores a small looping GIF of the clip as the timeline plays it (12 frames, 320 px) as its preview instead of one still, so the Effects panel shows the move; a still is still used when the frames cannot be read.
- **Animated stickers move.** A GIF, APNG or animated WebP sticker placed from the library (`library place`, a click in the Stickers panel) is turned into a ProRes 4444 movie with alpha beside its copy in `stickers/` (`<copy>.x<loops>.mov`, each frame held for its own delay, looped to cover the length asked or the sticker's `seconds`, at most 10 minutes), so preview and export play the animation; before, only the first frame showed. The result says `animated: true`. The Stickers and Effects panels play animated images. Lottie stays unsupported: macOS has no native Lottie renderer, and drawing one would need a third-party animation engine in the app process (AGENTS.md keeps heavy tools in out-of-process plugins); export Lottie as a GIF, animated WebP or a movie with alpha.
- **Waveforms in the Audio panel.** Each audio library item shows its peak envelope under its name, read in the background with the timeline's waveform analysis and cached in `~/Library/Caches/BashCut/LibraryWaveforms`.
- **Library paging.** `library list --offset N --limit M` returns one page as `{items, total, offset, limit, next}` (`next` is the following page's offset, null after the last; limit 1–500, 50 with offset alone); without them it still returns every match as an array. The library panels draw the first 60 matches and a **Show more** link adds 60 at a time; a new search or filter starts again.
- **Transition sounds: offset and volume.** A transition preset takes `sfxOffset` (timeline frames from the cut, −600 to 600; negative starts the sound before the cut so a whoosh can peak on it) and `sfxVolumeDb` (−60 to 12 dB, set as the sound clip's `volumeDb`). `library apply` places the sound there (never before frame 0), `library save-selection --kind transition-preset` reads both back from the sound at the cut, and the preset sheet (Edit…) shows them under Sound.
- **`library update --file` measures the new file.** An audio item's length, a sticker's kind, size and frame count and a clip's length, size and sound are measured from the new file like `library add` does, and values measured from the old one (an audio item's tempo, loudness and landmarks) are dropped instead of describing the wrong file; the result lists `measured` and `cleared` (run `library analyze` again for loudness and tempo).
- **A trimmed audio clip saves only what it plays.** `library save-selection --kind audio --item` (and Save selection as… in the Audio panel) on a clip trimmed to part of its file now saves that part as the item's file (WAV from an uncompressed file, M4A otherwise), with its length and `trimmedFrom {start, end}` in the original file's seconds; before, the whole file was saved with the whole length.
- **Freeze frames from the command line and in saved effects.** New `clip freeze [ITEM] [--at-frame N] [--off]` does what the clip menu's Freeze Frame (`ui action clip.freeze`) does, as one undo step: it holds the frame the clip shows at that timeline frame (the playhead by default) for the clip's whole length and returns `freezeFrame`, the source frame held; freezing a frozen clip picks again from its source, `--off` removes it. `library save-selection --kind effect-preset` now keeps a freeze frame as a `freeze` step at the same place along the clip (`t`), so the saved effect freezes the matching moment of the next clip.
- **Skill packs without code, exported from saved skills, reviewed before trust (#506).** A plugin that ships only skills or library packs may leave out `entrypoint` (host feature `skillsOnly`; nothing that runs is allowed then) and installs and loads like any plugin. `skills export --output DIR --as-plugin --id me.my-skills` packages saved skills as such a plugin (plain skill folders without `--as-plugin`), checked by reading it back. The install approval shows a **Skills for agents** part: each new, changed or removed skill with its line diff against the installed copy, and added lines flagged `command`, `url` or `override` ("ignore previous", …); `ui dialog` reports the counts.
- **Drag files out of plugin views (#408).** A plugin list row with `file`, or an `image` (its `file`, else its `path`), can be dragged onto the timeline (imported and placed like `media import --place`) or the Media panel (imported like `media import`), host feature `views.drag`. Only absolute paths to local video, audio and image files drag. The Media panel now also takes files dropped from Finder.
- **Plugin overlays on the timeline and viewer (#407).** A plugin marks frame ranges, markers and viewer regions as data (host feature `overlays`): `[{id, kind: range|marker|region, start, end, track, rect, label, color, style}]`, sent with the host call `plugins.set-overlays` or the session line `{"type":"overlays"}`. The timeline draws ranges and markers with the clips (only when they change; a redraw looks them up by frame), the viewer draws regions while the playhead is in their frames. `plugins overlays` lists them, `plugins set-overlays` sets or clears them, and the plugin's panel shows how many with **Clear**. At most 500 per plugin; not saved with the project. Benchmark: 2000 overlays, 1.2 µs per timeline lookup, 21 µs per playback frame for the viewer filter.
- **Plugins update their views outside a request (#409).** A session plugin may send `{"type":"viewUpdate","view","body","title"?,"state"?}` at any time (a background job, a timer; host feature `viewUpdate`). BashCut draws it only in a view on screen, at most every 60 ms like streamed renders, and drops updates for hidden or undeclared views, larger than 512 KiB, or beyond a burst of 20 refilled at 10 a second per plugin.
- **Inspector plugin views follow the selection without piling up requests (#405).** A new selection renders 120 ms after the selection stops changing, a render still running for an item the user left is cancelled (the plugin gets `cancel`) and waited for, so a plugin renders one item at a time; the view no longer rendered twice when it first appeared. An inspector view may have a `when` condition (`selection.kind == text`, host feature `inspector.when`) and is then not asked about items it does not match. Benchmark (`scripts/verify.sh perf`): 300 selection changes 5 ms apart start one render; the main-actor timer stays within about 1 ms (p99), 6 ms worst.
- **Voice providers declare `maxTakes` (#410).** A `voice.synthesize` provider may set `"maxTakes": 1` (1–8, API 8, host feature `voice.maxTakes`) so BashCut never asks it for more takes per line: a paid TTS line costs one take instead of three. `voice speak --takes` is capped to it (the answer has `requestedTakes` when fewer came back), the Voice panel generates that many and hides the take picker for one, and `plugins list` and `capabilities get voice.synthesize --voices` report it.
- **Plugins set their own options (#411).** A plugin's view or action may call `plugins.option` over the host channel (`{"plugin": "<its id>", "option", "value"}`, host feature `options.set`) for one of its own options, so a voice library's "Use" button sets the `voice` the Voice panel and later requests see. Never another plugin's options and never a `secret` option (a plugin with secrets may still set its other options); user-scope values are saved for this Mac, project-scope values are an undoable edit by author `plugin`.
- **Plugin author on the install sheet and the plugin panel.** The install approval sheet (and its `ui dialog` text) and a plugin's panel header show the manifest's `author` (*By <name>*, a link when it has a url), so the person who wrote a contributed plugin is seen before trusting it.
- **Colour and font pickers in plugin views.** Two new view components: `colorPicker` (a colour well; `value` `#RRGGBB`, or `#RRGGBBAA` with `alpha`; sends `change` with the hex string 250 ms after the colour stops moving) and `fontPicker` (a menu of the project's fonts and the installed ones, what `fonts list` lists; `value` a PostScript name, or a family name with `"by": "family"`; fonts without the content language's letters are marked). Host features `views.colorPicker` and `views.fontPicker`; a colour that is not hex is refused.
- **Claims ledger, creator profile, style profile link (P3-I5).** `knowledge set-claim KEY --text --source` records a number, price, superlative or name the video states with its source (URL, `MEDIA@SECONDS`, file or `user`; `knowledge claims` lists them); review lists those in titles and voiceover lines that no claim covers as `unsourced-claim` (info). Preferences under `creator.` (name, handle, channel, platforms, language, niche, audience, tone, cta, voiceSamples as media IDs, disclosure) are checked and shown as one `creator` object in the session summary; an agent's change to them for every project always waits for approval. `library add`/`update --profile` links a look, preset or brand kit to the reference profile it was made from (`style save` no longer exists; library items are the style kits).
- **Export ledger, post links, project history and outcomes (P3-I2, P3-I3).** Every finished export is kept (the last 100) with an ID, the revision and a fingerprint of the edit (looks, caption and title presets, music, transitions, clips, average and median cut, the hook's first cut, first text and words, the sections); its sections and caption words are kept for later. `export history [--full]` lists them, `export link --url --platform --posted-at [--export]` records where one was posted, and `project history [--limit N]` reads the last N projects' ledgers with how many used each look, preset, music file and transition and their hook and cut numbers. `outcomes import FILE [--export] [--platform] [--totals]` reads a retention curve (CSV with a time or video-position column, or JSON) and totals; `outcomes map` gives per section the retention at start and end, the raw change, the largest drop with the words within 4 s, the largest lift, the replay peak and the viewers at its start, plus the largest drops overall. Missing values stay null; no verdicts.
- **The user's verdicts on agents' changes (P3-I1).** BashCut records, per project (`.bashcut/knowledge/verdicts.jsonl`), what the user did with an agent's change: `keep` (dismissed the change notice, or the next edit left the agent's items alone), `undo` (undid the agent's step, also an older one), `edit` (the next edit changed the same items) and `reject` (Reject on an edit the scope guard held; Allow is a keep). Each row names the command that made the change (`timeline.apply`, `library.apply`, `library.place`, `plan.apply`…), its label, agent, revision and items. `knowledge verdicts [--verdict] [--subject] [--limit]` returns counts per command and verdict and the newest rows. Facts only, no reasons.
- **Evidence on knowledge (P3-I4).** Lessons count their sightings: `occurrences` (1 when recorded), `lastSeen` and `sources` (the projects they were seen in), shown in `knowledge lessons`, the session summary (`context get` › `knowledge`) and the Knowledge window; `knowledge update-lesson ID --seen` counts one more (no approval needed for a lesson for every project: it changes no rule). Preferences carry `confirmedBy` (`user` or `inferred`, the default for agents; `set-pref --confirmed-by`; approving a proposal makes it `user`). Facts carry `evidence` {`source`, `measure`, `n`, `status` measured|estimated|user} (`set-fact --source --measure --n --status`). Older files read unchanged.
- **Units said as the script says them; decoder scores per word.** `voice check`, `voice lines` and script-timed captions match a heard unit to the script's spoken form of it, in Vietnamese and English (`2 hectare` = hai héc ta, `3km` = ba cây số or ba ki lô mét, `3 km` = three kilometres), only when the script does not write the unit as heard; the extra words share the unit's time. Word timings (`words.json`) may carry `avgLogprob` and `compressionRatio` per word: kept in the source transcript, listed in `precision` and in `media transcript --as words` / `transcript words --heard` rows.
- **Multi-selection: shared Inspector edits, block moves on Main, copy and paste across projects (#357 follow-ups).** With several items selected the Inspector sets opacity, volume, fill, zoom, pan, tilt and rotation on every item they apply to, as one undo step (a slider drag coalesces; a value that differs shows Mixed). Dragging a selection on the magnetic main layer moves its clips there as one block, in order, before the clip under the drop (other selected layers stay). Copy and Cut also write the clips to the macOS pasteboard (private type `com.bashcut.timeline-items`, JSON with their media), so Paste works in another project or BashCut window: missing media are added with a project-relative path (a new ID when taken) and timing is converted to the project's frame rate. New command `timeline move-items --items a,b (--by N | --before ID|end)` for agents; multi-edit is `timeline apply` `patchItems` with `items`.
- **Blur fill for off-aspect photos and clips in one click (P3-J7 item backdrop).** A fitted clip or image can fill its bars with a blurred copy of its own frame scaled to fill, or a colour (item field `backdrop {kind blur|color, color, blur, dim}`), instead of a duplicate clip on another layer. It moves, fades, transitions and grades with the clip, in preview and export. `clip backdrop --kind blur|color|none [--items a,b] [--blur --dim --color]` (several items in one undo step) and Inspector › Video › Backdrop; `timeline get` scale facts name the backdrop.
- **Two fonts in one title (text phase 2).** `textStyle.lines` gives each line of a text item its own font (PostScript name, which picks family and weight), size (`scale` × the block's), text and outline colour, so a title can set a script word over a bold headline. A styled line is fitted to the frame on its own; items without it draw as before (no schema change). New command `text line-style --line N [--font --scale --fill --stroke | --clear]` (one undo step), Inspector › Text › Lines for titles of two or more lines, the review's text size check and missing-glyph check follow each line's size and font.
- **Crop and rounded corners can be keyframed.** `crop.left`, `crop.right`, `crop.top`, `crop.bottom` and `crop.radius` are keyframe properties on clips and images (`clip keyframe --property crop.radius`, `clip motion --keyframes`), so a picture can round into a card or open from a slit; the renderer cuts the picture anew at each frame (preview and export). Inspector › Video has a Crop section with the four sides, the corner radius and a crop keyframe button; animated values set keys at the playhead.
- **Subject-aware reframe: `clip reframe` (P3-J1).** A clip or image is cropped to its subject from the face (or person) boxes `media subjects` measured: it fills the frame and pans so the subject sits at an anchor. `--mode locked` holds one framing, `cut` jumps to a new one (hold keys) when the subject drifts, `follow` keys a smoothed path. Every limit is a parameter (`--anchor x,y`, `--zoom`, `--min-confidence`, `--gate`, `--min-subject-share`, `--drift`, `--min-hold`, `--smooth`). When too few pictures have a subject or the framing keeps too little of it in view, it fits the whole picture (`--fallback fit`) or changes nothing (`refuse`); never a blind centre crop. One undo step; returns the coverage, the framings and a source/edit preview grid. Boxes missing for the source the clip plays are measured first. `media subjects` now keeps its boxes per file (`.bashcut/cache/subjects/`).
- **Text over faces in `review layout`.** `faceOverlap` was always null: it is now the largest share of a face box a text item covers (with the clip, frame, confidence and the pictures sampled), from the boxes stored for the clips under it, placed with fit/fill, zoom, pan and tilt; overlay pictures get it at a frame. Still null when no boxes are stored. The new review limit `review.maxFaceOverlap` (0–1) reports `text-face` issues above it; unset, nothing is judged.
- **A long-running app no longer scans folders on the main thread to draw.** The agent dock checked for new knowledge every 3 s (the Knowledge window every 1.5 s) by listing the skill folders and reading the knowledge files' dates on the main thread; that now happens in the background and only a change reloads. A chat tab's `/` suggestions found and re-installed the agent kit (listing and hashing its files) on every keystroke; the kit's skill names are now read once when the tab refreshes. A plugin panel read its plugin's SKILL.md files on every redraw; they are read once per plugin refresh.
- **Less main-thread work when an export finishes (#350).** The report's speech coverage (every clip's transcript words) and the credits of `review.credits` projects were computed on the main thread when the export landed; the export now makes them on its own task and hands them over with the result.
- **A 29.97 fps clip next to a 30 fps clip keeps every picture.** Each project frame showed the source picture at the start of the frame; a 29.97 fps picture starts a hair after a 30 fps frame boundary, so such a clip showed every picture one frame late (its first picture twice, its last never), which looked like a dropped frame at a join with a 30 fps clip. The composition now samples each clip at the middle of the project frame (the rule the constant-rate export already used for held pictures); same-rate clips show the same pictures as before, and a clip at another rate shows the nearest picture instead of the earlier one.
- **Plugin review checks take large projects.** A `review.check` request carried the whole project inline, so a project over the 1 MiB request limit failed every check. A project whose JSON is over 512 KiB is now written once to a private file and sent as `projectFile` (its path) instead of `project`; the file is removed once every check has answered. Providers read `project` when present and `projectFile` otherwise.
- **Xcode Debug builds are development builds.** `BCDevelopmentBuild` was set only by `scripts/run.sh`, so a Debug build run from Xcode looked for updates by itself and offered to replace itself with the latest release. The Debug configuration now sets it (`BC_DEVELOPMENT_BUILD = YES` in `Configs/Debug.xcconfig`, `NO` in Base, read through Info.plist).
- **Review measurements survive a restart.** The picture measurement (`review measure`) and the loudness of the last normalized export were kept only for the app session, so after a restart review asked to measure again. They are now stored in `.bashcut/cache/review-measurements/`, keyed by the project's content (its JSON without the revision number) and its media files' size and date: reopening the project, or undoing back to measured content, finds them; any edit or a replaced media file does not. Opening another project no longer keeps the previous project's measurements (their revision numbers could match). Plugin `review.check` issues are still per session.
- **Render errors name the frame.** A frame the compositor cannot read failed an export with only `BashCutCompositor.MissingFrame code 2`. The error (export status, job `error`, the `export.failed` event) now names the project frame, the item, its track, its media file and the source frame, for example `Render failed at project frame 20: source frame missing (item a on track v1, media m media/a.mov source frame 26)`.
- **Run panel, result card and quick edits (#447, #448, #449).** A panel over the editor shows the agent's run from the run log: the stages (survey → export and any the plan adds), the current one with the agent's step text, progress and time left, and the elapsed time of the run and the stage, while the timeline keeps updating underneath. Agents report a stage with the call they already had, now taking `--progress` and `--eta`: `run append stage --stage cut --text "Cutting 12 shots" --eta 120` (status `started`, the default; `cut`, `color` and `audio` mean `rough-cut`, `colour` and `sound`); BashCut's own stage entries need no call. When the run exports, the panel becomes a result card: a still of the newest export, its duration, loudness and cuts, the review issues still open, every file the run exported, and Open, Reveal, Export another format…, Fix N remaining issues and Try another recipe (the last two send a request worded by BashCut to the open agent). An agent's export during a run shows the card instead of the export report sheet. `run status` returns the panel's data; `ui action run.fix-issues`, `run.another-recipe`, `run.dismiss` and `run.show` (File › Show Agent Run) are the card's buttons. **Quick Edit** next to Send to Agent (clip menus, Clip menu, Inspector) sends Faster, Remove this part, Lower the music, Add a caption, More punch-ins or the user's own words to the open agent, scoped to the selected clips (plus the music under them for Lower the music) and ending with a review of that range; `agent quick-edit <kind>` does the same. `review run --from --to` lists and counts only the issues touching those frames (a pass there is not the review stage).
- **Faster project open and socket JSON.** Project files, the undo journal, autosave records and every automation request and response are read with `JSONValue(parsing:)` (JSONSerialization) instead of `Decodable`, with the same values. Release build, synthetic 5,000-item project (752 KB): open 96 → 30 ms (reading the JSON 80 → 16 ms), 200-step journal 192 → 104 ms; 1,000 items: open 20 → 6 ms. A 965 KB response line: 506 → 64 ms in a debug build. `bashcut-core-bench` prints both paths.
- **Cover titles (#443).** `export cover FRAME --title TEXT [--preset P]` draws the title on each cover in a text preset or a library text-preset ID (bold-outline by default; a library preset brings its style and font), sized by each cover's short side and fitted to its width like timeline text; each cover reports `titleBox` {x, y, width, height} as fractions from the top-left to check against the platform's zones, and the file ends in `-title`. The Export sheet has a **Cover** row: an optional title, its preset and **Save Cover at Playhead** (each output's cover aspect, saved in render/).
- **Scope guard: ripple shifts, undo/redo and dry runs (#356 follow-up).** An agent's `timeline undo` and `timeline redo` were not checked against the attached clips, so an undo could revert the user's changes elsewhere; they are now checked as the change between the two states (clips that only moved on their layer pass) and fail with `-32004` naming what lies outside, since a step cannot be held for the user. Closing the gap a lifted scope clip left (`timeline close-gap`: the layer's tail shifted by one amount, with its section markers) counts as a ripple shift and is no longer held, while moving one clip is still checked. `timeline apply --dry-run` reports `outsideScope` when the apply would be held or refused.
- **Text presets carry their font.** A text preset whose `textStyle.font` is one of the project's own fonts (Add Font…, `fonts import`) is saved with the font file (`library add`, `library save-selection`, the panels' Save selection as…, and `library move` of an older preset to This Mac); placing or applying it, or naming it in `plan.cut`, in a project without that font copies the file into the project's `fonts/` folder and registers it, so a preset saved to This Mac draws the same in every project instead of falling back to Helvetica.
- **Knowledge › Skills preview: numbered lists, quotes and rules; skill names checked while typing (#126, #127, #128).** The SKILL.md preview shows `1.` items as numbered rows (indented lines join them, like bullets), `>` lines as one quote block and a body `---`, `***` or `___` as a divider. The new skill field disables Add and shows "Use lowercase words joined by hyphens" while the name is not valid.
- **Post text limits in the platform data; `script check` shows each beat's ON SCREEN note.** The built-in platform table (version 2026-10-13) adds `caption.maxChars` (TikTok 2200 UTF-16 units, Reels 2200), `hashtags.max` (Reels 5; TikTok none official, `info`), `description.maxChars` (YouTube and Shorts 5000) and `hashtags.ignoredAbove` (YouTube and Shorts 60: more and all are ignored), each with the platform's own page as its source; `title.maxChars` now cites YouTube's help page. `platforms get --facts` returns them. `script check` rows carry the beat's `onScreen` note (given, else the plan beat with that id), so a visual plan reads heard words and planned pictures in one call.
- **MCP server instructions.** BashCut's MCP server sends one instruction line at initialize: "For any edit request, read the `bc:edit-workflow` skill first."
- **Plugin views in the Inspector.** A plugin view may live in the Inspector (`"location": "inspector"`, host feature `location.inspector`): it shows under the controls of one selected item, on every tab, and renders from scratch whenever the selection or the selected item's media changes, with the selection and its media (`data` included) in its request's `context`. A view that answers an empty body takes no room, so a plugin shows itself only for items it made, such as a rendered graphic's inputs to edit and render again without an agent. No container (rail icon) is needed.
- **Craft checks: whole-picture hits, sound-effect runs, keyed text size, export without music, lessons as cases (#517).** `review sync --events impacts` lists every change to the whole picture lasting at most `impactFrames` (default 12): short transitions on Main, fast zoom/pan/tilt/rotation/opacity/exposure keys on Main clips and adjustment layers, short pictures over Main, each with its nearest beat (and the beat's strength when the music's grid has strengths) and the spacing in beats and seconds, plus count, per minute and smallest spacing (#518). `review sync --events sfx` adds `sfxRuns`: three or more placements of one sound file with starts at most `runGapSeconds` apart, with their gains, intervals and whether gain and spacing stay constant (#519). No limit is applied to either. `review.minTextSize` and plan check's `textShare` now count keyed `zoom` and `textStyle.size`: the smallest scale a title holds for half a second (a pop-in that settles does not count); the issue gives `keyedScale` and `styleShare` (#521). `export start --without music` (also sfx, voiceover, dialogue) writes the same cut with those audio layers muted, and the Export sheet has **Without music**; that file's loudness and QC stay out of review (#520). Lessons take an optional `check` question (`knowledge add-lesson --check`, `update-lesson --check ""` clears it) shown in every session's knowledge summary, and the evidence help asks for the user's words quoted (#524).
- **An explainer in a few calls: voiceover lines and graphics in `plan.cut`.** `plan.cut` takes `voiceover` lines (`{id, text, caption, section, pause, at, take, volumeDb}`), played one after another on the Voiceover layer from frame 0, so an edit can be lines without clips; each line's `section` makes the section markers. `graphics` (`{id, media, on | section | at, offset, seconds | until, track overlay|main, from, render}`) place rendered movies full canvas over an entry's or a section's span (Main when the graphics are the picture); `render` is a graphics plugin's inputs, kept and not read. Captions from speech also cover the lines (broken into cues of at most `captions.maxChars` characters), with each line's own text (or its `caption`, digits for a number spelled out for the voice) timed by its take's words; titles anchor to a line, SFX to a line or a graphic. `plan check` reports each line's take and similarity and each graphic's span, also before it has media (`graphic-no-media`), `graphic-short`, `no-take` and `picture-gap` (Main black in an edit without clips); `--words` adds the voiceover words heard during each graphic, in seconds from its start. New job `voice lines [lines.json] [--takes --min-similarity --retries --only --force]` voices every line of `plan.cut.voiceover` (or a file) in one job: takes are kept, transcribed and diffed against their text, a line with no take at the minimum is tried again, and a line that already has a passing take is skipped; numbers the script spells out match the digits a recognizer writes (`528` = năm trăm hai mươi tám, either common spelling), in every take check; `plan apply` plays each line's best kept take. `voice check --items a,b|all` checks several voiceover items in one job. Measured motivation: an explainer bench run took 142 turns and 33M input tokens, most of them voicing and checking lines one by one and placing graphics, captions and the voice with hand-written timeline operations.
- **Background removal: `image cutout`.** A new capability `vision.cutout`, served by the built-in Vision plugin (Apple Vision's foreground mask, now version 1.1.0), turns a picture's subject (a mascot, a product) into a PNG with a transparent background; `image cutout <file or sticker> [--crop]` returns the file, how many subjects were kept and the share of the picture they cover, ready for `library add --kind sticker`. A plugin with a better model can serve it with a higher priority.
- **A ripple on Main keeps other clips in sync with their sound.** A ripple delete, ripple trim or speed change moved the later clips on their own layer only, so a clip whose linked sound sat on a layer the edit did not ripple (the clip before it had no sound, or the sound was on another dialogue layer) was refused as "linked timing or media differs". The linked partner of every moved item now moves with it, once.
- **Update Now for Homebrew copies.** Software Update no longer asks the user to quit and paste `brew upgrade --cask bashcut` into Terminal: **Update Now** (and `app update`, approved by the user) lets Homebrew update its taps and download the release while BashCut runs, then saves the project, quits, upgrades the cask from a helper and opens the new version. A failure before quitting (offline, Homebrew not yet offering the release, a save that fails) keeps BashCut running and shows why, with the command to copy as before; a failed upgrade is reported on the next launch with its log (`~/Library/Logs/BashCut/update.log`). `app update-check` adds `canUpdateNow` and `installError`.
- **Brand kits (#453).** A new library kind `brand` holds what a channel keeps on every video: a palette (accent, background, text, secondary), a heading and a body font, a logo and mascot poses (sticker items), a default voice and a disclosure label. `library apply <brand>` (no item) sets the project's `brand` and, in one undo step, restyles every text item whose `brandRoles` tie `textStyle` paths (`fill`, `stroke`, `highlight`, `background.color`, `shadow.color`, `accentBars.color`, `font`) to the kit's roles; text presets with `brandRoles` take the project's kit when placed. Two kits give the same recipe two consistent looks without editing the timeline by hand. The new Brand panel shows the kit in use and the saved kits (click to apply, New Brand Kit…, Edit…), New Project and `project create --brand` start a project with one, and recipes, graphics and voice skills read `project get` › `brand`.
- **Imported movies keep their transparency.** `media import` marks a movie with an alpha channel (HEVC with alpha, ProRes 4444) as `alpha`, so a rendered graphic imported directly (a HyperFrames re-render) is shown over the picture below like a video sticker, not on black.
- **Three new transitions: swing, glitch, halftone.** `swing` turns the next card in about its left edge in perspective while the last one falls back (the explainer card swap), `glitch` tears red and blue apart with a jitter, `halftone` breaks the picture into print dots and resolves the next one out of them. They are rows of the same motion table, which gains the properties `swing` (degrees about the left edge), `rgbSplit` (share of the width) and `halftone` (dot spacing as a share of the width) for custom kinds; preview and export draw them the same way.
- **Ask agent: Explainer template (#512).** The Ask agent sheet offers an Explainer request (topic, platform, length, voiceover or music only, 4–6 parts with cards, numbers and a map, chart or checklist, facts from a source) for the vlog plugin's `explainer` recipe and HyperFrames' data widgets.
- **Fewer silent wrong results (#507, the rest).** `platforms get youtube-1080` (or `youtube-4k`) resolves to the `youtube` platform its export preset is made for (#507-21). A ripple delete or trim and `timeline close-gap` on the main layer move the section markers with the clips; markers inside the removed part go to the cut (#507-11). `upsertTransition` takes an optional `id` (without one it updates the transition at that cut or names a new one `transition-<from>-<to>`) and `between: [from, to]` (#507-18); `addTrack` without `atIndex` puts the layer in front of its kind (#507-19c). `audio mix-measure` no longer calls every short effect `masked`: it reports each effect against the voice at the same moment (`voiceDuring`, `voicePeakDb`, `overVoiceDb`, `peakOverVoiceDb`) and names effects measured together (`sharedWith`), with no verdict (#507-16). `review layout --contrast` rates outlined text by its stronger part (`basis: outline`, `meanRatio` kept) instead of the mean of fill and outline (#507-17). `review accept` keeps an error when no fix exists (counted as `acceptedErrors`) (#507-31), and a `review.severities` entry may be `{severity, reason}`, shown as `severityReason` (#507-37). Speech coverage (review `coverage`, export status `speechCoverage`) counts clips with a stored transcript from their first heard word to the last, so hand-placed speech is no longer 0 (#507-36). `export start` with a name already on disk or queued uses the next free one and says `renamedFrom`; `--overwrite` replaces the old files (moved to the Trash) (#507-23). `media import --origin web` marks a file downloaded from someone else's page (#507-24). `ui frame --out FILE` also writes the PNG there (#507-25b). `project create` adopts an existing folder without a project, such as one the footage was copied into (#507-38). A GitHub `/tree/` link whose branch has a `/` installs: each split of ref and folder is tried (#507-29). `export status` reports `clips` and `cuts` (the joins between them) and `review measure` names its count `hardCuts` (#508-34).
- **Exports are constant frame rate (#507-1).** A clip at another rate (23.976, 24, 25 fps or a phone's variable rate) with no animation came out of the composition at its own rate, so the file was variable frame rate with frames missing (a 30 fps product ad: 476 of 495 frames; the #508 recheck project: 469 of 508, 27.7 fps). Every export now writes one picture on each frame of the project's rate, the latest due by the middle of that frame; held pictures (stills, freeze frames, the last frame) repeat on every frame. `review run` flags an export whose average rate is under 98% of the project's (`delivered-vfr-<preset>`, an error).
- **Edits do what they say in one call (#507, #508).** Wire `setProperties` and `setProjectProperties` patches (and `project set-data --merge`) merge objects key by key like `patchItems`, so `{"textStyle":{"strokeWidth":4}}` keeps the font and `{"audio":{"mixGainDb":0}}` keeps the loudness target. `timeline apply` returns `unread-field` warnings for item fields nothing reads, with the field meant (`volume` → `volumeDb`). Title presets placed without `--track`, plan titles and effect text go on a Titles text layer (role `titles`, added when missing), never among the captions, and the `.srt` leaves that layer out. A normalized export keeps its loudness gain in the file: it no longer writes `mixGainDb` into the project (which stacked under the next export and bumped the revision, so the agent's next edit failed as stale). A second job for a busy capability (`voice speak`, `library search`…) is queued behind the first instead of failing `busy_running`. `selects place` widens an edge that falls inside a transcribed word to the word's edge and lists it in `widened`. `color measure --graded` / `--compare source` measure their pixels off the main actor (17 s with the app frozen → about 5 s, app responsive) and the CLI waits up to 60 s for them. `bashcut <group> --help`, `bashcut help <group>` and an unknown command print that group's commands (an unknown group prints the group names), not all ~200 commands.
- **Normalized exports reach their loudness target.** A normalized export applied one gain capped by the true-peak ceiling, so mixes with a few loud peaks stopped short: seven benchmark drafts landed at -15.1 to -16.3 LUFS against -14. The export now applies the whole gain to the target and a look-ahead limiter (1.5 ms, linked stereo, smooth release) holds sample peaks 1 dB under the platform's true-peak ceiling, leaving room for inter-sample peaks and the AAC encoder; the verify pass still measures the file.
- **One call readies the footage; commands that wait for their own work; plan clips keep their last word whole.** `project create --footage DIR --import` also imports the folder's files and starts `media transcribe` and `media analyze`, returning the import and the job IDs (`jobs {transcribe, analyze}`, or `{error}` for one that could not start), so a survey can begin after one call. `review run --measure` measures a revision not measured yet (waiting up to 100 s, `measured {job, timedOut}`) before reviewing it; `export start --wait` returns the finished job when the export starts at once, and `--save` saves the project once it lands. `media transcript --ranges A:B,C:D` reads several windows in one call. `jobs wait --timeout` over 110 s waits 110 s (`waitedAtMost`) instead of refusing the call, and `bashcut <group> <command> --help` prints that command's reference. A plan clip's out edge now rounds up to a whole frame (the in edge down), so a clip given at a word's end no longer stops a frame inside it and fails review as a cut word; review counts up to one frame inside a word as timing noise, and a rough edge within a frame of a word's far edge snaps out of that word instead of taking it whole. `plan.cut.sfx` lists sound effects (`{media, on: clip or title ID | section | at, offset, seconds, volumeDb}`) built on the SFX layer by the same `plan apply`, so a whoosh on a cut or a pop on a title costs no extra edit. A `plan.cut` clip picked by `quote` or `words` may also give `from` or `to` to move that edge (snapped out of words; the quote's own range stays in the check as `quoted`), so `plan check --patch '{"clips": {"c9": {"to": 1390.3}}}'` trims a quoted clip instead of failing with "give one of quote, words or from/to"; a patch that gives a clip a new quote drops its old edges. A `plan.cut` clip or cover takes `zoom`, `pan` and `tilt` for its picture (a punch-in that breaks a jump cut between clips of one camera, kept in the list instead of edited by hand), and a field nothing reads (a typo, a field from another command) is now an `unknown-field` warning in `plan check` instead of being ignored while the check said ok. `plan apply` returns a brief result (about 2 KB instead of 18 KB: clips as a count, the sheet as image paths; `--full` for every clip's facts, the changes, the built items and the sheet's cells), so agents stop saving it to a file and parsing it over several turns. `project create --footage` also takes one file (its folder is linked; `--import` takes only that file). A `plan.cut` clip given in seconds that holds transcribed words is tagged speech like a quoted one, so speech coverage no longer needs a role patch per clip. `skills get` takes a plugin skill by the name agents list it under (`vlog-product-ad`) as well as its ID. The unsaved-changes error names the project and the CLI options. BashCut's own run-log stages (intake, survey, story, rough cut, captions) are written once instead of on every `plan apply`; review and export still once per revision. Measured motivation: run 10 of the ad benchmark spent 7 of 33 turns before the survey, 4 on `plan check` loops over a one-frame cut, and 3 on measure/wait/review.
- **A plan clip given in seconds never cuts a word.** `plan.cut` clips with `from`/`to` that fall inside a spoken word now move out to that word's edges when built (the times given stay in the check as `requested`); before, `plan check` reported the snapped edges as clean while `plan apply` built the times as given, and review then failed the cut as inside a word.
- **Captions say what the cut plays; misheard names fixed in the plan; clearer edit errors.** A caption line a clip plays only part of now shows only the words heard inside the clip (it showed the whole transcript line, words cut away included), for `plan.cut` captions and `captions generate` alike. `plan.cut.captions.replace` (`{"misheard words": "right words"}`) fixes names and places the transcript got wrong in every caption it builds. A skill read before any project is open (an agent reading its recipe before `project create`) is kept and written to the next project's run log, so the recipe guard no longer refuses the rough cut for a recipe that was read; reads of the last half hour made while another project was open are carried into a project created or opened next. An unknown edit operation names the valid ones, `patchItems` takes item IDs inside `select` too, and `review-profile-unset` says what each missing limit can hold (`facts.accepts`).
- **Fewer turns between survey, review and draft.** `--base-rev last` (MCP: `"baseRev": "last"`) is the revision as of the caller's last command, so an agent need not read the project to learn the revision its own edit made; an edit by anyone else since still makes it stale, and every edit's result carries `rev`. `media describe` repairs a describer's obvious slips (numbers as text, subjects as one comma-separated string, labels and notes over their length, a best moment or looked frames outside the shot, a shot running into the next) and lists them in `adjusted`; what cannot be repaired is reported for every shot at once, and a list sent wrapped as `{shots: […]}` is taken from the CLI too. Review asks only for the limits a check of the timeline reads (no music, no music-gap limit; no captions, no caption lines), and loudness, measured by the normalized draft, moves to `checks.atExport` and no longer keeps a review `incomplete`. `plan.cut.review` carries the review limits with the plan (written into the project on `plan apply`, checked by `plan check`), and `review-profile-unset` lists every limit the built edit still needs in `facts.unsetLimits`. BashCut also records the intake stage when the brief is set, survey when every media is described and story on `plan apply`; the export entry says whether loudness was measured.
- **Faster footage analysis, fewer agent turns per edit.** `media analyze` decodes each video once, in order, in its native YUV format (luma thumbnails for every frame, the sampled frames scaled in hardware and measured as before), and reads the sound alongside: a 23-minute 1080p vlog took 58 s in a debug build instead of 364 s, with the same cuts (158 of 159 on the same frame) and sample luma within 0.003. The job reports progress, and asked while a media is still being converted (AV1, VP9) it waits for the conversion and measures the converted copy instead of refusing, so an agent can start transcription and analysis right after import and work from the words meanwhile. `plan check` and `plan apply` take `--patch`: changes merged over the edit list by entry ID (`{clips: {c2: {cover: […]}, c5: null}, titles: {t1: {style: {…}}}}`; null removes, an unknown ID adds), and `plan apply --patch` saves the result as `plan.cut`. `review verify all` (or `ID1,ID2,…`) proves a whole round in one call: fixed and persisting counts, a row per issue with a window only for what persists, and new issues. `timeline sheet --entries c2,t1` lays out only the items built for those plan.cut entries. BashCut writes run-log stages it can prove itself (`auto: true`): rough-cut and captions on `plan apply`, review on a `review run` that passes, export when an export lands. Settings › Agents › "Only BashCut's MCP server in Claude tabs" (on by default) starts Claude with `--strict-mcp-config`, so the user's other MCP servers do not ride along on every turn. Measured motivation: of a 15.7-minute ad run, 10 minutes were the conversion and the analysis, waited out over six turns.
- **No more blind surveys of converting video; plate text measured right; titles on a section.** While an AV1 or VP9 media is still being converted, `media frames`, `media frame`, `media strip` and `media analyze` refuse with a busy error naming the conversion job (`jobs wait JOB --done`), instead of "not decoded" cells or a one-shot analysis of the undecodable file. Text on its own box (`textStyle.background`, opacity 0.5 or more) is measured against the box, not the picture behind it: white letters on a black plate measured 1.1–1.4:1 before. A plan.cut title can anchor to a `section` (it starts with the section's first clip, plus `offset`), and without `seconds` lasts to the end of its clip or section. The `cut-in-word` fix names both word edges in source seconds (and facts `before`/`after`), so a plan.cut clip's `from`/`to` can move there directly.
- **Fewer tokens per edit: catch text problems before the critic, one read of the footage, compact output.** `plan check` gives each title's `textShare` (its smallest line as a share of the short side, counting a template's shrunk emphasis line), warns `stroke-units` when `strokeWidth` is under 1 (it is in points, unlike `size`, so 0.12 drew no outline) and `review-profile-unset` when the project has no review limits (review would stay incomplete and check no text size or contrast). `review.minTextSize` now judges the smallest line, so a Headline + Subline subline at 0.42× is caught. `review measure` measures the contrast of every title and up to eight captions against the picture behind them; new review limit `minTextContrast` (WCAG ratio 1–21) warns per item, unset reports the lowest as info. `plan apply` returns the review's errors and warnings of the built edit, and `--sheet` adds the storyboard (`timeline sheet --cuts --text`) of the new revision in the same call. New read command `media digest [--media] [--from --to] [--as json]`: each media's described shots, transcript phrases (a phrase repeated within 120 s marked `[again T]`, a possible retake) and undescribed cuts in time order, one line each, also written to `analysis/digest.json`. `skills get --section WORDS` returns only the matching `##` sections (and lists `sections`), still counting as reading the skill. `export start` returns the `job` when it starts at once, for `jobs wait --done`. The CLI prints compact JSON when its output is not a terminal. Measured motivation: an ad run spent 34% of 7.1M tokens on a critic round that found an invisible outline (`strokeWidth: 0.12`) and a 2% subline.
- **Plan apply also makes captions, titles by preset name and the mix; waits up to 110 s.** `plan.cut` takes `captions: {from: "speech", wordStyle, preset, style}` (captions from the clips' stored transcripts, cut with the clips; tagged so the next apply replaces them), a clip `role` (speech by default for a quote or words: speech coverage counts without tagging by hand; cover pictures are B-roll) and `music.duckDb` (the music layer's level under speech). A title's or the captions' `preset` is a renderer preset or a library text-preset ID (`stacked-keyword`, a plugin's preset), and `style` takes text style fields directly (`font`, `size`, `stroke`…; the old nested `textStyle` still works). `plan check` errors on an unknown preset, a font not on this Mac, or one lacking letters of the content language. `jobs wait --done` returns only when a job ends; `jobs wait` and `checkpoint status --wait` go up to 110 s (was 30).
- **Vietnamese hook titles draw their tone marks right.** Fonts named `System-` + an optional Condensed, Compressed or Expanded + Regular…Black draw with the Mac's own San Francisco (listed first in `fonts list`, source `system`). The hook title preset and the Stacked Keyword and Boxed Keyword templates use `System-CondensedBlack` instead of Helvetica Neue Condensed Black, which has the Vietnamese letters but misplaces stacked marks (Ắ, Ở). Items that name Helvetica Neue themselves keep it.
- **The edit as one list: `plan check` and `plan apply`; fewer calls per edit.** `plan.cut` (project data, or a file passed to the commands) lists the clips on Main in order — each by `quote`, `words FIRST-LAST` or `from/to` seconds, with `section`, `speed`, `volumeDb` and `cover` (pictures shown over the clip's sound, muted, the last filling the rest) — plus `titles` anchored to a clip (`offset`, `seconds`, `preset`, `style`) and one `music` bed. New read command `plan check` resolves every quote in the stored transcript, builds the edit on a scratch copy and returns each clip's source range, edges (inside a word or sentence), where it lands, its described shot and orientation, each title's chars per second, problems (`quote-not-found`, `quote-partial`, `quote-ambiguous`, `unknown-media`, `source-reused`, `same-framing`, `orientation-mix`, `cut-inside-word`) and the review of the edit as it would be; `ok` is false while an error stands. New edit command `plan apply [cut.json] --base-rev N` builds it as one undoable edit (with `cut`, also saved as `plan.cut`; `--dry-run` returns the check): clips with linked sound, section markers, titles, music, each item tagged `planCut`; applying again replaces only what an apply built, and Main must hold nothing else. Batching: `media import FOLDER` adds every video, audio and image file in the folder as one edit; `jobs wait ID1,ID2` waits for several jobs; `checkpoint status --wait N` returns as soon as the user answers instead of being polled. The agent instructions say to batch and to build cuts from `plan.cut`. Measured motivation: one ad made through single commands took 778 calls (159 `context get`, 119 `media import`, 110 `jobs wait`, 36 `ui frame`).
- **`timeline sheet` no longer crashes on AV1 or VP9 video.** Sheets (and `review window`) checked nothing before asking AVFoundation for frames of video this Mac cannot decode, whose asset reader raised an Objective-C exception and quit the app; they now fail with `unsupported_media` like `ui frame`.
- **A transcript made before a conversion finished is found.** Media converted to H.264 (AV1, VP9) point at the converted file, so a transcript made from the original while the conversion ran was keyed by the original and looked missing (`media resolve-range`: "no transcript yet"). Stored transcripts are now also looked up by the media's `originalPath`.

- **Release archive builds again.** The two core plugins' executables had the same product name (`provider`), so an Xcode archive failed once the vision plugin was added; they are now `bin/bashcut-audio-analysis` and `bin/bashcut-vision` (each plugin.json's entrypoint).
- **Recipe-driven workflow: checklist, audits and two guards (spec 13, phases 2–3).** `skills get` records each plugin and kit skill read in the run log (`{kind: skill, name, origin, author, verified: true}`; kit skills as `bc:<name>`; a failed write never fails the read). `run append` takes `stage --status done|skipped --evidence "a;b" --reason` (done without evidence is stored `unverified: true`, skipped needs a reason), `skill --name N [--origin] [--verified-by hook]` (agent-written entries are `verified: false`; the kit's skill hook passes `--verified-by hook`) and `audit --point strategy|draft|process --verdict pass|changes|fail --findings N --by critic|self` (bound to a fingerprint of the timeline). New read command `run checklist`: the stages of the kit's table (or the plan's `stages.<id>.skill`), whether each skill was read, status, evidence, required and `n/a` from the plan, the three audits and `open`; `context get` › `workflow` adds `checklist` (compact) and `next {stage, skill, skillRead}`, and its `plan` summary adds `recipe`, `promise`, `checks` (count), `requiredStages` and `naStages`. `review packet --point strategy|draft|process` (default draft, which gains `checks.json` with the kit's generic checks and `plan.checks`). `review run --summary` gives `summary.status` pass, fail or incomplete (no errors but a review limit unset or a check not run); `passed` is now true only on pass, and the CLI exits 0, 1 or 2. Two guards for agents only (the user is never blocked): `export start` with any preset but quick-draft needs a passing draft audit of the current timeline or the user's G5 approval at this revision (`audit_missing`, remediation `review packet --point draft`); `checkpoint request G2`, and `run append stage --stage rough-cut` while G2 is skip, need the plan's recipe skill read (`recipe_unread`) and a strategy audit (`audit_missing`). The agent instructions gain the tool rules from the kit's edit-workflow skill: held and out-of-scope edits, error categories and retries, capability reasons, `agentPermissions`, library first.
- **Recipes in `/` before a project exists.** Plugin skills are also linked into the user's agent folders where the kit is set up: each Claude Code configuration folder with the kit's marketplace (`~/.claude`, `$CLAUDE_CONFIG_DIR`, other `~/.claude-*`) and Codex's `~/.agents/skills` once the kit's `bc-*` skills are there, with a ledger in Application Support so only BashCut's links are ever removed. A request can then reach a recipe before any project is created. With a user folder in place the open project gets no copy, so `/` lists each skill once. Agents see each plugin skill as `<plugin>-<skill>` (`/vlog-product-ad`, `/vlog-plan`): one wrapper per skill in Application Support/BashCut/AgentSkills carries the plugin's SKILL.md with that name and links to its other files, and every agent folder links to the wrapper. `run append skill` records a plugin skill loaded by that name under its ID (`bashcut.vlog:product-ad`), and ignores other skills the kit hook reports.
- **Deleting a clip's sound keeps its picture.** Deleting the audio half of a linked pair unlinks it and deletes only the sound; it used to delete the picture too. Deleting the picture still takes its sound, and selecting both deletes both.

- **Text templates by look; a new hook title.** The Text panel starts with four templates named by how they look, not what they are for, so one look serves as a hook, a call to action or a label and the agent picks it for the video: **Stacked Keyword** (heavy condensed lines, the keyword line large and yellow), **Headline + Subline** (wide caps over a small sentence), **Boxed Keyword** (one huge word or number on a light plate) and **Two-Tone Pop** (lines alternating white and yellow with a hard offset shadow). They use fonts that ship with macOS and cover Vietnamese. `hook-title` gets the stacked look: Helvetica Neue Condensed Black, no outline, a soft shadow and no red underline, with its last of two lines or middle line larger and yellow. New `textStyle` fields: `emphasis {line, fill, scale, plate}` (or `false`) and `lineFills`. A text block taller than the frame (a large emphasis line on a landscape frame) is moved back inside it. Built-in sample texts are English.

- **Agents run without stopping by default; they source media themselves.** Every workflow gate (G1–G5 and a skill's own gates) now defaults to Skip instead of Ask me; a user who wants a stop sets it in Settings › Agents › Workflow gates, and agents still may only tighten a gate. The agent instructions drop "ask before downloading media": timeline edits need no confirm, and agents download the music, SFX, images, footage and fonts an edit needs whatever the licence, recording license, source and author so the user can handle rights afterwards. Agents install the command-line tools they need and work to the end without waiting; installing and trusting BashCut plugins stays with the user, and agents never clone a voice that is not the user's.
- **No default content language; fonts and voices follow the project's language.** `project create --language` has no default (it was `vi`): agents pass the language from the user's prompt or ask. `fonts list` drops `--vietnamese` (breaking) and each font's `vietnamese` field; it takes `--language TAG` (default: the content language) and `--covers`, and gives `covers` per font, checked against macOS's letters for that language (accents and tone marks included), so any language works. Inspector › Text › Font marks fonts that lack letters of the content language instead of Vietnamese ones. `capabilities get --voices` gives `speaksContentLanguage` per voice when the project has a language.
- **No more empty `khao-sat/` folder in new projects.** New projects no longer get a Vietnamese-named `khao-sat/` folder; nothing read or wrote it. Existing projects keep theirs and can delete it.
- **Plugin bundles, one approval; installs wait their turn.** The plugin registry can list bundles (`bundles` in `registry.json`; the first is `starter`, Recommended). Plugins › Browse shows a Recommended card for a bundle with plugins this Mac does not have yet, and the empty Installed tab offers it too. Install… downloads and verifies those plugins, then shows one approval with a checkbox per plugin (checked by the bundle's defaults), what each adds and sets up, the total size and the plugins left out with why. Approving installs the checked ones one after another as one job (`Recommended: 2 of 5`), trusting each one's exact files as a single install does; one that fails is reported and the rest go on. When an install ends, BashCut checks each new plugin's health again; one with a dependency still missing (for example a model or Python environment its setup did not finish) gets its Install Dependencies approval queued, so the user only approves it. Fix: a dependency probe in a health check had 15 seconds, which the first check after a setup can exceed (a fresh Python environment imports and macOS scans its new libraries), so Whisper Captions showed Needs setup right after installing; probes now have 60 seconds, and a dependency that was not checked no longer counts as needing setup. New command `plugins bundles` lists the bundles and what installing each plugin would do; `plugins install --bundle ID [--only a,b]` shows the bundle's approval (agents only show it; the user approves). Bug fix: asking to install a plugin while another install was waiting for approval or running replaced that approval or opened a second one over the running install. Registry installs and bundles asked for meanwhile now wait in a queue (`approval: queued` with the position; the Plugins sheet shows Next) and open when the current one ends; adding a plugin from this Mac or a link, and setup, are refused until it ends. The agent instructions point users who lack plugins to `/bc:setup`.
- **Claude's questions in a card over the terminal; Claude tabs skip permission prompts.** BashCut's Claude tabs start with `--dangerously-skip-permissions` and a PreToolUse hook for AskUserQuestion (`bashcut agent hook`): the questions show in a card over the terminal (options with descriptions and previews, multiple choice, Other with your own text, notes) and the answers go back to Claude as the tool's answers, so its terminal menu is skipped. Answer in Terminal, closing the tab, Claude exiting or 15 minutes without an answer hand the question back to the terminal menu, as does any failure reaching the app. New command `agent ask` (questions JSON, `--timeout`) asks from a terminal tab; it is left out of the agent instructions. Without a project or chosen workspace, agent tabs start in the projects folder (~/Movies/BashCut) instead of the home folder.
- **Plugins sheet matches Settings.** The Plugins sheet takes the same size as Settings (the main window less a margin) instead of a fixed 760×620.
- **Media panel fits its column (#484).** The Media source picker is a menu instead of five segments, which did not fit the 225pt panel and pushed it over the left rail and the viewer, clipping rail labels and the panel's controls. Each editor pane (rail, library, viewer, Inspector) is clipped to its own frame, and the empty Media message wraps.
- **Footage in the library (P2-H5).** New library kind `clip`: a movie or image file (generated or downloaded B-roll) with free `params` (`library add` measures `seconds`, `width`, `height`, `hasAudio`; a provider's model or prompt keys round-trip). `library generate --kind clip` asks a video or image provider for candidates; `library place` copies the file into the project's `clips/` folder once per content, imports it with the item's licence and provenance and places it like `media place` (main layer or `--track`, spilling to a free layer, linked sound, `--duration` trims) as one undo step. The Media panel gains a **Clips** tab; `library list --panel media` lists them. No new generate command and no model enums in core. The plugins guide describes pixel effects and AI transitions as a render-then-place action (P2-H11: no per-frame plugin renderer).
- **What is in the picture, and the agent's notes on media (P2-H6, P2-H7, P2-H10).** New core plugin `bashcut.vision` (Apple Vision, out of process like Audio Analysis) provides `vision.faces` and `vision.text`. `media subjects <media> [--step --from --to]` returns, for one upright picture every `step` source seconds, face and whole-body person boxes `[x, y, width, height]` (shares from the top left) with confidence; `media ocr` returns lines of on-screen text with box and confidence (`--languages`). Both are provider jobs with the source `frame` per picture and where the media plays on the timeline; no labels and no review checks (flexibility audit). New op `setMediaData {media, patch}` keeps the agent's own fields on a media under `data` (take numbers, verdicts, reasons; null removes a key); core never reads them and there are no take commands. Test fix: `ExportSampleTransferTests` no longer fails under a fully parallel `swift test`, where its 50 ms wait could outlast the 5 s interrupt grace.
- **Deferred flexibility audit items: transitions and easing as data, fewer and merged commands (flexibility audit, rest).** Transitions are data: a transition's optional `motion {outgoing, incoming}` runs `zoom`, `panX`, `panY`, `rotation`, `opacity`, `exposure`, `scaleX` and `reveal` through 2–16 values over the tween; the seven built-in kinds are rows of `TransitionMotion.builtIns` and any kind name works with a motion (`upsertTransition`, transition presets' `params.motion`). One ease type: keyframe `ease` and transition `easing` both take the named curves or `cubic-bezier(x1,y1,x2,y2)`. Keyframes animate `color.exposure|contrast|saturation|lutStrength` on clips and adjustment layers and `textStyle.size|positionX|positionY|strokeWidth|lineHeight|tracking` on text; `textStyle.accentBars [{side, color, opacity, thickness, gap, length, radius}]` draws bars beside the text block or its plate. Commands: `review cuts` and `review hook` are removed (each `review shots` cut carries its kind, `framingBefore/After` and `sameFraming`, `transitionIn.easing`; `review shots` and `review layout` take `--from/--to`; `review layout --ink` measures a composed frame's luma and ink share); `review shots` drops runs, `lowVarianceRuns`, `--run-length` and `--max-cv`; `review sync` gives count, mean and median offsets (`--bins` for p10/p90 and per-offset counts); the review packet writes `shots.json` (no `cuts.json`, `hook.json`) and `coverage.json {clips, script}`. `platforms list` → `platforms get [id] [--facts]`; `project brief`/`set-brief` and `plan get`/`set` → `project data KEY` / `project set-data KEY value.json [--merge]` (brief, plan or any key of the agent's); `ui open|panel|source|notify` → `ui action open|panel|source|notify TARGET` (chat agents may run panel and source, plugins also notify); `plugins health` → `plugins list --health [--plugin]`, `plugins views` → `plugins list --views`; `voice voices` → `capabilities get --voices`; `clip speed` and `clip speed-curve` are Inspector-only (agents use the `setSpeed`/`setSpeedCurve` ops). Workflow gates take any name besides G1–G5 (asks by default; Settings lists it once used). `review coverage` returns which described shot each clip plays (the agent joins it with its plan); `script check` takes `--beats` or `--text`. `voice speak` only generates and measures takes and keeps every file with its provenance unless `--choose` or `--replace` (no `--target-rate`, `--keep-takes` or provider-score pick); new `voice place TAKE [--at-frame | --replace]` puts the take the agent picked on the timeline.
- **Less noise, shorter prompt (flexibility audit, phase 3).** Review issues carry a stable `kind` and `facts` (the raw numbers: seconds, limits, measurements, a text box and the platform zone) beside the short title and detail. Editorial checks run only against the project's review limits: without them there are no shortest/longest-shot, longest-silence, longest-music-gap, longest-still, "Loudness measured" or speech-coverage notes (the numbers stay in `review shots`, `audio measure` and the other measurement commands). The repeated-framing note is gone (`jumpCutChange` now also covers cuts between the same source and framing), as are the recognition-loop heuristic and the computed safe-zone `moveText` fix; most hint-only fixes are dropped. `review run`'s description is a short summary; the review packet README lists its files only. `audio energy` returns the curve (with where the file plays on the timeline) and no lift/drop/breath candidates (`--count` and `--window` removed); `narration windows` returns `covered {music, footage}` shares instead of an `owner` label. The agent instructions are about 8k tokens instead of ~22k: each command shows its usage with the options in one bracket and the first sentence of its description, and commands for the user, panels and plugin views (chat, plugin install and views, storage, agent setup, `ui open/panel/source/notify`, knowledge approval, skill switches) are left out but still work; `bashcut help GROUP COMMAND` prints a command's full description and parameters without the app. The provider-backed commands' capabilities are declared once in the catalog (`capabilities get` and capability errors read it), and every provider job takes `--request-id` and `--dry-run`. `run append` takes any kind (not `gate`) and a `--data` object.
- **One look system, motion and text presets as data (flexibility audit, phase 2 rest).** Looks are only library `look` items: the project `looks`/`styleKits` catalogs and the commands `looks save`, `looks delete`, `style save`, `style delete` and `style apply` are removed (breaking); `adjustment add --look` takes a library look (built-in or `scope:id`, without a LUT file), the Filters panel shows library looks only, and opening an older project copies its own looks into the project library once (the old fields stay as unknown fields). Motion presets are `MotionTemplate` data — keys at `t` 0–1 of the item or `s` seconds (negative from the end), values a number or a share of the frame width/height. Library text presets take any preset name, any `textStyle` field, `wordStyle` and an `animation` that is a preset ID or keys; saving a selection keeps hand-made keyframes as such a template. The effect recipe `text` step accepts `textStyle`, `wordStyle` and `keyframes`. A loudness measurement without project outputs uses Quick Draft (the project's own target) instead of a guessed YouTube/TikTok preset. The Inspector's Word by word picker shows Custom for per-state word styles, and Use on all captions copies them.
- **Restyle (flexibility audit, phase 2).** New wire op `patchItems` restyles many items at once: `items [IDs]` or `select {track, trackRole, trackKind, textPreset, media}`, and a patch whose objects (`textStyle`, `transform`, `color`, …) merge key by key (`null` deletes a key); it expands into ordinary `setProperties` ops, so undo, dry run, scope and fingerprints are unchanged. `textPreset` is open (any name; unknown ones use bold-outline's defaults). `textStyle` gains `align`, `positionX`, `lineHeight`, `tracking`, `uppercase`, `background {color, opacity, padding, radius}` (a plate) and `shadow {color, opacity, blur, dx, dy}`, drawn and laid out alike. `wordStyle` also takes `{spoken, upcoming, past}` looks of `{fill, opacity}`; the three names are presets of it.
- **Open agent notes (flexibility audit, phase 1).** Brief and plan are free JSON objects: an unknown field no longer makes a project fail to open, edit or save (bug), they are never validated on load, and review reads `lengthSeconds {min,max}`, `outputs` and section lengths only when present (directly or under `value`). Select status is a free string; `selects mark` and `selects remove` are folded into `selects set` (`reason` with a status or mustKeep change is kept as `statusReason`; `{id, remove: true}` removes). `media describe` takes open labels for size/angle/move/direction (the lists are suggestions), `tags`, and keeps any other field. Licences are free text or an object with an open `id` and the facts the item itself records (`redistribute`, `commercial`, …): the text parser and derived facts are gone, `library export-pack` refuses only items that say `redistribute: false`. `project credits` returns raw facts per used media (licence, provenance, frames on top) and the AI picture share; credit wording, disclosure rules and Content ID notes are the skill's, and review's rights notes shrink to `ai-media`. Error data keeps `category`, `retryable` and `remediation.command`; the hint prose (including an ffmpeg command, contradicting "never render with ffmpeg") is gone and the categories are explained in the agent instructions. `contentLanguage` is no longer silently `vi`: new projects leave it unset unless given (providers detect it) and `context get` reports it.
- **`project credits`, on request (P2-H9).** Credit lines from media licences and provenance (required ones first, with a description-ready `text`), AI use with the share of AI picture and each output platform's AI-label rule, Content ID notes for stock or downloaded music, and non-commercial / all-rights-reserved / unknown flags. Off by default: with `review.credits: true` the review adds `ai-disclosure`, `credits-required` and `rights-unclear` info issues and export job results carry `credits`. Nothing is written onto the video.
- **Licences and provenance on media and library items (P2-H8).** `license` is structured (`{id, version, text, url, attribution}`: cc0, public-domain, cc-by[-sa|-nd|-nc…], royalty-free, own, all-rights-reserved, custom, unknown), mapped from the old free text, with derived facts (commercial, redistribute, attributionRequired, shareAlike). `provenance` records origin (stock, ai, own, built-in), sourceUrl, author, provider, model, prompt, seed, requestId, charged and parentMedia. `media import --origin --license --source --author` and `library add --origin --author` record them (new op `setMediaRights` for media already in the project); `library place` copies an item's onto its media; voice takes and saved plugin candidates record theirs. `timeline get` lists media with licence facts; `library export-pack` refuses items whose licence forbids redistribution and lists `unknownLicenses`.
- **Provenance hashes and staleness (P2-G6).** Captions transcribed from media and the beat grid keep `generatedBy.sourceKey` (the file's content key then); voice takes keep `voice.textHash` (and on their media `generatedBy.textHash`). `review run` adds info issues `voice-text-changed-<item>` (fix: `voice speak --replace`), `captions-source-changed-<media>` and `beats-source-changed-<media>` when the source no longer matches. Measurements stay revision-checked as before.
- **`capabilities get` (P2-G5).** Each plugin capability (or one, optionally for a library kind) with `available` or a `reason` — `missing`, `not_configured` or `unhealthy` — every provider's plugin, priority, `paid`, state and detail, and the commands that call it; health checks run in parallel, bounded at about 8 s. Provider resolution reports the same reasons: a command whose capability cannot serve fails with category `capability_missing` and `data {capability, reason, providers}` (job commands at the call, not in the job), and a failed job keeps its typed `errorCategory`.
- **`jobs wait`, usage and paid requests (P2-G4).** `jobs wait <id> [--timeout 1–30]` returns when the job's state or step changes or it finishes (the CLI and MCP socket wait long enough for it). Every job reports `step` and `usage {provider, wallSec, units, costUSD, costSource}`; units and cost come only from what a provider reports in its result's `usage`, never estimated. `voice speak` and `library generate` take `--request-id` (a resend returns the same job; the provider receives `requestId`) and `--dry-run` (the frozen request without option values, whether the provider is `paid`, and its estimate when it declares `estimates`). Providers gain `paid` and `estimates`.
- **Video this Mac cannot decode is converted on import.** AV1 (on Macs without an AV1 decoder, such as M1 and M2) and VP9 without its decoder now get an H.264 copy made with the system's ffmpeg as a `media.convert` job, in `media/converted/<media id>.mov` with the same frames and frame times; the media then reads the copy (`originalPath` keeps the original, which is never touched). A transcript made before the conversion is carried over to the copy (same sound and times), so it is not lost when the media switches files. `media import` returns `proxy` (`converting` with the job), and `media proxy` answers `converting` instead of `unsupported`, which now only means there is no ffmpeg. Before, an agent given an AV1 YouTube download stopped and asked the user to run ffmpeg.
- **Agents never stop to wait for the user after intake.** After one round of questions at intake, the agent instructions say to fix a failed step itself or take the best fallback, finish the edit and list what waits on the user in the final summary; `capability_missing` and `unsupported_media` no longer tell agents to ask the user.
- **VP9 footage previews and exports.** BashCut registers the system's supplemental VP9 and AV1 decoders at launch; before, a VP9 `.mp4` imported and analyzed but every frame failed to decode (`ui frame` "Cannot Open", exports held one frame that review called black). Video a Mac still cannot decode is left out of the preview build instead of breaking it, `ui frame` on its frames and `export start` fail with the new error category `unsupported_media` (media, codec, frames and a conversion hint), and `media proxy` answers `unsupported` instead of `not-needed`.
- **Why, evidence and a fingerprint on edits (P2-G3).** `timeline apply --why --evidence` keeps the reason and its references (review issue IDs, transcript ranges, measurements) with the undo step and the saved history; `edit.committed` carries `why`. Dry run and apply return `fingerprint` (ops + base revision); `--expect-fingerprint` refuses ops that differ from the reviewed dry run. New `timeline changes [--limit] [--author]`: recent edits newest first with author, label, why, evidence, time, revision and a short change digest, plus the undone ones. A file conflict while editing or saving is now `-32003` `file_conflict` (was `-32602` invalid arguments).
- **Typed error data (P2-G2).** Every RPC error's `data` carries `category`, `retryable` and, where a factual next step exists, `remediation {command?, hint}` (CLI, MCP and socket alike); a command's own data stays. `-32003` keeps its code and splits by category: `busy_dialog`, `busy_approval`, `busy_running`, `file_conflict`, `not_available_now`. `context get` › `recentFailures` lists the session's failures of the last 15 minutes and how many in a row repeat. A stale revision inside commands that wrapped project errors as `-32602` (selects, plan, transcripts, presets and others) now comes back as `-32002` with expected/actual.
- **Fixes from live-testing P1 (D7–G1).** `selects place` and `project derive` put sound-only selects (a podcast, a voice memo) on the dialogue layer instead of failing on Main. `selects mark --reason` keeps the pick's `reason` and records `statusReason`, shown in the Selects tab. `ui view --media-source footage|project|shared|selects` switches the Media panel (the Selects tab had no command). `variants diff` compares media as the files they name, so a variant's relative paths and a symlinked footage folder are not a change. Delivered QC measures the rate frames are written at from frame times, so a held black or still stretch and a 1/600 timescale's 20/21-tick frames are no longer a wrong-fps error (`averageFps` reports the plain average). New error `gap-end`: Main ends while sound or text goes on. `media resolve-range` documents `matched`.
- **Edit results carry a change digest (P2-G1).** Every edit or privileged command that changes the project returns `changes`: items added, removed and modified (with the fields), layers, project fields, durations, counts, `truncated` past 40 rows, and `+ ~ -` lines in `text`.
- **Covers, chapters and captions per output (P1-F3, P1-F4).** `export cover <frame> [--aspect]` writes a centre-cropped still per output's cover aspect into render/; `export chapters [--platform] [--write]` lists chapters from section markers and checks the platform's rule (first at 00:00, count, shortest). `output.captions` sets per preset burn, sidecar, both or none, SRT or WebVTT and the caption layer; caption layers carry `language` (`layers set --language`) and the export follows the setting.
- **Review mechanics (P1-E3–E8).** `review verify <id>` re-measures one issue over its own range (picture re-sampled only there) against how an earlier round saw it, with a still window as proof. `review packet` writes an evidence folder for a fresh critic (plan, change digest, issues with round diff, cuts, word landing, hook, coverage, what was measured, a contact sheet) with no editor reasons. `review run --summary` adds `checks` (measured, stale, notChecked, failed/timed-out plugin checks, unreliable picture, unset limits); a picture that never changes is reported unreliable, not passed. Every export is measured from the file (stream starts and drift, fps and size against the preset, black and silent stretches; `export status` → `delivered`) and review reads it: drift over a frame, a wrong size or rate and black inside are errors. `review sync --events captions` times each caption against its first word. `review compare --reference --ours` puts two measured files side by side by the same functions; tolerances only from `review.compare`. Negative-control tests make every detector fail on purpose (1-frame gap, 0.3 s caption shift, cut inside a word, frozen second, end card 15 dB down).
- **Derived projects and variants (P1-D9).** `project derive` writes a sibling project per kept select (same canvas, outputs, review profile, brief and layers; only that media, paths rewritten relative to the new folder; the range on Main; `derivedFrom`). `variants create <name> --changed` writes a full copy that records what it changes; `variants list` finds both kinds next to the project and `variants diff` compares fields, items and durations. The open project never changes.
- **Selects store and panel (P1-D8).** `selects` in the project: source ranges with status candidate/kept/rejected, quote, reason, evidence, mustKeep and order. `selects list/set/mark/remove/place` (place lays the kept ones on Main as one undoable edit); the Media panel's Selects tab lets the user keep, reject, star must-keep and place them; a must-keep select no clip plays is a review warning. New UI strings are translated to Vietnamese (workflow gates, checkpoint sheet, selects).
- **Select by quote (P1-D7).** `media resolve-range <media> --quote/--words/--from --to` turns what was said into word-edge source ranges with snap deltas, mid-word and mid-sentence flags and the nearest word and sentence edges; equal matches are listed in order, never ranked. `media place --from --to` places only that part; `captions find` says where words are said on the timeline; `timeline apply --dry-run` lists `cutsInsideWord`.
- **Platform data with provenance; feed presets and bitrate ceilings (P1-F1, P1-F2).** Platform facts live in a versioned table where each field is `{value, kind hard|recommended|info, source, checked, confidence}` (`platforms get <id>`, `platforms list --facts`); a plugin may ship a newer table (`contributes.platforms`, API 9) and `review.platform` still overrides. TikTok's bottom band is now 0.24 (measured 23–25 %, was 0.16), Reels' 0.25, Shorts' 0.20; YouTube carries chapter, title and disclosure rules. Vertical exports default under the platform's recompression line (TikTok/Shorts 8, Reels 5 Mbps, was 16), `export start --bitrate` overrides, and the export status reports the bitrate written. New presets `feed-4x5` (1080×1350), `square` and `portrait-3x4` (1080×1440). The project schema documents `brief`, `plan`, `review.accepted` and `review.blockExport`.
- **Plan vs measured (P1-D3).** `review coverage`: per planned shot the described footage shots that fit it (size, mustShow subjects), the clips that place it (`planShot` or the described shot they play) and placed/found/missing/undescribed. `script check`: per beat the share of its words heard, where, and the section it starts in against the plan. Facts only.
- **Invariants are the only default errors; review rounds and accepted issues (P1-E1, P1-E2).** New errors without review settings: a clip edge inside a transcribed word (`cut-in-word-…`, from stored transcripts) and characters the font cannot draw (`glyph-…`); overlapping text and recognition loops became notes. `review.blockExport` (issue ID prefixes) makes the export refuse while such issues are open. Frame-based issue IDs (black, still, silence, music-gap) are anchored to the Main clip and offset, so they survive edits elsewhere. `review run --since-rev N` adds `diff {fixed, new, persisting}` and the round; `review accept <id> --reason` keeps a warning or note (`review.accepted`, never an error), leaves it out of the counts and lists it in the export report.
- **Workflow gates, checkpoints and the run log (P1-D4, D5, D6).** Settings → Agents → Workflow gates sets G1 brief, G2 strategy, G3 rough-cut sheet, G4 script and G5 draft to ask (default), notify or skip, plus the review round limit; `workflow gates`/`workflow set-gates` (agents may only make a gate ask more). `checkpoint request <gate> --summary --attach` shows a sheet only the user can answer (approve, ask for changes with a note, reject; an agent can only withdraw), bound to the revision; `checkpoint status` reads it. `run log`/`run append` keep an append-only `.bashcut/run-log.jsonl` of starts, stages, gates with the user's answers, review rounds and what was measured or not; `context get` shows the gates and the waiting checkpoint.
- **Brief and edit plan (P1-D1, P1-D2).** The brief and the edit plan are project data (P1-D1, P1-D2): `project brief`/`project set-brief` and `plan get`/`plan set` (JSON file, `--merge`, one undoable edit, validated shape). Review reports the edit's length and outputs against the brief and each planned section's length against its section marker, as info; `context get` summarises both.
- **No taste in core review (P0-K1, K2, #466, #468, #469, #470, #472).** Every editorial limit is the project's:
  `review` gains `maxSilenceSeconds`, `maxMusicGapSeconds`, `voiceoverMarginSeconds`, `captionLineChars`,
  `captionMaxLines`, `stillMotion`, `jumpCutChange`, `blackMinSeconds`, `loudnessToleranceLU`, `minTextSize` and
  `minSpeechCoverage` next to the pacing and hook keys, and core keeps no defaults: without a limit a check does not
  run or reports the measured value as info (the longest shot, the longest silence…). Editorial findings are info
  unless a profile or `review.severities` raises them; gaps, missing fonts, black picture inside the edit and
  platform facts stay errors. The `review` object is validated on every edit, and severities can name a plugin
  provider (`provider:`). The jump-cut fix is a hint (no ×1.15 punch-in) and the Review sheet can apply the
  `project.format` fix. Text is checked against the zones of **every** output of the frame's shape (strictest side
  wins) with `review.platform` overrides; with no output set nothing is assumed (one note); `platforms list` shows
  the facts. Platforms no longer carry a smallest text size. Each export is normalized to and reviewed against its
  own preset's loudness (`output.targets`, else the platform's). Command descriptions carry no editing advice.

- **Speech, script and voice (P0-C2–C9).** `speech rate` measures speaking rate in the content language's unit
  (syllables for Vietnamese, characters for CJK, else words) per transcribed media and speaker (p10/p50/p90, overall,
  articulation) and lists the rates measured on synthesized takes per voice. `narration windows --min-seconds S
  [--rate R] [--levels]` lists speech-free stretches with their anchors, owner, shots, mix level and text budget.
  `voice speak` no longer scores takes by a 2.5 words/s pace: every take is reported with its seconds, units, rate,
  leading/trailing silence and pauses, and the take is chosen by `--target-rate`, `--choose` or the provider's score
  (else the first). Voiceover items keep `voice {text, language, provider, voice}`; `voice speak --replace ITEM` puts
  a new take into the item in place and times its captions again from the new take. `voice check` diffs what a take
  says against its text (similarity, matched/substituted/missing/extra words with times; `passed` only with
  `--min-similarity`); `voice fit` changes a voiceover's speed (pitch kept) to fill a slot within caller bounds, or
  refuses with the speed it would need. `voice voices` lists voices by their manifest facts with measured rates;
  `voice.synthesize` requests carry `cloneConsent`, and providers may declare `voices` and `clones`. `captions group`
  re-cuts captions from the agent's word groups (or a rule whose limits are all given) and reports cue lengths, gaps
  and overlaps. `captions align` makes captions whose text is the script, timed from the speech (the transcript, or
  a new `captions.align` provider with `--aligner`).

- **Hook and close as facts (#467, P0-B11).** `review hook` reads when the first words are heard, the first title,
  caption and cut appear, when each described subject and shot size first shows and how long it stays, frame 0's luma
  and ink share, and at the end the last title (hold, bounds, edges), the last words and the last cut. The review's
  hook check no longer asks for a number or a question or speech in the first 0.5 s: it runs only when the project
  sets `review.hookSeconds`, and then reports nothing said or written inside that window.

- **Beat grid v2 and music energy (P0-B10, PL2).** The built-in beat tracker also returns each beat's strength,
  the downbeats (the bar phase where the kick band hits hardest), how clearly the tempo stands out, a least-squares
  grid fit (period, phase, RMS error) and the half and double tempos with their relative strength; `beats detect`
  keeps the grid per file and `beats grid --media M` reads it with the downbeats on the timeline (the timeline grid
  and `setBeatGrid` are unchanged). `audio energy --media M` (new `audio.energy` capability, built in) gives the
  level, onset density and fullness every 100 ms and lift/drop/breath candidates snapped to beats and mapped to the
  timeline: pointers, not decisions. Built-in Audio Analysis plugin 1.2.0.

- **The mix as numbers without exporting (#471, P0-B9).** `audio measure --media M --curve` adds loudness over time
  (momentary and short-term LUFS and the sample peak every 100 ms); `audio measure --timeline` renders the mix to a
  scratch file and measures it with its curve and silent stretches. `audio mix-measure` renders one stem per role
  (speech, music, sound effects; other sounds at −120 dB so ducking stays) and reports the voice level, music under
  speech and music in the gaps as median/p10/p90 overall and per spoken window, and for every sound effect its level
  and peak against the voice around it (masked when under it) and its onset and peak offsets to the nearest cut, beat
  and word. `library analyze` stores each sound's landmarks (onset, peak, tail). The `audio.loudness` contract gains
  an optional `curve`; the built-in provider supports it.

- **Colour as numbers (P0-B8).** `color measure [--items A,B] [--samples N] [--graded] [--compare source] [--by clip]`
  (`color.measure`) measures each clip on the colour skill's 0–100 scale: black/p5/mid/p95/white luma, mean,
  saturation and its p95, the tint of shadows, mids and highlights, and the clipped and crushed shares; from the
  source frames, from the edit as graded, or both with what the grade changed (black lift, chroma ratio, clipping and
  crushing growth, mean ΔE), and each clip's difference from the median clip. The kit no longer needs ffmpeg and
  NumPy to measure colour.

- **Text, layout and scale facts (P0-B6, P0-B7).** `review layout` adds per text item its hold, words and words per
  second, how it sits against the speech (onset offset from the nearest word, share of its time with words spoken),
  how much of a caption a title covers, how often its template repeats on its layer, titles and captions per minute,
  and at a frame the pictures on screen with their scale; `--contrast` measures each item's WCAG contrast on the
  rendered frame against the same frame without text. Face fields stay null until a `vision.faces` provider exists.
  `timeline get` and `review shots` give each video or image item's `scale`: fit or fill, base scale, zoom now and
  at its largest key, output pixels per source pixel at both, `maxZoomNative` (the largest zoom before upscaling) and
  frame coverage. The compositor's fit/fill scale now comes from the same core function.
- **Phone-width frames and before/after grids (P0-B5).** `ui frame --phone` (390 px) or `--width N` renders the
  viewer at viewer size; `ui frames --compare graded|source --frames F,F | --items A,B` puts the frame without colour,
  or the clip's source frame, next to the edit in one grid.

- **The edit as pictures without exporting (P0-B3, P0-B4).** `review window F [--span N] [--step N]`
  (`review.window`) draws the composed frames around frame F with the cuts as lines, the timeline's sound level and
  the heard words, and returns the level per frame. `timeline sheet [--at F,first,last] [--cuts] [--text] [--every
  S] [--outputs all|presets]` (`timeline.sheet`) lays the composed edit out on labelled contact sheets with an index
  of the items and text on screen in each cell (also written as `index.json`, kept per revision and request in
  `.bashcut/cache/timeline-sheets`); `--outputs` adds sheets with each output's covered zones shaded.
- **Cuts and timing as data (P0-B2).** `review cuts` lists every cut on Main with its kind (hard or the transition,
  with length and easing), a gap before it, the framing on both sides and whether it stays the same, with counts and
  runs per kind. `review sync [--events cuts,text,sfx] [--rendered]` gives each event's offset to the nearest beat
  and word edge (frames and ms) and their distribution; `--rendered` matches the last export's sound to the
  timeline's mix every 10 s and reports each window's lag and the drift per minute.
- **Shots as a sequence (P0-B1).** `review shots` adds per shot the `cut` into it (`sameMedia`, `sameSetup`,
  `sourceGapSeconds`, size/move/direction from → to from `media describe`) and `cameraMove` from its keyframes
  (property, from, to, change per second, ease). With `--summary`: `rhythm` overall and per section marker (mean,
  median, cv, cuts per minute, the most common length bin and its share, and with `--run-length N --max-cv X` the
  runs whose lengths vary less), runs of the same described size and move, and shares of each size, move and
  direction. `--media ID` gives the same for a source file's measured shots.

- **Footage inventory and analysis readiness (P0-A6).** `media inventory [--location-grid D]` (`media.inventory`,
  read) lists each media's capture time, GPS position, device and shown size/orientation as the file records them
  (read once per file content, kept in `.bashcut/cache/inventory`), speech seconds and language from the stored
  transcript, and whether it is measured, transcribed and described, with totals per folder and for the project
  (places grouped on a grid, IDs not yet measured/transcribed/described). `context get` gains `analysis`: running
  `media.analyze`/`media.transcribe`/`review.measure` jobs and the media not yet measured, transcribed or described.
  Content keys are remembered per path, size, modification date and inode.

- **Source frames as pictures (P0-A5).** `media frames [--media A,B] [--at S,S | --every S | --count N] [--from S
  --to S] [--sheet] [--reference M]` (`media.frames`, read) writes exact source frames as PNGs with their frame index
  and second, or contact sheets whose cells are labelled `<cell> <file> <m:ss.s>` (colour per media) with a cell map
  back to media and second; `--reference` adds a REF row above OURS. `media frame --media M [--at S | --index N |
  --edge first|last]` writes one frame at source size, and `media strip --media M [--from --to]` a filmstrip with the
  sound level, the speech-map gaps and the stored transcript's words. Files go to `.bashcut/cache/media-stills`
  (newest 300 kept). Agents no longer need ffmpeg to look at footage.

- **Shot descriptions (P0-A4).** `media describe shots.json --media M --base-rev N [--merge] [--clear]`
  (`media.describe`, edit) stores what the agent saw in a source file, shot by shot, on the media in the project
  (new optional `media.description`, op `setMediaDescription`), so it is undoable and survives save and reopen.
  Each shot has source `start`/`end` and facts in a closed vocabulary: `size` ECU…EWS/insert, `angle`, `move`,
  `direction`, `subjects`, `people`, `onScreenText`, `confidence`, nullable `bestMoment`, the frames `looked` at and
  a short `note`. Unknown fields or values are rejected and there is no field for pairings. `media description
  [--media M]` reads them with coverage of the `media analyze` shots ("38/40", `missing`), `media list --analysis`
  shows each media's coverage, and `review shots` adds `described` facts to every clip from the source shot it plays.

- **Speech map with its calibration (P0-A3).** `media speech-map --media M` (`media.speech-map`, read) splits the
  `media analyze` level windows into quiet and loud by Otsu's method (digital silence counts as quiet and is left
  out) and reports the floor, the loud level, their separation in dB and the share of variance the split explains.
  When they do not separate (`--min-separation-db`, default 6) it returns `separation: none` and no spans instead of
  made-up silences; otherwise spans and gaps in source seconds with gap statistics. `--threshold-db` skips the
  calibration. With a stored transcript it adds the spans where words were recognised and how far the two agree.

- **Source transcripts (P0-A2).** `media transcribe [--media M] [--provider P] [--force]` (`media.transcribe`, a
  job) transcribes whole files once with a `captions.transcribe` provider and keeps the transcript by file content
  in `.bashcut/cache/transcripts`, without touching the timeline. `media transcript --media M --as
  phrases|words|json|text [--from S] [--to S]` reads it in source seconds: phrases with their gap and mean
  confidence, words with the provider's `confidence`, `speaker`, `event` and `noSpeechProb`, and precision flags
  saying which of these the provider gave. `captions generate` places captions from the stored transcript instead
  of transcribing again (`--fresh` transcribes again; the job's result says `stored`, `transcribed` or `range`).
  `transcript words --heard` maps the stored words through the clips that play each media now, so they follow
  trims, moves and speed changes. `media list --analysis` adds each media's transcript overview. The
  `captions.transcribe` word file gains those optional per-word fields.

- **A measured record per media (P0-A1).** `media analyze [--media M] [--force] [--rate N]` (`media.analyze`, a
  job) measures source files once and keeps the record by file content in `.bashcut/cache/analysis`: file facts
  (codec, size, rotation, frame timing for variable frame rate, colour transfer, primaries and bit depth, track
  lengths), picture samples with the `review picture` values plus sharpness and colourfulness, every jump narrowed
  to its exact frame as a cut candidate, and sound levels per 0.1 s with peak and stereo correlation.
  `media analysis --media M` (read) derives cuts, shots with the `review shots` fields and statistics, a
  shot-length histogram, cuts per 10 s and active sound spans, with limits the agent chooses (`--min-score`,
  `--activity-db`, `--bridge`). `media cuts --media M --add S --remove S` corrects the cut list;
  `media list --analysis` shows what is measured.

- **Captions and spoken words as data (P0-C1).** `captions export --as json|text` adds two formats next to
  SubRip: JSON cues with timing in frames and seconds, characters, characters per second, the gap since the previous
  cue, line count, the media they were made from and their words; `text` is one line per cue for a cheap read.
  `transcript words [--from F] [--to F] [--media M]` (`transcript.words`, read) lists every word on the caption
  layers in timeline order with its frames, caption, timing kind (transcribed or estimated), the gap since the previous
  word and, for captions made from a media, its source seconds through the clip heard there now.

- **Rendered text layout for agents and the review (#465).** `review layout [--frame N]` (`review.layout`, read)
  returns each visible text item's box as `TextRenderer` lays it out: font size in pixels and as a share of the short
  side, line count, longest line, bounds in pixels and the margin to each frame edge, next to the platform's zones.
  The review's text checks (safe zones, text size, overlap) now use the same rendered bounds instead of an estimate at
  0.55 em per character.

- **Shot list for agents (#464).** `review shots` (`review.shots`, read) lists the shots on Main in order with their
  timing in frames and seconds, source media and in-point, zoom and transform, speed, keyframed properties, the gap
  before, the transition in or the picture difference across the hard cut, and the measured motion (mean and peak
  change) when `review measure` ran for this revision. `--summary` adds count, mean/median/min/max length and cuts per
  minute. No verdicts: a skill compares them with its genre's range.

- **Raw picture data for agents (#463).** `review picture` (`review.picture`, read) returns the measurement behind the
  picture checks of the last `review measure`: every sample `{frame, seconds, luma, spread, change, peak}` and every
  hard cut on Main `{item, fromItem, frame, before, seconds, difference}`, with the units and the noise floors the
  checks use (`floors`). `--from/--to` limit the range, `--samples false` / `--cuts false` leave a part out, and
  `current` says whether the timeline changed since. No verdicts: an agent can find a frozen stretch or a
  near-identical cut from the numbers alone.

- **Agents use the runtimes plugins share.** Agent terminals get `BASHCUT_SHARED_DATA`, `BASHCUT_SHARED_CACHE` and
  uv's `UV_PYTHON_INSTALL_DIR` / `UV_CACHE_DIR` pointing at BashCut's shared plugin folders, so the agent kit's
  Python scripts (`uv run`, `uvx`) reuse the Python and packages Whisper and VieNeu installed instead of a second copy
  in `~/.cache/uv`, and Settings › Storage counts and clears all of it. Codex's sandbox may write those folders. The
  folders stay fixed (no setting to move them).

- **Platform output presets with targets (#441).** Export presets now include **Instagram Reels** and **YouTube
  Shorts** (1080×1920, rendered like TikTok; `reels` was a TikTok alias before). Each social preset names a platform
  with its longest upload (TikTok 10 min, Reels and Shorts 3 min), loudness (-14 LUFS, -1 dBTP), the zones its UI
  covers (Reels' caption bar is 20 %, Shorts' 18 %, TikTok's 16 %) and the smallest readable text. A project records
  the presets it is made for in `output.presets` (format menu › **Platform**, or `project format --outputs
  reels,youtube-1080`); the review checks the first one's platform — safe zones and text size follow it, a cut longer
  than the platform takes is an error and a frame of another shape warns with a `project.format` fix — the viewer's
  safe-area overlay draws its zones and the Export sheet starts with its preset. A project's `review` object also
  takes `hookSeconds` and `severities` (check ID or prefix → `error`, `warning`, `info` or `off`), so a genre recipe
  can tune the review; `output` and `review` are in the project schema.

- **Plugins can contribute review checks (plugin API 9, #451).** A provider of the new `review.check` capability gets
  the project and returns issues in the review's shape (severity, frame/endFrame, optional fix). `review measure`
  runs every enabled check side by side with the picture measurement, each for at most 30 s; a check that fails,
  returns a malformed result or times out becomes one info issue and never stops the others. `review run` merges the
  issues of the current revision with `source` (the plugin ID) and IDs prefixed with the provider; the Review sheet
  shows *From plugin …*. A project turns checks off with `review.disabledChecks` (plugin or provider IDs), and
  `plugins hooks` lists them under `reviewChecks`. `review measure` takes `--picture` and `--plugins` (both default
  true).

- **Review checks the rendered picture (#432).** `review measure` (a job; **Measure picture** in the Review sheet)
  renders the timeline small, two frames a second plus both sides of every hard cut on Main, with proxies, and keeps
  the measurement for that revision (a 3-minute 1080p edit takes about 9 s in a debug build). `review run` then
  reports black or empty picture of 0.5 s or more (error; a fade out of up to 1 s at the end passes), frozen picture
  longer than 4 s on vertical or 8 s on landscape outside freeze frames (no part of the picture moves: a mouth or a
  ticker keeps it alive), and jump cuts (under 6 % change across a cut
  that is not already "Repeated framing", with a punch-in fix). Shot length is checked from the timeline: under 0.4 s
  is a note, over 8 s (15 s landscape) warns when the picture barely moves and passes when it keeps moving. A
  project's `review` object (`minShotSeconds`, `maxShotSeconds`, `maxStillSeconds`) overrides the pacing. Issues over
  a stretch carry `endFrame`; without a measurement of the current revision the review adds a "Picture not measured"
  note with a `review.measure` fix.

- **Import counts a video's frames up to its last picture (#437).** `Media.frames` came from the container duration,
  so a camera file with sound past its last picture offered 1–3 timeline frames without picture (the cause of #420).
  Import (and stickers made from videos) now ends at the video track's last picture; audio files and images are
  unchanged. Media already in a project keep their frame count, and the edge hold from #420 still covers them.

- **Review grades issues and checks sound, text placement and the hook (#435, #431, #433, #434).** Every issue has a
  severity (`error` spoils the export, `warning` hurts it, `info` is a note), errors first, and a `fix` when one
  exists: a command with arguments (`timeline.close-gap`, `timeline.apply`, `export.start`) or a hint. `review run`
  takes `--min-severity` and `--summary` (`{issues, summary: {errors, warnings, infos, passed}}`); the Review sheet
  colours rows by severity and applies edit and export fixes with **Fix**. New checks: loudness against the project's
  `audio.targetLUFS` (±2 LU, true peak ≤ -1 dBTP) from the last normalized export of the same revision (info when not
  measured); Music with ducking off under speech; dead air over 1.5 s; a music bed that drops out; text under the
  vertical caption bar (error, with a fix that raises it), the side buttons or the top bar; text outside title safe on
  landscape; text below 3 % of the short side; vertical captions over two lines or 32 characters; overlapping text;
  and no hook (text with a number or question, or speech) in the first 3 s. Thresholds come from a study of 30
  Reelcrew/AgentVid videos.

- **Export no longer fails with `BashCutCompositor.MissingFrame 2` when a clip reaches its media's first or last
  frame.** `Media.frames` comes from the file's duration, and camera MOV/MP4 files often have sound before the first
  picture or after the last one. Clips, freeze frames, transition holds and speed ramps that reach past the pictures
  now hold the first or last picture, split on the timeline's own time scale (a nanosecond-rounded split made the
  composition longer than its instructions, AVError -11841). Exports that end on a held picture (freeze frame, still,
  last source picture) repeat it on the last frame, so the video track no longer ends before the sound.

- **Plugin authors.** A manifest may name its author: `"author": {"name": "…", "url": "https://…"}` (url
  optional, http or https). Plugins › Installed and Browse show *By <name>* (a link with a url), Browse search
  matches it, and `plugins list` / `plugins search` return `author`. The registry copies it from the manifest; the
  `publisher` (who signs and ships) stays separate. Metadata only: no plugin API bump, older versions ignore it.
- **Text fonts and colours end to end (#412–#415).** `textStyle.font` (PostScript name), `fill`, `stroke` and
  `highlight` (`#RRGGBB`) are declared item properties: validated, in `project.schema.json` and `schema get`.
  Inspector › Text adds a font menu (preset, project fonts, installed families; fonts without Vietnamese letters are
  marked), text and outline colours and outline width. Library text presets keep font and colours, and the Text
  panel cards show them. Projects carry fonts: `fonts import` (or Add Font…) copies a font into the project's
  `fonts/` folder, registered for the app process when the project opens (nothing is installed on the Mac);
  `fonts list` gives names and Vietnamese coverage; `review run` flags a font that would fall back to Helvetica.
- **Plugin API 8: plugin panels, declarative views and plugins using other plugins (#390–#397, #399).**
  `contributes.container` adds the plugin's icon to the left rail; it opens a panel BashCut draws from the manifest
  (header, view picker, Tools, Skills, Requires, Uses with Find…) around the plugin's `contributes.views`. A view is
  JSON components the plugin returns from `view.render` / `view.event` (section, row, text with markdown, badge,
  keyValue, progress, image, imageCompare, audio, list, button, textField, textArea, toggle, picker, slider; unknown
  types draw a placeholder), drawn natively: only while visible, one request at a time with coalesced changes,
  debounced search, sliders on release, lazy lists, cached downsampled images, at most 2000 components. View requests
  and session actions of API 8 plugins get the host channel and call app commands as author `plugin` (for example
  `voice.speak`, so a plugin speaks with whichever voice plugin the user chose). `uses` + `plugins.invoke` call
  another plugin's capability raw; `requires` (semver ranges) keeps a plugin `needs-plugin` until the plugins it needs
  are installed, in range and ready, and installing it from the registry offers them next. `features` and the
  hello's host feature list replace one API bump per feature. New commands: `plugins views`, `plugins view`,
  `plugins view-event`, `plugins invoke`; `plugins list` reports container, views, requires and uses.
  A view's `location` puts it in the rail panel (default), a tab in the agent dock (`dock`) or a sheet (`sheet`,
  closed with Close, `ui respond close` or an answer's `close: true`); `plugins show-view` and the host call of the
  same name (own views only) open one where it lives, and the panel lists a plugin's dock and sheet views.
  Benchmarked (`scripts/verify.sh perf`, plus a live run): plugin answers are read with `JSONValue(parsing:)`
  (`JSONSerialization`, same values as `JSONDecoder`; 186 KB in 5.7 ms instead of 82 ms), the panel is one lazy
  column (worst main-actor stall for a 1900-component view 212 ms → 16 ms in a debug build), streamed renders are
  drawn at most every 60 ms (300 in one request: 179 ms → 16 ms), answers are parsed off the main actor, and typing
  15 characters in a search field sends one request.
- **Plugins can ship agent skills (#375, #376, #377).** Plugin API 7 adds `contributes.skills`: `SKILL.md` folders
  inside the plugin (front matter `name` equal to the folder, a `description`; at most 16 skills, 64 KB per
  `SKILL.md`, 2 MB per folder, nothing linking out of the plugin). A bad skill is reported by `plugins validate` and
  in `plugins list` diagnostics and left out. While the plugin is trusted, turned on and compatible, its skills are in
  the new read-only `plugin` scope as `<plugin-id>:<name>` (`skills list --scope plugin`, `skills get`; without a
  scope `get` looks in the project, every project, plugins, then the kit), listed with their paths in the agents'
  knowledge, linked into the open project's `.claude/skills` and `.agents/skills` as `<plugin-id>--<name>`
  (recorded in `.bashcut/plugin-skills.json`, so only those links are ever removed), into the Codex tab's workspace
  and into terminal plugins' `skillsFolder`. Turning the plugin off, revoking Trust or removing it takes them away.
  Knowledge › Skills lists them under Plugins with Copy to This Project / Copy for Every Project; `skills save`,
  `enable`, `disable` and `remove` refuse the plugin scope. `plugins list` reports each plugin's `skills`, and the
  Plugins sheet and install approval name them. `Fixtures/plugins/example.skills` is an example.
- **Plugin confirmations no longer freeze the app.** An action that declares `confirm` used to ask in a modal alert
  that stopped every command (agents' calls timed out) until it was answered. Its job now waits for the user in a
  `plugin-confirm` sheet instead, so the app keeps answering; agents see the job running and the sheet in
  `ui dialog`, and can only cancel it (`ui respond cancel` or `jobs cancel`). Running an action from its parameter
  sheet no longer asks a second time.
- **`context get` scope for agents without a tab.** A session that has no tab of its own, such as the external agent
  token, now gets `scope: null` instead of the shown tab's scope, which the guard never applied to it. A read
  without a token still sees the shown tab's.
- **Codex: text after a sent scope starts on a new line.** Codex drops the newline at the end of a paste, so a
  request typed after Send to Agent was glued to `[/Scope]`. BashCut now ends the paste with Ctrl+J, which Codex
  takes as a new line.
- **Settings like VS Code (#384).** Settings no longer uses grouped forms, which macOS caps at about 600 pt: its
  section cards stretch with the sheet up to 1000 pt. A search box above them lists the matching settings of every
  section (title, description and keywords, in English or the interface language, ignoring case and accents, so
  "clip da gui" finds "Sửa ngoài các clip đã gửi"); the sidebar shows each section's matches, and a search for a
  plugin option opens its plugin. Agents drive it with `ui view --settings-search <text>`, and `ui view` reports
  `settingsSearch`.
- **Allow all agent actions by default.** **Dangerously allow all agent actions** is now on unless you turned it off:
  agents edit, export and run plugin actions without asking, and the scope guard is off. Turn it off in Settings ›
  Agents › Agent permissions to get the separate switches back.
- **Scope guard fixes (#356).** An agent edit with a stale base revision now fails with `-32002` instead of being
  held, and a held edit the user allows keeps its base revision. Items made by an edit the user allowed (Allow Once
  or Allow for This Request) join the scope, so later edits to them are not asked again. Return no longer allows a
  held edit. Closing the agent's terminal tab, or turning agent edits off, rejects its held edit.
- **Dangerously allow all agent actions.** Settings › Agents has a new **Agent permissions** section: Allow agent
  timeline edits, **Approve agent actions without asking** (was "Run agent exports without confirmation"; it always
  covered kit setup, library items and preferences for every project too), Edits outside the attached clips, and a
  new master switch **Dangerously allow all agent actions**. Turning it on asks once; while on, the other three are
  shown on and locked, agents edit and run privileged actions without asking, the scope guard is off, and plugin
  actions with `confirm` run without the dialog when an agent starts them. Installing and trusting plugins still needs
  the user, and no command can change the switch. `context get` reports `agentPermissions`
  (`edits`, `autoApprove`, `scopeGuard`, `allowAll`).
- **Larger Settings.** The Settings sheet now takes the main window less a margin (820×600 up to 1400×1000), like an
  editor tab. Collapsible rows (plugin options, storage per plugin, plugin diagnostics and install output) open and
  close when any part of their title row is clicked, not only the chevron.
- **Scope guard (#356).** While a chat or terminal tab has clips attached with Send to Agent, the app checks each
  edit that tab's agent makes. Edits to the attached clips, their linked partners, items those edits make, and new
  items inside the attached range run as before. An edit that changes other clips or the whole project (layers,
  project settings, format, sections) follows Settings › Agents › **Edits outside the attached clips**: **Ask
  first** (the default: the edit is held and a sheet offers Allow Once, Allow for This Request and Reject; only the
  user can allow), **Block**, or **Allow**. The command fails at once with the new code `-32004` (CLI exit 77),
  listing the items in `data.outOfScope` (`held: true` when it waits for the user); a held edit the user allows is
  applied then, and `context get` reports the answer as `scope.last`. Terminal tabs now show their attached clips as chips over the terminal; `agent detach [--items]`
  removes them, and `agent terminals` lists each tab's `scope`. `context get`'s `scope` is now the caller's own tab's,
  with the guard `mode`, `allowedForRequest`, `held` and `last`. Shell tabs are the user's own and are not checked.
- **Text presets keep their style (#380).** A `text-preset` library item can store `textStyle` (`size`, `positionY`,
  `strokeWidth`, with the item property ranges) and `animation` (a `clip motion` preset) next to `textPreset` and
  `text`. `library save-selection --kind text-preset` keeps the selected text item's style and its motion preset
  (when its keyframes are exactly one); `library place` and `library apply` set them back, apply as one undo step with
  the stored style over the item's own. `library add|update --params` validate them. Items without a style behave as
  before, and `library stats` tells styles apart when looking for duplicates. The Text panel's cards show the stored
  size, position and outline, and Edit… on a saved text style changes them and the animation.
- **Plugin library (#81), plugin API 6.** `contributes.library` lists library pack folders inside a plugin (the
  `pack.json` format of `library import-pack`); `plugins validate` checks each pack and its files, which must stay inside
  the plugin after symlinks. While the plugin is ready, its items are listed in the read-only `plugin` scope
  (`createdBy` names the plugin) and the panels group them under the plugin's name; an ID that is built in or already
  used by another plugin is left out with a diagnostic in `plugins list`. Placing or applying a plugin item copies its
  file into the project by content first (also for plugins in the project's `.bashcut/plugins`), so removing the plugin
  never breaks the timeline; `library update --as` saves an editable copy. New capabilities `library.search` and
  `library.generate` (providers may list the `kinds` they serve) return candidate items with files in a request folder
  under `~/Library/Caches/BashCut/LibraryCandidates` (pruned after a day); `library search <text> --kind K` and
  `library generate <prompt> --kind K [--params]` run them as jobs (`--provider` takes a plugin or provider ID), and
  `library add --from-result <job>:<index>` (or `--save <index> --scope project|user`) saves one with its source, license
  and the provider as `provenance`; agents saving to the user scope wait for approval. Library panels show Search… and
  Generate… when a plugin provides them for their kinds: a sheet (`ui open library-search|library-generate`, dialog
  `library-search`) that previews and plays candidates and saves them. `plugins list` reports each plugin's packs and
  provider kinds. Manifests using any of this need `apiVersion` 6; older plugins stay valid.
  `Fixtures/plugins/example.library` is a worked example.
- **Sticker library (#64).** Stickers are library items of four kinds, `params.stickerKind`: `emoji` (as before),
  `image` (PNG, JPEG, HEIC, WebP…, transparency kept), `animated` (GIF, APNG, animated WebP) and `video-alpha` (a
  .mov/.mp4 with an alpha channel: HEVC with alpha or ProRes 4444). `library add --kind sticker --file` reads the kind,
  pixel size and frame count from the file and refuses a movie without alpha; Lottie is refused with a clear message.
  Optional defaults in params: `size` (width as 0.01–1 of the frame), `position` (a named spot inside the safe area,
  `center`, `top-left`… `bottom-right`, or `{x, y}`), `animation` (a `clip motion` preset, applied around the
  sticker's own size and place) and `seconds`. `library place` on an image, animated or video sticker copies its file
  into the project's `stickers/` folder once per content (`library-<hash>.<ext>`), imports it and places it on the
  Overlay layer (added when missing) at the playhead or `--at-frame`, with new `--position` and `--size`, as one
  undo step; emoji stickers place as text as before. Animated stickers show their first frame for now (the result
  says so); a sticker movie plays once and is previewed without a proxy, which would drop its alpha. `library
  save-selection --kind sticker` saves the selected image or alpha-movie overlay with its size, position and length,
  or an emoji text item with its text preset. Placing a project library file (any kind, audio too) now copies it into
  the project instead of pointing at `.bashcut/library`, so removing a library item never breaks the timeline;
  `library remove` keeps (and lists under `kept`) any of the item's files the open project's media still points at
  from before. The Stickers panel shows image and movie thumbnails with animated/video badges, takes dropped images
  and alpha movies, and adds Place at Playhead, Edit… (size, position, animation) and Save selection as sticker.
- **Audio library (#78).** Audio library items carry `params` `{role: music|sfx|ambience, seconds, bpm, loopable, lufs,
  truePeak}`, all optional and checked, with mood and genre as tags; `library add --kind audio --file` measures the
  length and picks a role by it. `library place` copies the file into the project's `music/` or `sfx/` folder once per
  content (`library-<hash>.<ext>`, reused by any item with the same file), imports it and places it on the Music
  (music, ambience) or SFX layer, adding the layer when missing, at the playhead or `--at-frame`, as one undo step;
  `--duration` trims it, and a loopable sound repeats as back-to-back copies to fill a longer length (BashCut has no
  clip looping) while another plays once and says so. New `library analyze <id>` (a job) measures length, loudness
  and true peak (the `audio measure` provider) and tempo (the `beats detect` provider) on the library file and saves
  them as a new version; agents saving to the user library still need approval. `library save-selection --kind audio
  [--media]` saves a project clip or audio media. New `library preview <id> | --stop` plays a sound. The Audio panel
  shows library audio with play/stop, role, length, BPM, LUFS and loop badges, Place, Analyze and Edit… (role, loop),
  and **Save to Library…** on the project's audio. Transition and effect preset sounds now share this copy, so they
  are also named by content in `sfx/`.
- **Effect presets as recipes (#76).** An effect preset's `params.steps` is a recipe of clip edits BashCut already
  has: `motion` (a motion preset, or `focus` as fractions of the picture), `keyframes` (positions `t` 0–1 that scale
  with the clip, or integer `frame`s), `speed`, `speedCurve`, `reverse`, `freeze`, `patch` (item properties), `sfx`
  (an audio library item or the preset's own file on an SFX layer) and `text` (a text item over the clip), with named
  `params.parameters` (`default`, `min`, `max`) that steps use as `"$name"`. `library apply` runs every step as one
  undo step; `--set zoom=1.5,frames=12` overrides parameters and `--from`/`--to` applies it to part of the clip,
  split off in the same edit. A `reverse` step whose reversed copy is not rendered yet runs as a job and then
  commits. Sounds and text a preset placed are replaced when it is applied again. `library save-selection --kind
  effect-preset` builds a recipe from the clip's reverse, speed or speed ramp, framing, keyframes and the sound
  effect at its start, with a still of the clip as its preview. Old presets with `params.patch` work as before.
  The Effects panel shows previews and has **Apply with…** (parameter sliders and a frame range; the
  `effect-apply` dialog). New built-ins: Ken Burns zoom in/out, Zoom punch-in (Motion), Speed ramp and Slow motion
  (Speed).
- **Filter stacks (#79).** A look library item is now a filter stack: its grade (`params.color`: exposure, contrast,
  saturation, `lutStrength`), and optionally its own .cube LUT as the item's `file` (named by `params.lutName`), so
  it travels across projects. `library place` adds it as an adjustment and `library apply` grades a clip or
  adjustment with it; either is one undo step that also adds the LUT to the project (copied to
  `luts/library-<hash>.cube`, reused when the same file was added before). `library save-selection --kind look`
  keeps the whole stack, the LUT's strength and its file included. Looks saved before keep working unchanged. The
  Filters panel lists looks, style kits and the project's own looks (`looks save`, `style save`) in the shared
  library UI, with a built-in Looks pack (Original, Vivid, Muted film, Black & white, Bright & airy, Moody), Edit…
  for a look's grade and LUT, and .cube files accepted by Add… and drops.
- **Transition presets (#77).** A transition preset is a kind, duration, easing and an optional sound effect.
  Transitions get an `easing` (`linear`, the default, `in`, `out` or `inOut`) that preview and export apply the same
  way: `upsertTransition` takes it, and the Transitions panel has an Easing picker for the active transition.
  `library apply` (or a click in the panel) sets the transition at the cut and places the preset's sound (`params.sfx`,
  an audio library item, or its own `file`) from the cut on an SFX layer as one undo step, copying a sound from
  outside the project into `sfx/`; applying again at that cut replaces the sound. `library save-selection --kind
  transition-preset` keeps the easing and the sound a preset placed. Writable presets have **Edit…** (kind, duration,
  easing, sound; `library update --params`), and Duplicate & Edit shows the same fields. New built-in Transitions
  pack: Soft dissolve, Quick whip, Zoom punch.
- **Opening a project looks for earlier agent conversations faster (#351).** The scan parses a session file only
  when its bytes hold the project's or workspace's path, remembers what each file held, and on the next open reads
  only files that are new or changed. Closing or switching the project stops a running scan.
- **Faster status commands (#349).** `storage get` measures folders the way `du` does (about 0.1 s instead of
  1.8 s with large plugin runtimes). `agent status` checks Claude Code and Codex at the same time and keeps the
  answer for 30 seconds; a different kit, search path or configuration folder, setting an agent up and Settings ›
  Agents check again. `chat status` asks every chat agent at once and no longer reloads their slash commands.
- **Director is now AI Editor.** The chat-agent plugin's name in docs and the command catalog; the plugin itself was
  renamed in `bashcut-plugins` (ID still `bashcut.director`). Agent instructions now say what a `[Scope]` block or
  `scope` in `context get` means: change only those items, and ask before changing anything else.
- **Send to Agent (#355).** Right-click a clip (or a multi-selection), the Clip menu or the multi-selection
  Inspector → **Send to Agent** attaches the clips to the open agent's request. A chat agent shows them as chips
  over its input (`Clip · Main · 00:12–00:18`; × removes one) that stay when the selection changes; every message
  carries them as a `[Scope]` block with the item IDs and the rule to edit only those, and the transcript keeps
  them. A terminal agent gets the block pasted in its input. With no agent open, the first chat agent opens. New:
  `ui action clip.send-to-agent`, `chat attach --items a,b`, `chat detach`, `scope` in `context get` and
  `chat transcript`, and `scope` in the chat plugin's `turn` parameters. The Ask agent sheet names the number of
  selected clips.
- **Timeline multi-select (#357).** ⌘-click toggles a clip, ⇧-click selects a run of clips on a layer, dragging
  over empty space draws a selection rectangle, ⌘A selects every clip and Esc clears the selection. Delete, Lift,
  Mute, Copy, Cut and Paste act on every selected clip as one undo step, and dragging a selected clip moves them all
  by the same amount (clips on the magnetic main layer stay in place). The Inspector shows the count and the shared
  actions. `context get` and `ui view` add `selectedItems`, `ui select` takes `--items a,b,c` and `--add`, and the
  `selection.changed` hook adds `items`. New actions: `timeline.select-all`, `timeline.deselect`, `clip.copy`,
  `clip.cut`, `clip.paste`, `clip.mute`.
- **Edits that change nothing are not edits (#347).** `timeline apply` with a batch that leaves the project as it
  was keeps the revision, adds no undo step, no agent ◆ marks and no plugin hook, and returns `changed: false`.
  Repeated agent edits no longer fill History or make other clients' `baseRev` stale.
- **Re-importing a file reuses its media (#346).** `media import` (and Import or drop in the app) of a file the
  project already has, unchanged, returns that media with `existing: true` instead of a duplicate entry;
  `--place` still places a new item.

- **Shorter agent kit skill names.** Kit 0.1.0 is the plugin `bc` with skills such as `audio-mix`, so Claude Code
  and Codex show `bc:audio-mix` instead of `bashcut:bashcut-audio-mix`. Codex links are `bc-<skill>`. `agent setup`
  replaces the old `bashcut` plugin and removes the old `bashcut-<skill>` links; Settings → Agents shows an old
  plugin as an older kit until **Update** runs. The MCP server is still `bashcut`.

- **Faster edits on long timelines (#348).** After an edit the timeline repaints only the clips and gaps that
  changed (and clips whose selection, review warning or agent badge changed) instead of every visible clip, and
  the layer header repaints only when the layers change. One edit round trip at 1,000 clips: 52 → 23 ms; at 100
  clips: 27 → 16 ms (release build). Waveform bars now sit on a grid from the clip's start, so a partial repaint
  draws the same bars.

- **Feature bench.** `scripts/bench-features.py` runs every command group end to end against the running app in a
  scratch project (generated media; the open project is saved and reopened): media, timeline edits with exact
  undo/redo checks, clip speed/motion/keyframes/reverse, layers, colour, captions, library, knowledge and skills,
  dialogs, save and reopen, export length, OTIO, legacy EDL, service commands, a 500-clip stress project, and
  whether the UI stays responsive during exports and slow commands. It writes report.md/report.json.
- **Close buttons read "Cận cảnh" in Vietnamese.** The dialog button **Close** and the **Close** framing preset
  shared one key, so every **Close** button showed the shot-size word. The framing preset is now **Close-up**
  (Cận cảnh) and **Close** is **Đóng**.
- `media place` and `media import --place` put audio media on the Music layer by default, like Import in the app;
  they used the Main layer and failed with "audio media cannot go on a video layer".

- **Library panels you can manage (#80).** Audio, Text, Stickers, Effects, Transitions and Filters each show their
  library items with search, pack, tag and scope filters, a badge on items an agent made and on items saved in the
  project or on this Mac, **Add…** and drag-and-drop for files (audio, sticker images) and packs, **Save selection
  as…** (a text style, a clip's framing, the transition at a clip, a grade), and a context menu: **Duplicate &
  Edit…**, **Rename…**, **Move to Project / This Mac**, **Show Source & License**, **Show in Finder**, **Remove**.
  New commands: `library save-selection`, `library move`, and `ui view --library-query|pack|tag|scope`;
  `library apply` now applies transition presets (kind and duration).

- **Translate joined labels.** Labels built with `+` (`"Changed: " + keys`, plugin **Actions**, **Hooks**,
  **Dependencies**, the install sheet's **Capabilities**/**Adds**/**Listens to**, the external-changes summary, and
  the two long plugin notes) were plain strings, so they stayed in English even where the catalog had a
  translation. They are now interpolated localized keys with Vietnamese text.
- A missing plugin dependency that has no install recipe now shows **Not available on this Mac** instead of
  **Installed during setup** (`where installable` applied only to the unchecked case).

- **One source for UI translations.** Release builds read `Localizable.xcstrings`, but `scripts/run.sh` copied
  older `en.lproj`/`vi.lproj` `Localizable.strings` files, so the two drifted: dev builds showed new screens (Ask
  agent, Knowledge) in English, and release builds missed 106 Vietnamese strings that only the old files had
  (Settings, Sections, Recent projects, Doctor, word-by-word captions…). Those strings moved into the catalog, 12
  untranslated ones were added, the old files were removed and `run.sh` now compiles the catalog with
  `xcstringstool`. **Clear** in the Ask agent sheet reads "Xóa" again, and the word-by-word style **Reveal** has its
  own key so it no longer shares a translation with **Reveal** in Finder.
- `ui respond send` on the Ask agent sheet now fails, like the disabled **Send** button, when the request is empty or
  no agent is open; before, it answered OK and sent nothing.
- `knowledge memo --clear [--scope user]` empties a memo; before, an empty file was rejected as missing text.

- **Ask agent sheet with templates; short requests in agent terminals.** Claude Code and Codex fold a long paste
  into a placeholder (`[Pasted text #1 +23 lines]`, `[Pasted Content 1801 chars]`), which hid the request behind
  the context block. Survey, Write VO, Review, review fixes and **Ask the agent to split it** now paste only the
  request; agents read the selection and playhead with `context get` (their instructions say so). The dock's
  **Project context** button became **Ask agent…**, and ⌘K opens the same sheet instead of a small popover: pick a
  template (vlog, short video, product review, music montage, tutorial, captions, fix a part), fill in the parts in
  [brackets], **Clear** to start over and **Send** (⌘↩), which pastes the request and presses Return (a chat tab
  starts a turn). The draft is kept when the sheet is closed; `ui respond send|clear|close` drives it.
- **Split the memo into lessons, preferences and facts** (#72). When the project memo or the notes for every project
  have text, the Knowledge window's **Notes** section offers a one-time split: **Ask the agent to split it** puts a
  request in the open agent's input, and **Keep as notes** stops offering it. The agent reads the memo and runs the
  new `knowledge split-memo <entries.json> [--scope user]`; the lessons, preferences and facts it finds wait in the
  **Inbox** for review (lessons tagged `memo`), entries that already exist are skipped, and the memo itself stays as
  notes. The outcome is kept in `memo-split.json`, `knowledge get` returns `memoSplit` (`pending`, `split`, `kept`
  or `none`) and agents see a hint under a memo that was not split yet. `knowledge memo` works as before.
- **Skills in the Knowledge window** (#71). The **Skills** section now lists this project's skills, skills for every
  project (new: kept in `Application Support/BashCut/Knowledge/skills`) and the agent kit's skills with their
  descriptions. Project and user skills open in an editor with a Markdown **Preview**, can be turned off without
  deleting them (**On for agents**), shared with Claude + Codex and deleted (history keeps the text). Kit skills are
  read-only: **Propose change…** edits a copy and sends the diff to the Inbox as a kit proposal. New commands
  `skills list|get|save|enable|disable|remove|propose`; agents need approval to change skills for every project.
  Turned-off skills are left out of the agents' knowledge. Chips on a selected Lessons or History row are now white
  instead of blue on blue.
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
