import BashCutProject
import Foundation

extension CommandCatalog {
    /// Instructions given to terminal agents and model APIs, rendered from the command specs.
    public static let instructions: String = {
        let commands = specs.map { spec in
            let note: String
            switch spec.execution {
            case .immediate: note = ""
            case .job: note = " Runs as a background job and returns a job ID."
            case .approval: note = " The app asks the user before running it."
            }
            return "- `\(spec.usage)`: \(spec.summary)\(note)"
        }
        return ([preamble, color, plugins, "Commands (MCP tool `bashcut_<group>_<command>` takes the same parameters):"]
            + commands + [operations]).joined(separator: "\n")
    }()

    private static let preamble = """
        You are inside BashCut, a native video editor. Prefer the bashcut_* MCP tools; the bashcut CLI on PATH is the fallback.
        Read `bashcut context get` and `bashcut timeline get` before editing. Track IDs and roles are dynamic:
        always take them from `bashcut timeline get`, never assume IDs such as v1 or t1.
        Layers: tracks list visual layers back to front, then audio layers, which are mixed. There is exactly one
        main video layer. Items never overlap on one layer, audio media never goes on a visual layer.
        Adjustment layers (kind adjustment) hold items with only a `color` grade and no media or text; each grades
        every layer below it while on screen. Use `adjustment add` for a grade on a range and `style apply` for a
        whole-video style kit; there is no project-wide style setting. Save reusable grades with `looks save` and
        recipes with `style save`; `timeline get` lists luts, looks and styleKits (built-in and custom).
        `schema get` returns the JSON Schema of project.bashcut.json with every field, type and range.
        Prefer `media place` and `timeline move`, which put content on a free or new layer when the range is taken;
        raw insert/move operations that overlap are rejected.
        Edits need --base-rev N from the latest read. One request is one atomic apply call.
        On staleRevision, re-read and retry. Changes appear in the UI and can be undone.
        Job commands return a job ID; poll `bashcut jobs status JOB_ID`. Their result is one undoable edit.
        Installing plugins is user-only. Add `--format text` to print text results without JSON quoting.
        Projects: `bashcut project create` / `project open` / `project save`; they refuse to drop unsaved work unless
        you pass --save-current or --discard-current. Outside BashCut's terminals the CLI and MCP read the
        automation token file automatically; edits are attributed to "agent". Exports still need the user's approval.
        """

    /// How agents find and run what installed plugins add. The installed actions themselves are listed in the
    /// session context (`ProjectDocument.pluginActionsText()`) and by `plugins actions`.
    private static let plugins = """
        Plugin actions: installed plugins add actions (Plugins menu, clip and timeline menus, panels). To use one:
        1. `bashcut plugins actions` lists each action's id, title, plugin, `when` condition, params as JSON Schema
           and `enabled` (whether it can run with the current selection).
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
            + ", lut (a LUT ID). setProperties replaces the whole `color` object: send every key you want to keep."
            + " Text items take `textPreset` (" + TextPreset.all.joined(separator: ", ") + ")."
    }()

    private static let operations = """
        `bashcut timeline apply /absolute/path/ops.json --base-rev N --label "Describe the edit"` reads an array of objects.
        Supported operations:
        {"op":"split","item":"ID","atFrame":30}, {"op":"delete","item":"ID","ripple":true},
        {"op":"trim","item":"ID","edge":"end","toFrame":120,"ripple":true},
        {"op":"move","item":"ID","toTrack":"TRACK_ID","atFrame":0},
        {"op":"reorder","item":"ID","before":"OTHER_ID"}; omit before to move to the end of the main track,
        {"op":"setProperties","item":"ID","patch":{"transform":{"zoom":1.2}}},
        Cycle or choose framing with setProperties patches such as
        {"op":"setProperties","item":"ID","patch":{"reframePreset":"close","transform":{"zoom":1.3,"pan":0,"tilt":0}}},
        {"op":"setLinkedAudio","video":"VIDEO_ID","audio":"AUDIO_ID"}; omit audio to unlink,
        {"op":"setSpeed","item":"ID","speed":2}; the clip and its linked sound get 2x and half the length, later
        clips on their layers move up; add "keepDuration":true to keep the length (prefer this over a speed patch),
        {"op":"insert","track":"TEXT_TRACK_ID","item":{"id":"new-id","at":0,"dur":90,"text":"Caption"}},
        {"op":"addTrack","track":{"id":"NEW_TRACK_ID","kind":"video","role":"overlay","name":"B-roll 2","items":[]},"atIndex":2},
        {"op":"moveTrack","track":"TRACK_ID","toIndex":3},
        {"op":"setTrackProperties","track":"TRACK_ID","patch":{"name":"Product shots"}},
        {"op":"setProjectProperties","patch":{"audio":{"targetLUFS":-14,"normalizeEnabled":true}}},
        {"op":"deleteTrack","track":"TRACK_ID"},
        {"op":"setProviderPreference","capability":"voice.synthesize","provider":"acme.voice.fast"}.
        {"op":"setBeatGrid","media":"MEDIA_ID","bpm":120,"frames":[0,15,30]}.
        {"op":"upsertSection","id":"section-hook","label":"Hook","atFrame":0},
        {"op":"deleteSection","id":"section-hook"}.
        {"op":"upsertTransition","id":"cut-a-b","kind":"dissolve","from":"CLIP_A","to":"CLIP_B","duration":12},
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
        """
}
