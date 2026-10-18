import BashCutProject
import Foundation

extension CommandCatalog {
    /// Commands for the user, the app's own panels or plugin views, not for agents: still callable, but left out of
    /// the agent instructions to keep them short (flexibility audit, D10/D12/D13/A13).
    public static let hiddenFromAgents: Set<String> = [
        "project.close", "project.recents", "project.folder", "media.proxy", "export.otio", "edl.import",
        "plugins.hooks", "plugins.proposal", "plugins.updates", "plugins.validate", "plugins.install", "plugins.replace",
        "plugins.reload", "plugins.remove", "plugins.setup", "plugins.set", "plugins.show-view",
        "plugins.view", "plugins.view-event", "plugins.invoke", "storage.get", "storage.clear",
        "agent.status", "agent.setup", "agent.kit-check", "agent.kit-update", "agent.terminals", "agent.open",
        "agent.detach", "agent.ask", "agent.quick-edit", "run.status",
        "app.update-check", "app.update", "chat.status", "chat.send", "chat.attach", "chat.detach", "chat.stop",
        "chat.commands", "chat.command", "chat.reset", "chat.transcript", "doctor.run", "knowledge.approve",
        "knowledge.reject", "knowledge.remove-lesson", "skills.enable", "skills.disable", "skills.remove",
        // Inspector › Speed; agents use the setSpeed and setSpeedCurve ops (D10). Freeze Frame: setProperties of
        // freezeFrame, or an effect preset's freeze step.
        "clip.speed", "clip.speed-curve", "clip.freeze",
        // Dragging a selection, Inspector › Text › Lines and › Backdrop; agents use the move and reorder ops and
        // setProperties of textStyle.lines, backdrop, enter and exit.
        "timeline.move-items", "text.line-style", "clip.backdrop", "clip.transition",
        // Plugin overlays (plugins set them for themselves) and packaging saved skills as a plugin (#407, #506).
        "plugins.overlays", "plugins.set-overlays", "skills.export",
        // Learning facts (P3-I1–I5) the kit's self-learn and publish skills call by name: the ledger, outcomes,
        // verdicts and claims are read after a run, not while editing.
        "export.history", "export.link", "project.history", "outcomes.import", "outcomes.map", "knowledge.verdicts",
        "knowledge.claims", "knowledge.set-claim",
        // The result card's per-file Reveal in Finder: for the user watching, not for editing.
        "export.reveal-output",
        // My voices (#532): capabilities get --voices lists the clones; removing one is the user's.
        "voice.clone-list", "voice.clone-remove",
        // Generated pictures (#550): image generate returns them; the list is for checking later.
        "image.generate-list",
        // Batch pipelines (P2-C1): batch run and status are listed; cancelling and saving presets are the user's
        // (the batch window, P2-C2), still callable by name.
        "batch.cancel", "batch.presets",
        // Batch fixes (P2-C3): captions style is the batch window's step; agents restyle with patchItems.
        "captions.style",
    ]

    /// Instructions given to terminal agents, rendered from the command specs: each command's usage and first
    /// sentence; `bashcut help GROUP COMMAND` and the MCP tool descriptions have the rest.
    public static let instructions: String = {
        let commands = specs.filter { !hiddenFromAgents.contains($0.name) }.map { spec in
            let note: String
            switch spec.execution {
            case .immediate: note = ""
            case .job: note = " (job)"
            case .approval: note = " (asks the user)"
            }
            return "- `\(compactUsage(spec))`: \(firstSentence(spec.summary))\(note)"
        }
        let header = "Commands (MCP tool `bashcut_<group>_<command>` takes the same parameters; `bashcut help GROUP "
            + "COMMAND` or the MCP tool description has the full text, parameters and results; (job) returns "
            + "a job ID):"
        return ([preamble, color, plugins, header] + commands + [operations]).joined(separator: "\n")
    }()

    /// The usage with the optional parameters as one bracket of their flags: `bashcut review shots <id>
    /// [--summary --media …]`.
    static func compactUsage(_ spec: CommandSpec) -> String {
        var required: [String] = [], optional: [String] = []
        for parameter in spec.parameters {
            let text: String
            switch parameter.cli {
            case .positional: text = "<\(parameter.name)>"
            case .positionalJSONFile: text = "<\(parameter.name).json>"
            case .positionalTextFile: text = "<\(parameter.name)-file>"
            case .option(let flag): text = parameter.required ? "--\(flag) <\(parameter.name)>" : "--\(flag)"
            case .flag(let flag): text = "--\(flag)"
            }
            if parameter.required { required.append(text) } else { optional.append(text) }
        }
        let options = optional.isEmpty ? [] : ["[" + optional.joined(separator: " ") + "]"]
        return (["bashcut"] + spec.cliWords + required + options).joined(separator: " ")
    }

    /// The gist of a summary: up to its first ". ", ": " or "; " outside brackets, at most about 160 characters
    /// (cut at a word, with "…").
    static func firstSentence(_ text: String) -> String {
        let characters = Array(text)
        var depth = 0
        var end = characters.count
        for (index, character) in characters.enumerated() {
            if "([{".contains(character) { depth += 1 }
            if ")]}".contains(character) { depth = max(0, depth - 1) }
            if depth == 0, index >= 20, ".?!:;".contains(character), index + 1 < characters.count,
                characters[index + 1] == " "
            {
                end = ".?!".contains(character) ? index + 1 : index
                break
            }
        }
        var gist = String(characters[..<end])
        if gist.count > 160, let space = gist.prefix(160).lastIndex(of: " ") {
            gist = String(gist[..<space]).trimmingCharacters(in: CharacterSet(charactersIn: ",;(")) + "…"
        }
        return gist
    }

    private static let preamble = """
        You are inside BashCut, a native video editor. Prefer the bashcut_* MCP tools; the bashcut CLI on PATH is the fallback.
        Read `bashcut context get` and `bashcut timeline get` before editing. `context get` also summarizes the
        agent knowledge (active lessons, the user's preferences, project facts): follow it. Requests the user sends
        from BashCut ("this clip", "here") mean the selection and playhead in `context get`: read it first. A request that
        starts with a [Scope] block, or a `scope` list in `context get`, names the timeline items the user attached with
        Send to Agent: change only those items (and their linked sound or picture); new items such as titles or
        adjustment layers are fine inside their frame range, but ask the user before changing anything else.
        Track IDs and roles are dynamic:
        always take them from `bashcut timeline get`, never assume IDs such as v1 or t1. `timeline get` also lists
        transitions and markers (sections). To look at the result, `bashcut ui frame [FRAME]` renders the viewer
        picture at a frame to a PNG; read that image.
        Layers: tracks list visual layers back to front, then audio layers, which are mixed. There is one
        main video layer. Items never overlap on a layer; audio media never goes on a visual layer.
        Adjustment layers (kind adjustment) hold items with only a `color` grade and no media or text; each grades
        every layer below it while on screen. Use `adjustment add` for a grade on a range; there is no project-wide
        style setting. Reusable grades are library looks (`library list --kind look`, `library place`, `library add`).
        Brand kit: `library apply BRAND` (no --item) sets brand, restyles brandRoles text.
        `schema get`: the JSON Schema of project.bashcut.json (fields, types, ranges).
        Prefer `media place` and `timeline move` (they use a free or new layer when the range is taken); overlapping
        raw insert/move operations are rejected.
        Edits need --base-rev N from the latest read. One request is one atomic apply call.
        Jobs: `bashcut jobs wait JOB_ID --done --timeout 100` returns when it ends;
        `jobs wait ID1,ID2,…` waits for several at once. Their result is one undoable edit.
        Each call is a turn: batch (`media import FOLDER`; sheets, not `ui frame` one by one; `checkpoint status
        --wait 100`; `context get` on start, not per command). Build a cut (or voiceover lines and graphics) as plan.cut:
        `plan check`, then `plan apply`; transitions go in it too. `plan check --patch P --save` keeps fixes before
        graphics have media.
        `--format text` prints plain results.
        `project format --canvas landscape|portrait|square` changes the canvas (text sizes follow the short side).
        Clips fit inside the frame; a clip's `fill` (setProperties) or `--clips fill` crops to cover; zoom scales from it.
        Projects: `bashcut project create` / `project open` / `project save`; they refuse to drop unsaved work unless
        you pass --save-current or --discard-current. A new project has no default language: pass `--language` from
        the user's prompt or answer. Your terminal stays open when the project changes; read
        `context get` or `timeline get` before your next edit (edits fail until you do). Outside BashCut's terminals the CLI and MCP read the
        token file themselves; edits are attributed to "agent". Exports still need the user's approval.
        """

    /// How agents find and run what installed plugins add. The installed actions themselves are listed in the
    /// session context (`ProjectDocument.pluginActionsText()`) and by `plugins actions`.
    private static let plugins = """
        Plugin actions: installed plugins add actions (Plugins menu, clip and timeline menus, panels). To use one:
        1. `bashcut plugins actions [TEXT] [--plugin ID]` lists each action's id, title, plugin, `when` condition,
           params as JSON Schema, `enabled` (whether it can run with the current selection) and `lastRun`. MCP lists
           at most \(PluginActionTools.budget) actions as their own tools (available and recently run first); search
           here for any other and run it with `plugins run`.
        2. Make it runnable: most actions work on the selection, so `bashcut ui select ITEM_ID` first.
        3. `bashcut plugins run ACTION_ID --params '{"name":value}'` (MCP: `bashcut_plugins_run`, or the per-action
           tool `\(PluginActionTools.prefix)<id>`); omitted params use their defaults. It returns a job ID.
        4. `bashcut jobs status JOB_ID` gives the result: the plugin's message and `data` (for example the ranges it
           removed). The edit is one undo step attributed to the plugin.
        Plugins that provide capabilities (voice, captions, beats, loudness) are used by `voice speak`,
        `captions generate`, `beats detect` and export; `--provider` picks one, `plugins list` shows them.
        Voices: `capabilities get --voices` rows are `kind` preset or clone (the user's saved voices).
        Find more with `plugins search`; installing, trusting and turning plugins on are for the user only. When the
        user is missing plugins, suggest they type `/bc:setup`, which shows one approval for the recommended
        bundle (`plugins bundles`). Never start an install on your own.
        """

    /// Color keys and ranges, from the same table validation uses.
    private static let color: String = {
        let keys = ColorGrade.ranges.map { "\($0.key) \($0.range.lowerBound)…\($0.range.upperBound)" }
        return "Color grades (item, adjustment or look `color`): " + keys.joined(separator: ", ")
            + ", lut (a LUT ID). setProperties replaces the whole `color` object; patchItems merges into it. "
            + text
    }()

    private static let text: String = {
        let presets: String = TextPreset.all.joined(separator: ", ")
        return "Text items take `textPreset` (built-in: \(presets); any other name uses the first's defaults) and "
            + "open `textStyle` fields: size, positionY, positionX, align left|center|right, font, fill, stroke, "
            + "strokeWidth, highlight, lineHeight, tracking, uppercase, background {color, opacity, padding, radius} "
            + "(× font size, not px: radius 0.2), "
            + "shadow {color, opacity, blur, dx, dy}, accentBars [{side left|right|top|bottom, color, opacity, "
            + "thickness, gap (× font size), length (share of the side), radius}], emphasis {line (from the top, "
            + "negative from the bottom), fill, scale, plate {color, opacity, padding, radius}} or false (one line larger "
            + "in its own colour; hook-title emphasises by default), lineFills [colors] (line colours, repeating), "
            + "lines [{font, scale, fill, stroke}] (per line). "
            + "Text templates are library items (`library list --kind text-preset`): pick the look for the video, "
            + "whatever the text is for. wordStyle is highlight|karaoke|reveal "
            + "or {spoken, upcoming, past} looks of {fill, opacity}. Keyframes also animate textStyle.size, positionX, "
            + "positionY, strokeWidth, lineHeight, tracking on text, color.exposure, contrast, saturation, "
            + "lutStrength on clips and adjustment layers and crop.left…bottom, radius on clips."
    }()

    private static let operations = """
        `bashcut timeline apply /absolute/path/ops.json --base-rev N --label "Describe the edit"` reads an array.
        Add `--dry-run` to validate without changing the project; it returns what would change.
        Supported operations:
        {"op":"split","item":"ID","atFrame":30}, {"op":"delete","item":"ID","ripple":true},
        {"op":"trim","item":"ID","edge":"end","toFrame":120,"ripple":true},
        {"op":"move","item":"ID","toTrack":"TRACK_ID","atFrame":0},
        {"op":"reorder","item":"ID","before":"OTHER_ID"}; omit before to move to the end of the main track,
        {"op":"setProperties","item":"ID","patch":{"transform":{"zoom":1.2}}} (replaces each field it names),
        {"op":"patchItems","select":{"trackRole":"captions"},"patch":{"textStyle":{"fill":"#FFD400","size":null}}}
        restyles many items at once: objects merge key by key (null deletes a key); select by track, trackRole,
        trackKind, textPreset or media (all given must match), or list "items":["ID",…],
        framing: setProperties {"reframePreset":"close","transform":{"zoom":1.3,"pan":0,"tilt":0}}; bars of a fit
        picture: {"backdrop":{"kind":"blur"}} (or "color" with "color"),
        {"op":"rippleDeleteRange","from":90,"to":180} cuts a span out of every layer and closes it (a restart):
        clips split or trimmed, captions lose its words, later items and sections move, music beds lose their tail,
        {"op":"setLinkedAudio","video":"VIDEO_ID","audio":"AUDIO_ID"}; omit audio to unlink,
        {"op":"setSpeed","item":"ID","speed":2}; the clip and its linked sound get 2x and half the length, later
        clips on their layers move up; add "keepDuration":true to keep the length (prefer this over a speed patch),
        {"op":"setSpeedCurve","item":"ID","preset":"hero"} or "points":[{"t":0,"speed":1},{"t":0.5,"speed":3},{"t":1,"speed":1}]
        for a speed ramp (t 0…1 along the clip; "points":null removes it); reverse a clip with `clip reverse ID`,
        {"op":"insert","track":"TEXT_TRACK_ID","item":{"id":"new-id","at":0,"dur":90,"text":"Caption"}},
        {"op":"addTrack","track":{"id":"NEW_TRACK_ID","kind":"video","role":"overlay","name":"B-roll 2","items":[]},"atIndex":2}
        (omit atIndex: in front),
        {"op":"moveTrack","track":"TRACK_ID","toIndex":3},
        {"op":"setTrackProperties","track":"TRACK_ID","patch":{"name":"Product shots"}},
        {"op":"setProjectProperties","patch":{"audio":{"targetLUFS":-14,"normalizeEnabled":true}}},
        {"op":"setFormat","width":1920,"height":1080} (canvas; even pixels; pan/tilt scale with it),
        {"op":"deleteTrack","track":"TRACK_ID"},
        {"op":"setProviderPreference","capability":"voice.synthesize","provider":"acme.voice.fast"}.
        {"op":"setBeatGrid","media":"MEDIA_ID","bpm":120,"frames":[0,15,30]}.
        {"op":"setMediaData","media":"MEDIA_ID","patch":{"take":3,"verdict":"keep","reason":"sharp, clean audio"}}
        keeps your fields on a media under data (null removes a key; media list shows them).
        {"op":"upsertSection","id":"section-hook","label":"Hook","atFrame":0},
        {"op":"deleteSection","id":"section-hook"}.
        {"op":"upsertTransition","id":"cut-a-b","kind":"dissolve","from":"CLIP_A","to":"CLIP_B","duration":12,
         "easing":"inOut"} (id optional; easing: linear, the default, in, out, inOut or "cubic-bezier(0.2,0,0,1)";
         kinds dissolve, blink, flash, dip-black, double-exposure, whip|wipe(-right|-up|-down), barn-door, shutter,
         slide(-up), iris, diamond, zoom, crash-zoom|out, spin, roll(-right), swing, arc(-right), infinite-zoom|out,
         screen-in|out, blur, seamless-zoom, glitch, halftone, flicker, color-shift, kaleidoscope, or any with
         "motion":{"incoming":{"opacity":[0,1]}}: zoom, panX|Y,
         rotation, opacity, exposure (EV), scaleX, reveal(FromRight|Top|Bottom), revealCenter, iris, diamond, swing,
         rgbSplit, halftone, blur, blurX|Y, zoomBlur, hue, saturation, kaleidoscope: [from, to] or more),
        {"op":"deleteTransition","id":"cut-a-b"}. Lone text, sticker, overlay: setProperties
        {"enter":{"kind":"iris","duration":12},"exit":{…}}.
        {"op":"insert","track":"ADJUSTMENT_TRACK_ID","item":{"id":"grade-1","at":0,"dur":90,"color":{"saturation":0.8,"lut":"LUT_ID"}}},
        {"op":"addColorLUT","lut":{"id":"look","name":"Look","path":"luts/look.cube","size":33}},
        {"op":"deleteColorLUT","id":"look"}.
        {"op":"roll","item":"ID","edge":"end","toFrame":120},
        {"op":"slip","item":"ID","sourceIn":60}.
        Roll moves a shared cut; slip only the source start.
        atFrame/toFrame: absolute timeline frames; in: a source frame at the media fps.
        Never hand-edit project.bashcut.json while the app is open, never overwrite original footage, and never render with ffmpeg.
        Editing the timeline (apply, cuts, voice, text, color, mix) needs no confirm: work on and use checkpoint request only at
        gates. Search for and download the music, sound effects, images, footage and fonts the edit needs without asking,
        whatever the licence; the user handles rights, so record no license, source or author and list no rights unless
        the user asks. Install the command-line tools you need yourself. Work to the end
        without waiting for the user: decide what the prompt and footage leave open and say what you chose. After one
        round of questions at intake, never end a turn on a question or a request to the user: fix a failed step
        yourself or take the best fallback, finish, and list what waits on the user in the final summary ("ask the
        user" in a skill or hint means that). Install
        a BashCut plugin the edit needs (trusted automatically unless the user turned it off); never clone a voice that
        is not the user's. Reply in the user's language.
        Errors carry data.category, retryable and sometimes remediation.command. Retry only retryable ones, after the
        remediation; never resend invalid_arguments unchanged. stale_revision (-32002)/file_conflict → context get,
        resend with the new rev; busy_dialog → ui dialog, answer it; busy_approval/busy_running → wait;
        capability_missing → data.reason missing (plugins search; the user installs), not_configured (the user turns it
        on; quote detail) or unhealthy (the user fixes detail); go on with what does not need it; unsupported_media →
        this Mac cannot decode the video (AV1, VP9): do not judge its black picture; BashCut converts it itself (media
        import answers proxy.status converting with a job: transcribe meanwhile, wait with jobs status, then read
        frames; unsupported because ffmpeg is missing → install ffmpeg, then media proxy MEDIA);
        audit_missing/recipe_unread/graphics_draft/stage_pending → run remediation.command. recentFailures.repeated ≥ 2: stop repeating it, try
        another way or skip that step, and report it.
        Scope: an edit outside the attached items fails with -32004; never retry or work around it. held: true → the
        user is asked: wait for scope.last.outcome (applied → re-read; rejected → ask; failed stale → re-read, resend if
        still wanted); no held → stop and ask; -32003 while held → wait. agentPermissions in context get (edits,
        autoApprove, scopeGuard, allowAll) is the user's. Library first: library list --kind K before building a style,
        effect, transition, look, sound or sticker. Read a plugin's skill (skills get ID) before using its feature.
        Record stages: run append stage --stage S --status done --evidence "a;b" (skipped: --reason); run checklist and
        context get › workflow.next name the next stage and skill. An agent's final export needs a passing draft audit
        of the current timeline (or the user's G5 approval) and the plan's required stages done or skipped; G2 needs a
        strategy audit and the plan's recipe read.
        """
}
