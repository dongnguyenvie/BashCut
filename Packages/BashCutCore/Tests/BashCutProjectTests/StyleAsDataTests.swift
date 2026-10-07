import Foundation
import Testing

@testable import BashCutProject

/// Transitions, easing and style keyframes as data (flexibility audit C5, C6, C13).
struct StyleAsDataTests {
    /// Two adjacent clips a (0–60) and b (60–120) on v1 at 30 fps.
    func project() throws -> Project {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("a.mov"), "fps": FrameRate(30, 1).json, "frames": .integer(300),
        ])
        return try Project(name: "Data", fps: FrameRate(30, 1)).applying(.group(label: "clips", author: .user, ops: [
            .addMedia(media),
            .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 60)),
            .insert(track: "v1", item: Item(id: "b", media: "m", at: 60, duration: 60, sourceIn: 60)),
        ])).project
    }

    @Test("One ease type: the named curves and cubic-bezier, for keyframes and transitions")
    func ease() throws {
        let bezier = try #require(ItemMotion.Ease(rawValue: "cubic-bezier(0.42, 0, 0.58, 1)"))
        #expect(bezier.rawValue == "cubic-bezier(0.42,0,0.58,1)")
        #expect(ItemMotion.Ease(rawValue: bezier.rawValue) == bezier)
        #expect(abs(bezier.apply(0.5) - 0.5) < 1e-4 && bezier.apply(0) == 0 && abs(bezier.apply(1) - 1) < 1e-6)
        #expect(bezier.apply(0.25) < 0.25)
        // A linear bezier is the straight line.
        let line = try #require(ItemMotion.Ease(rawValue: "cubic-bezier(0.25,0.25,0.75,0.75)"))
        #expect(abs(line.apply(0.3) - 0.3) < 1e-4)
        for bad in ["cubic-bezier(1.5,0,0,1)", "cubic-bezier(0,0,1)", "bounce", "cubic-bezier(a,0,0,1)"] {
            #expect(ItemMotion.Ease(rawValue: bad) == nil)
        }
        #expect(TimelineTransition.isEasing("cubic-bezier(0.2,0,0,1)") && !TimelineTransition.isEasing("hold"))
        #expect(abs(TimelineTransition.eased(0.5, easing: "cubic-bezier(0.42,0,0.58,1)") - 0.5) < 1e-4)
        let motion = try ItemMotion(json: .object(["zoom": .array([
            .object(["frame": .integer(0), "value": .number(1), "ease": .string("cubic-bezier(0.42,0,0.58,1)")]),
            .object(["frame": .integer(10), "value": .number(2)]),
        ])]))
        #expect(motion.json.object["zoom"]?.array.first?.object["ease"] == .string("cubic-bezier(0.42,0,0.58,1)"))
        let edited = try project().applying(.upsertTransition(
            id: "cut", kind: "dissolve", from: "a", to: "b", duration: 12, easing: "cubic-bezier(0.2,0,0,1)")).project
        #expect(edited.transitions.first?.easing == "cubic-bezier(0.2,0,0,1)")
        try edited.validate()
    }

    @Test("Built-in kinds are motion rows; any kind with motion renders, a new kind without one is refused")
    func transitions() throws {
        let zoom = try #require(TransitionMotion.builtIns["zoom"])
        #expect(zoom.value("zoom", incoming: true, at: 0) == 1.25 && zoom.value("zoom", incoming: true, at: 1) == 1)
        #expect(zoom.value("opacity", incoming: false, at: 0.5) == nil)
        let blink = try #require(TransitionMotion.builtIns["blink"])
        #expect(blink.value("exposure", incoming: false, at: 0.5) == 4)
        #expect(Set(TransitionMotion.builtIns.keys) == Set(TimelineTransition.renderedKinds))

        let push: JSONValue = .object([
            "outgoing": .object(["panY": .array([.number(0), .number(1)])]),
            "incoming": .object(["panY": .array([.number(-1), .number(0)]), "opacity": .array([.number(0), .number(1)])]),
        ])
        var project = try project()
        #expect(throws: ProjectError.self) {
            try project.applying(.upsertTransition(id: "cut", kind: "push-up", from: "a", to: "b", duration: 12))
        }
        project = try project.applying(
            .upsertTransition(id: "cut", kind: "push-up", from: "a", to: "b", duration: 12, motion: push)).project
        let transition = try #require(project.transitions.first)
        #expect(transition.motion.value("panY", incoming: true, at: 0.5) == -0.5)
        try project.validate()
        let codec = try EditOperation(json: EditOperation.upsertTransition(
            id: "cut", kind: "push-up", from: "a", to: "b", duration: 12, motion: push).json)
        if case .upsertTransition(_, _, _, _, _, _, let motion) = codec { #expect(motion == push) } else { Issue.record("codec") }
        // Replacing it with a built-in kind and no motion drops the motion.
        project = try project.applying(.upsertTransition(id: "cut", kind: "wipe", from: "a", to: "b", duration: 12)).project
        #expect(project.transitions.first?["motion"] == nil)
        for bad: JSONValue in [
            .object(["incoming": .object(["spin": .array([.number(0), .number(1)])])]),
            .object(["incoming": .object(["opacity": .array([.number(0)])])]),
            .object(["incoming": .object(["opacity": .array([.number(0), .number(2)])])]),
            .object(["sideways": .object([:])]),
        ] {
            #expect(throws: ProjectError.self) { try TransitionMotion(json: bad) }
        }
        let preset = try TransitionPreset(params: ["kind": .string("push-up"), "motion": push])
        #expect(preset.params["motion"] == push)
        #expect(throws: ProjectError.self) { try project.transitionPresetPlan(TransitionPreset(kind: "push-up"), at: "a") }
        _ = try project.transitionPresetPlan(preset, at: "a")
    }

    @Test("Keyframes animate numeric textStyle fields on text and color fields on clips and adjustments")
    func styleKeys() throws {
        #expect(ItemMotion.properties(onTrackKind: TrackKind.text).contains("textStyle.size"))
        #expect(!ItemMotion.properties(onTrackKind: TrackKind.text).contains("color.exposure"))
        #expect(ItemMotion.properties(onTrackKind: TrackKind.video).contains("color.exposure"))
        #expect(ItemMotion.properties(onTrackKind: TrackKind.adjustment) == ["color.contrast", "color.exposure",
                                                                            "color.lutStrength", "color.saturation"])
        let motion = try ItemMotion(json: .object([
            "textStyle.size": .array([
                .object(["frame": .integer(0), "value": .number(0.05), "ease": .string("linear")]),
                .object(["frame": .integer(10), "value": .number(0.1)]),
            ]),
            "zoom": .array([.object(["frame": .integer(0), "value": .number(1)])]),
        ]))
        #expect(motion.style?.keys.keys.sorted() == ["textStyle.size"] && motion.picture?.keys.keys.sorted() == ["zoom"])
        let styled = motion.styled(["textStyle": .object(["fill": .string("#FFFFFF")])], at: 5)
        #expect(styled["textStyle"]?.object["size"] == .number(0.075) && styled["textStyle"]?.object["fill"] == .string("#FFFFFF"))
        #expect(throws: ProjectError.self) {
            try ItemMotion(json: .object(["textStyle.size": .array([.object(["frame": .integer(0), "value": .number(3)])])]))
        }
        #expect(throws: ProjectError.self) {
            try ItemMotion(json: .object(["textStyle.font": .array([.object(["frame": .integer(0), "value": .number(1)])])]))
        }
    }
}
