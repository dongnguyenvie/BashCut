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
        "agent.detach", "app.update-check", "chat.status", "chat.send", "chat.attach", "chat.detach", "chat.stop",
        "chat.commands", "chat.command", "chat.reset", "chat.transcript", "doctor.run", "knowledge.approve",
        "knowledge.reject", "knowledge.remove-lesson", "skills.enable", "skills.disable", "skills.remove",
        // Inspector › Speed; agents use the setSpeed and setSpeedCurve ops (D10).
        "clip.speed", "clip.speed-curve",
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
            + "COMMAND` or the MCP tool description gives the full description, parameters and result fields; (job) "
            + "returns a job ID):"
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
        picture at a frame to a PNG and returns its path; read that image.
        Layers: tracks list visual layers back to front, then audio layers, which are mixed. There is exactly one
        main video layer. Items never overlap on one layer, audio media never goes on a visual layer.
        Adjustment layers (kind adjustment) hold items with only a `color` grade and no media or text; each grades
        every layer below it while on screen. Use `adjustment add` for a grade on a range; there is no project-wide
        style setting. Reusable grades are library looks (`library list --kind look`, `library place`, `library add`).
        `schema get` returns the JSON Schema of project.bashcut.json with every field, type and range.
        Prefer `media place` and `timeline move`, which put content on a free or new layer when the range is taken;
        raw insert/move operations that overlap are rejected.
        Edits need --base-rev N from the latest read. One request is one atomic apply call.
        On staleRevision, re-read and retry. Changes appear in the UI and can be undone.
        Job commands return a job ID; `bashcut jobs wait JOB_ID` returns when it moves on (repeat until it ends).
        Their result is one undoable edit.
        Installing plugins is user-only. Add `--format text` to print text results without JSON quoting.
        Change the canvas of the open project with `bashcut project format --canvas landscape` (portrait, landscape,
        square); text sizes follow the short side, so titles keep their look. New projects fit each clip inside the
        frame (bars where its shape differs; `--clips fill` crops to cover instead); a clip's `fill` (setProperties)
        overrides that, and transform zoom scales from it.
        Projects: `bashcut project create` / `project open` / `project save`; they refuse to drop unsaved work unless
        you pass --save-current or --discard-current. Your terminal stays open when the project changes; read
        `context get` or `timeline get` before your next edit (edits fail until you do). Outside BashCut's terminals the CLI and MCP read the
        automation token file automatically; edits are attributed to "agent". Exports still need the user's approval.
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
        Find more with `plugins search`; installing, trusting and turning plugins on are for the user only.
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
            + "strokeWidth, highlight, lineHeight, tracking, uppercase, background {color, opacity, padding, radius}, "
            + "shadow {color, opacity, blur, dx, dy}, accentBars [{side left|right|top|bottom, color, opacity, "
            + "thickness, gap (× font size), length (share of the side), radius}]. wordStyle is highlight|karaoke|reveal "
            + "or {spoken, upcoming, past} looks of {fill, opacity}. Keyframes also animate textStyle.size, positionX, "
            + "positionY, strokeWidth, lineHeight, tracking on text and color.exposure, contrast, saturation, "
            + "lutStrength on clips and adjustment layers."
    }()

    private static let operations = """
        `bashcut timeline apply /absolute/path/ops.json --base-rev N --label "Describe the edit"` reads an array of objects.
        Add `--dry-run` to validate without changing the project. It returns the current rev, projectedRev,
        changedItems/changedTracks, addedTracks/removedTracks and the predicted duration in frames.
        Supported operations:
        {"op":"split","item":"ID","atFrame":30}, {"op":"delete","item":"ID","ripple":true},
        {"op":"trim","item":"ID","edge":"end","toFrame":120,"ripple":true},
        {"op":"move","item":"ID","toTrack":"TRACK_ID","atFrame":0},
        {"op":"reorder","item":"ID","before":"OTHER_ID"}; omit before to move to the end of the main track,
        {"op":"setProperties","item":"ID","patch":{"transform":{"zoom":1.2}}} (replaces each field it names),
        {"op":"patchItems","select":{"trackRole":"captions"},"patch":{"textStyle":{"fill":"#FFD400","size":null}}}
        restyles many items at once: objects merge key by key (null deletes a key); select by track, trackRole,
        trackKind, textPreset or media (all given must match), or list "items":["ID",…],
        Cycle or choose framing with setProperties patches such as
        {"op":"setProperties","item":"ID","patch":{"reframePreset":"close","transform":{"zoom":1.3,"pan":0,"tilt":0}}},
        {"op":"setLinkedAudio","video":"VIDEO_ID","audio":"AUDIO_ID"}; omit audio to unlink,
        {"op":"setSpeed","item":"ID","speed":2}; the clip and its linked sound get 2x and half the length, later
        clips on their layers move up; add "keepDuration":true to keep the length (prefer this over a speed patch),
        {"op":"setSpeedCurve","item":"ID","preset":"hero"} or "points":[{"t":0,"speed":1},{"t":0.5,"speed":3},{"t":1,"speed":1}]
        for a speed ramp (t 0…1 along the clip; "points":null removes it); reverse a clip with `clip reverse ID`,
        {"op":"insert","track":"TEXT_TRACK_ID","item":{"id":"new-id","at":0,"dur":90,"text":"Caption"}},
        {"op":"addTrack","track":{"id":"NEW_TRACK_ID","kind":"video","role":"overlay","name":"B-roll 2","items":[]},"atIndex":2},
        {"op":"moveTrack","track":"TRACK_ID","toIndex":3},
        {"op":"setTrackProperties","track":"TRACK_ID","patch":{"name":"Product shots"}},
        {"op":"setProjectProperties","patch":{"audio":{"targetLUFS":-14,"normalizeEnabled":true}}},
        {"op":"setFormat","width":1920,"height":1080} (canvas; even pixels; pan/tilt scale with it),
        {"op":"deleteTrack","track":"TRACK_ID"},
        {"op":"setProviderPreference","capability":"voice.synthesize","provider":"acme.voice.fast"}.
        {"op":"setBeatGrid","media":"MEDIA_ID","bpm":120,"frames":[0,15,30]}.
        {"op":"upsertSection","id":"section-hook","label":"Hook","atFrame":0},
        {"op":"deleteSection","id":"section-hook"}.
        {"op":"upsertTransition","id":"cut-a-b","kind":"dissolve","from":"CLIP_A","to":"CLIP_B","duration":12,
         "easing":"inOut"} (easing: linear, the default, in, out, inOut or "cubic-bezier(0.2,0,0,1)"; kinds dissolve,
         whip, blink, zoom, spin, shutter, wipe, or any name with "motion":{"outgoing":{"zoom":[1,1.2],"opacity":[1,0]},
         "incoming":{"panX":[0.3,0],"opacity":[0,1]}}: zoom, panX/panY (share of the frame), rotation (deg), opacity,
         exposure (EV), scaleX, reveal (wipe from the left), each [from, to] or more points),
        {"op":"deleteTransition","id":"cut-a-b"}.
        {"op":"insert","track":"ADJUSTMENT_TRACK_ID","item":{"id":"grade-1","at":0,"dur":90,"color":{"saturation":0.8,"lut":"LUT_ID"}}},
        {"op":"addColorLUT","lut":{"id":"look","name":"Look","path":"luts/look.cube","size":33}},
        {"op":"deleteColorLUT","id":"look"}.
        {"op":"roll","item":"ID","edge":"end","toFrame":120},
        {"op":"slip","item":"ID","sourceIn":60}.
        Roll moves a shared cut without changing total duration. Slip changes only the source start.
        atFrame/toFrame are absolute integer timeline frames. in is an integer source frame at the media fps.
        Never hand-edit project.bashcut.json while the app is open, never overwrite original footage, and never render with ffmpeg.
        Ask the user before downloading media or installing tools. Reply in the user's language.
        Errors carry data.category, retryable and sometimes remediation.command (the read that explains them):
        stale_revision/file_conflict → context get and resend with the new rev; busy_* → wait or answer the dialog;
        capability_missing → capabilities get, then ask the user to install or turn on a provider; unsupported_media →
        this Mac cannot decode the file: ask the user to convert it to H.264 or HEVC.
        """
}
