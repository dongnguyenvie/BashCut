import BashCutProjectFixtures
import Foundation
import Testing

@testable import BashCutProject

@Suite("Effect presets as recipes (#76)")
struct EffectRecipeTests {
    /// A 30 fps project with the 60-frame video clip `c` (1920×1080 source of 600 frames at 30 fps) on the main layer.
    private static func project() throws -> Project {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("clip.mov"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
            "frames": .integer(600), "width": .integer(1920), "height": .integer(1080), "hasAudio": .bool(false),
        ])
        return try Project(name: "Effects", fps: FrameRate(30, 1)).applying(
            .group(label: "Setup", author: .user, ops: [
                .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "m", at: 0, duration: 60, sourceIn: 30)),
            ])
        ).project
    }

    private static func whoosh(_ id: String = "whoosh") -> Media {
        Media(fields: [
            "id": .string(id), "path": .string("sfx/whoosh.wav"), "kind": .string("audio"), "fps": FrameRate(30, 1).json,
            "frames": .integer(15), "hasAudio": .bool(true), TransitionPreset.soundLibraryField: .string("user:whoosh"),
        ])
    }

    private static func recipe(_ steps: [[String: JSONValue]], parameters: [EffectRecipe.Parameter] = []) throws -> EffectRecipe {
        try EffectRecipe(params: EffectRecipe(parameters: parameters, steps: steps).params)
    }

    private static func operation(_ planner: LayerPlanner) -> EditOperation {
        planner.operations.count == 1 ? planner.operations[0] : .group(label: "Effect", author: .user, ops: planner.operations)
    }

    private static func applied(
        _ recipe: EffectRecipe, to project: Project, _ application: EffectApplication = EffectApplication()
    ) throws -> (project: Project, item: Item) {
        let plan = try project.effectRecipePlan(recipe, to: "c", application)
        let result = try project.applying(operation(plan.planner)).project
        let item = try #require(result.tracks.flatMap(\.items).first { $0.id == plan.itemID })
        return (result, item)
    }

    @Test("A recipe checks its steps and parameters; an old patch stays valid and is written back as it was")
    func validation() throws {
        let legacy = ["patch": JSONValue.object(["transform": .object(["zoom": .number(1.3)])])]
        let old = try EffectRecipe(params: legacy)
        #expect(old.isLegacyPatch)
        #expect(old.params == legacy)
        #expect(try old.resolvedSteps() == [.patch(["transform": .object(["zoom": .number(1.3)])])])
        try LibraryItem(id: "p", kind: .effectPreset, name: "P", params: legacy).validate()
        let zoom = EffectRecipe.Parameter("zoom", value: 1.2, minimum: 1, maximum: 2)
        let ramp = try Self.recipe(
            [["op": .string("keyframes"), "keys": .object(["zoom": .array([
                .object(["t": .integer(0), "value": .integer(1), "ease": .string("linear")]),
                .object(["t": .integer(1), "value": .string("$zoom")]),
            ])])]], parameters: [zoom])
        #expect(try EffectRecipe(params: ramp.params) == ramp)
        func step(_ op: String, _ fields: [String: JSONValue] = [:]) -> JSONValue {
            .object(fields.merging(["op": .string(op)]) { $1 })
        }
        let bad: [([String: JSONValue], String)] = [
            ([:], "params.patch"),
            (["steps": .array([])], "params.steps"),
            (["steps": .array([step("explode")])], "op must be one of"),
            (["steps": .array([step("speed", ["speed": .string("$fast")])])], "$fast"),
            (["steps": .array([step("speed", ["speed": .integer(40)])])], "speed"),
            (["steps": .array([step("freeze", ["frame": .number(1.5)])])], "whole number"),
            (["steps": .array([step("keyframes", ["keys": .object(["glow": .array([])])])])], "keys.glow"),
            (["steps": .array([step("motion", ["preset": .string("spin")])])], "preset"),
            (["steps": .array([step("motion", ["focus": .array([.integer(0), .integer(0), .integer(2), .integer(1)])])])], "focus"),
            (["steps": .array([step("text", ["text": .string("Hi"), "textPreset": .string("comic")])])], "textPreset"),
            (["steps": .array([step("patch", ["patch": .object(["dur": .integer(3)])])])], "timing"),
            (["steps": .array([step("sfx", ["sfx": .string("Bad ID")])])], "sfx"),
            (["steps": .array([step("reverse")]), "parameters": .object(["x": .object(["default": .integer(5), "min": .integer(0),
                                                                                      "max": .integer(1)])])], "min ≤ default ≤ max"),
        ]
        for (params, message) in bad {
            let item = LibraryItem(id: "e", kind: .effectPreset, name: "E", params: params)
            #expect(throws: ProjectError.self) { try item.validate() }
            do { try item.validate() } catch { #expect(error.localizedDescription.contains(message)) }
        }
        for item in LibraryBuiltIns.effects { try item.validate() }
        #expect(LibraryBuiltIns.recipes.map(\.id) == ["ken-burns-in", "ken-burns-out", "zoom-punch-in", "speed-ramp", "slow-motion"])
    }

    @Test("Overrides fill parameters within their range; frame values must stay whole")
    func overrides() throws {
        #expect(try EffectRecipe.overrides("zoom=1.5, frames=12") == ["zoom": 1.5, "frames": 12])
        #expect(try EffectRecipe.overrides(#"{"zoom": 2}"#) == ["zoom": 2])
        #expect(throws: ProjectError.self) { try EffectRecipe.overrides("zoom") }
        let punch = try EffectRecipe(params: try #require(LibraryBuiltIns.recipes.first { $0.id == "zoom-punch-in" }).params)
        #expect(try punch.values() == ["zoom": 1.3, "frames": 8])
        let steps = try punch.resolvedSteps(["zoom": 2, "frames": 12])
        guard case .keyframes(let keys) = steps.first else { Issue.record("expected keyframes"); return }
        #expect(keys["zoom"]?.map(\.value) == [2, 1])
        #expect(keys["zoom"]?.map(\.position) == [.frame(0), .frame(12)])
        #expect(throws: ProjectError.self) { try punch.resolvedSteps(["zoom": 9]) }
        #expect(throws: ProjectError.self) { try punch.resolvedSteps(["strength": 1]) }
        #expect(throws: ProjectError.self) { try punch.resolvedSteps(["frames": 2.5]) }
        // A parameter can feed any number, and text is never read as a reference.
        let project = try Self.project()
        let text = try Self.recipe([["op": .string("text"), "text": .string("$zoom"), "duration": .string("$frames")]],
                                   parameters: [.init("frames", value: 10, minimum: 1, maximum: 60)])
        let placed = try Self.applied(text, to: project).project
        let title = try #require(placed.tracks.flatMap(\.items).first { $0[EffectRecipe.textField] != nil })
        #expect(title.text == "$zoom")
        #expect(title.duration == 10)
    }

    @Test("Motion steps: a preset, keyframes at positions that scale, and focus; other keys stay")
    func motion() throws {
        var project = try Self.project()
        project = try project.applying(.setProperties(item: "c", patch: ["keyframes": .object([
            "pan": .array([.object(["frame": .integer(0), "value": .integer(40)])]),
        ])])).project
        let preset = try Self.applied(try Self.recipe([["op": .string("motion"), "preset": .string("zoom-in")]]), to: project).item
        #expect(preset.motion?.keys["zoom"]?.map(\.frame) == [0, 59])
        #expect(preset.motion?.keys["pan"]?.first?.value == 40)
        let keyframes = try Self.recipe([["op": .string("keyframes"), "keys": .object([
            "zoom": .array([
                .object(["t": .integer(0), "value": .integer(1)]), .object(["t": .number(0.5), "value": .number(1.5)]),
                .object(["frame": .integer(-1), "value": .integer(1)]),
            ]),
            "opacity": .array([.object(["frame": .integer(10), "value": .number(0.5), "ease": .string("hold")])]),
        ])]])
        let keyed = try Self.applied(keyframes, to: project).item
        #expect(keyed.motion?.keys["zoom"]?.map(\.frame) == [0, 30, 59])
        #expect(keyed.motion?.keys["opacity"]?.first?.ease == .hold)
        #expect(keyed.motion?.keys["pan"] != nil)
        let focus = try Self.recipe([["op": .string("motion"), "focus": .array([.number(0.25), .number(0.25), .number(0.5),
                                                                                .number(0.5)])]])
        let framed = try Self.applied(focus, to: project).item
        let expected = try MotionFocus.framing(
            MotionFocus.Region(x: 480, y: 270, width: 960, height: 540), source: (1920, 1080),
            canvas: (Double(project.width), Double(project.height)), fill: project.fills(framed))
        #expect(framed.motion?.keys["zoom"]?.first?.value == expected.zoom)
        #expect(framed.motion?.keys["pan"]?.first?.value == expected.pan)
        #expect(framed.motion?.keys["tilt"]?.count == 1)
    }

    @Test("Speed, speed ramp, freeze and patch steps reuse the clip edits")
    func timing() throws {
        let project = try Self.project()
        let fast = try Self.applied(try Self.recipe([["op": .string("speed"), "speed": .integer(2)]]), to: project).item
        #expect(fast.speed == 2)
        #expect(fast.duration == 30)
        let ramp = try Self.applied(try Self.recipe([["op": .string("speedCurve"), "preset": .string("montage"),
                                                      "keepDuration": .bool(true)]]), to: project).item
        #expect(ramp.speedCurve == SpeedCurve.preset("montage"))
        #expect(ramp.duration == 60)
        let frozen = try Self.applied(try Self.recipe([["op": .string("freeze"), "t": .number(0.5)]]), to: project).item
        #expect(frozen["freezeFrame"] == .integer(30 + 30))
        let patched = try Self.applied(try Self.recipe([["op": .string("patch"), "patch": .object(["opacity": .number(0.5)])]]),
                                       to: project).item
        #expect(patched["opacity"] == .number(0.5))
        // Steps run in order: keys placed after a speed change scale to the new length.
        let both = try Self.recipe([
            ["op": .string("speed"), "speed": .integer(2)],
            ["op": .string("keyframes"), "keys": .object(["zoom": .array([.object(["t": .integer(1), "value": .integer(2)])])])],
        ])
        #expect(try Self.applied(both, to: project).item.motion?.keys["zoom"]?.first?.frame == 29)
    }

    @Test("Reverse asks for its copy, then points the clip at it; a reversed clip stays reversed")
    func reverse() throws {
        let project = try Self.project()
        let recipe = try Self.recipe([["op": .string("reverse")]])
        var need: EffectReverseNeeded?
        do { _ = try project.effectRecipePlan(recipe, to: "c") } catch let error as EffectReverseNeeded { need = error }
        let request = try #require(need)
        #expect(request.sourceIn == 30)
        #expect(request.frames == 60)
        #expect(request.path == "reversed/clip-reversed-30-60.mov")
        var copy = project.media[0]
        copy["id"] = .string("m-rev")
        copy["path"] = .string(request.path)
        copy["frames"] = .integer(60)
        var application = EffectApplication()
        application.reversed[request.path] = copy
        let (reversed, item) = try Self.applied(recipe, to: project, application)
        #expect(item.mediaID == "m-rev")
        #expect(item.sourceIn == 0)
        #expect(item["reversed"]?.object["media"] == .string("m"))
        let again = try reversed.effectRecipePlan(recipe, to: "c")
        #expect(again.planner.operations.isEmpty)
    }

    @Test("Sound and text steps place tagged items, add the SFX layer when missing, and are replaced on re-apply")
    func soundAndText() throws {
        let project = try Self.project().applying(.deleteTrack(track: "a4")).project
        #expect(project.track(role: TrackRole.sfx) == nil)
        let recipe = try Self.recipe([
            ["op": .string("sfx"), "sfx": .string("user:whoosh"), "frame": .integer(5), "volumeDb": .integer(-6)],
            ["op": .string("text"), "text": .string("WOW"), "textPreset": .string("keyword-sticker"), "t": .number(0.5)],
        ])
        var application = EffectApplication()
        application.sounds["user:whoosh"] = Self.whoosh()
        #expect(throws: ProjectError.self) { try project.effectRecipePlan(recipe, to: "c") }
        let once = try Self.applied(recipe, to: project, application).project
        let sfx = try #require(once.track(role: TrackRole.sfx))
        #expect(sfx.items.map(\.at) == [5])
        #expect(sfx.items.first?[EffectRecipe.soundField] == .string("c"))
        #expect(sfx.items.first?["volumeDb"] == .number(-6))
        let text = once.tracks.flatMap(\.items).filter { $0[EffectRecipe.textField] == .string("c") }
        #expect(text.map(\.at) == [30])
        #expect(text.map(\.duration) == [30])
        let twice = try Self.applied(recipe, to: once, application).project
        #expect(twice.tracks.filter { $0.role == TrackRole.sfx }.count == 1)
        #expect(twice.tracks.flatMap(\.items).filter { $0[EffectRecipe.soundField] != nil }.count == 1)
        #expect(twice.tracks.flatMap(\.items).filter { $0[EffectRecipe.textField] != nil }.count == 1)
        #expect(twice.media.filter { $0.id == "whoosh" }.count == 1)
    }

    @Test("The whole recipe is one undo step, and undo restores the project")
    func oneUndoStep() throws {
        let project = try Self.project().applying(.deleteTrack(track: "a4")).project
        let recipe = try Self.recipe([
            ["op": .string("speed"), "speed": .integer(2)],
            ["op": .string("motion"), "preset": .string("zoom-in")],
            ["op": .string("patch"), "patch": .object(["opacity": .number(0.8)])],
            ["op": .string("sfx"), "frame": .integer(0)],
            ["op": .string("text"), "text": .string("Go")],
        ])
        var application = EffectApplication(range: 10..<50)
        application.sounds[EffectRecipe.ownSound] = Self.whoosh()
        let plan = try project.effectRecipePlan(recipe, to: "c", application)
        let operation = Self.operation(plan.planner)
        guard case .group = operation else { Issue.record("expected one group"); return }
        let round = try ProjectFixtures.undoRedo(operation, on: project)
        #expect(round.matches(original: project))
        #expect(round.applied.tracks.flatMap(\.items).contains { $0.id == plan.itemID && $0.speed == 2 })
    }

    @Test("A range splits the clip in the same edit and changes only that part")
    func range() throws {
        let project = try Self.project()
        var application = EffectApplication(range: 15..<45)
        application.splitID = "fx"
        let recipe = try Self.recipe([["op": .string("speed"), "speed": .number(0.5)]])
        let (result, item) = try Self.applied(recipe, to: project, application)
        #expect(item.id == "c-fx-a")
        #expect(item.at == 15)
        #expect(item.duration == 60)
        let main = try #require(result.track(id: "v1")).items.sorted { $0.at < $1.at }
        #expect(main.map(\.id) == ["c", "c-fx-a", "c-fx-b"])
        #expect(main.map(\.speed) == [1, 0.5, 1])
        #expect(main.map(\.duration) == [15, 60, 15])
        let start = try Self.applied(recipe, to: project, EffectApplication(range: 0..<20)).item
        #expect(start.id == "c")
        #expect(start.duration == 40)
        #expect(throws: ProjectError.self) { try project.effectRecipePlan(recipe, to: "c", EffectApplication(range: 50..<70)) }
    }

    @Test("Save selection as an effect keeps reverse, speed, framing, keyframes and the sound, and applies back")
    func saveSelectionRoundTrip() throws {
        var clip = Item(id: "c", media: "m", at: 0, duration: 60)
        clip["speed"] = .number(1.5)
        clip["transform"] = .object(["zoom": .number(1.3)])
        clip["reversed"] = .object(["media": .string("m"), "in": .integer(0), "frames": .integer(90)])
        clip["keyframes"] = ItemMotion(keys: ["zoom": [.init(frame: 0, value: 1, ease: .linear), .init(frame: 59, value: 1.2)],
                                              "opacity": [.init(frame: 17, value: 0.5)]]).json
        var sound = Item(media: "whoosh", at: 4, duration: 15)
        sound["volumeDb"] = .integer(-3)
        let params = try LibrarySelection.params(.effectPreset, item: clip, sound: Self.whoosh(), soundItem: sound)
        let item = LibraryItem(id: "saved", kind: .effectPreset, name: "Saved", params: params)
        try item.validate()
        let recipe = try EffectRecipe(params: params)
        #expect(try recipe.resolvedSteps().map { step -> String in
            switch step {
            case .reverse: "reverse"
            case .speed: "speed"
            case .patch: "patch"
            case .keyframes: "keyframes"
            case .sfx(let source, let at, let volume): "sfx \(source ?? "") \(at) \(volume ?? 0)"
            default: "other"
            }
        } == ["reverse", "speed", "patch", "keyframes", "sfx user:whoosh frame(4) -3.0"])
        // Applied to a clip, the framing and keys come back on its new length.
        let project = try Self.project()
        let noReverse = EffectRecipe(steps: recipe.steps.filter { $0["op"] != .string("reverse") && $0["op"] != .string("sfx") })
        let applied = try Self.applied(noReverse, to: project).item
        #expect(applied.speed == 1.5)
        #expect(applied.duration == 40)
        #expect(applied["transform"] == .object(["zoom": .number(1.3)]))
        #expect(applied.motion?.keys["zoom"]?.map(\.frame) == [0, 39])
        #expect(applied.motion?.keys["zoom"]?.first?.ease == .linear)
        #expect(applied.motion?.keys["opacity"]?.map(\.frame) == [11])
        // On a clip of the same length the keys land on the same frames.
        let same = try LibrarySelection.params(.effectPreset, item: Item(id: "x", media: "m", at: 0, duration: 60).merging(clip))
        let keys = try EffectRecipe(params: same).resolvedSteps().compactMap { step -> [String: [EffectRecipe.Key]]? in
            if case .keyframes(let keys) = step { return keys }
            return nil
        }.first
        #expect(keys?["opacity"]?.first?.position.frame(length: 60) == 17)
        #expect(throws: ProjectError.self) { try LibrarySelection.params(.effectPreset, item: Item(at: 0, duration: 30)) }
    }
}

private extension Item {
    func merging(_ other: Item) -> Item {
        var copy = self
        for key in ["transform", "keyframes"] { copy[key] = other[key] }
        return copy
    }
}
