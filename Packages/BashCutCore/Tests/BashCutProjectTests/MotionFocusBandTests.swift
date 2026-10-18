import Foundation
import Testing

@testable import BashCutProject

/// Focus framed into the visible band of a split layout (`clip motion --focus --within`) and plan.cut `focus`,
/// `focusTo` and `focusKeys` resolved on apply.
struct MotionFocusBandTests {
    let plan = PlanCutTests()

    /// Where `rect` (source pixels) lands on the canvas with `framing`.
    func landing(
        _ rect: MotionFocus.Region, _ framing: MotionFocus.Framing, source: (Double, Double) = (1920, 1080),
        canvas: (Double, Double) = (1080, 1920), fill: Bool = false
    ) -> MotionFocus.Region {
        let base = fill ? max(canvas.0 / source.0, canvas.1 / source.1) : min(canvas.0 / source.0, canvas.1 / source.1)
        let scale = base * framing.zoom
        let left = (canvas.0 - source.0 * scale) / 2 + framing.pan, top = (canvas.1 - source.1 * scale) / 2 - framing.tilt
        return MotionFocus.Region(x: left + rect.x * scale, y: top + rect.y * scale, width: rect.width * scale, height: rect.height * scale)
    }

    func inside(_ rect: MotionFocus.Region, _ band: MotionFocus.Region, slack: Double = 1) -> Bool {
        rect.x >= band.x - slack && rect.y >= band.y - slack && rect.x + rect.width <= band.x + band.width + slack
            && rect.y + rect.height <= band.y + band.height + slack
    }

    /// A 9:16 project with a portrait camera across the top half on the overlay layer, as in a screen tutorial.
    func splitProject(cameraFrames: Int = 600) -> Project {
        var project = plan.project()
        project.media.append(Media(fields: [
            "id": .string("cam"), "path": .string("cam.mp4"), "kind": .string("video"), "fps": FrameRate(30, 1).json,
            "frames": .integer(600), "width": .integer(1080), "height": .integer(1920),
        ]))
        var camera = Item(id: "cam-1", media: "cam", at: 0, duration: cameraFrames)
        camera["transform"] = .object(["zoom": .number(1.15), "tilt": .number(350)])
        camera["crop"] = .object(["bottom": .number(0.342)])
        let overlay = project.tracks.firstIndex { $0.role == TrackRole.overlay }!
        project.tracks[overlay].items = [camera]
        return project
    }

    @Test("Focus within the bottom half fits the panel to the band and keeps the picture's edges out of it")
    func framesIntoBand() throws {
        let band = MotionFocus.Region(x: 0, y: 960, width: 1080, height: 960)
        // The top-right quarter of a 1920×1080 screen: fitted to the band's width, its top edge on the band's top.
        let panel = MotionFocus.Region(x: 960, y: 0, width: 960, height: 540)
        let framing = try MotionFocus.framing(panel, source: (1920, 1080), canvas: (1080, 1920), fill: false, within: band)
        #expect(framing.zoom == 2)
        #expect(framing.pan == -540)
        #expect(framing.tilt == -607.5)
        let landed = landing(panel, framing)
        #expect(inside(landed, band))
        #expect(abs(landed.y - 960) < 0.5 && abs(landed.width - 1080) < 0.5)
        // A panel in the middle is centred in the band: the hand formula tilt = (cy − h/2)·scale − 480.
        let middle = MotionFocus.Region(x: 660, y: 390, width: 600, height: 300)
        let centred = try MotionFocus.framing(middle, source: (1920, 1080), canvas: (1080, 1920), fill: false, within: band)
        let scale = 0.5625 * centred.zoom
        #expect(abs(centred.tilt - ((540 - 540) * scale - 480)) < 0.1)
        #expect(abs(centred.pan - (960 - 960) * scale) < 0.1)
        #expect(inside(landing(middle, centred), band))
        // Without a band the result is what it was: centred in the whole frame.
        let whole = try MotionFocus.framing(middle, source: (1920, 1080), canvas: (1080, 1920), fill: false)
        let full = try MotionFocus.framing(
            middle, source: (1920, 1080), canvas: (1080, 1920), fill: false, within: MotionFocus.Region(x: 0, y: 0, width: 1080, height: 1920))
        #expect(whole == full && whole.tilt == 0)
        #expect(throws: ProjectError.self) {
            try MotionFocus.framing(middle, source: (1920, 1080), canvas: (1080, 1920), fill: false,
                                    within: MotionFocus.Region(x: 0, y: 2000, width: 100, height: 100))
        }
    }

    @Test("within reads auto, full, the halves and x,y,w,h as shares or pixels")
    func parsesWithin() throws {
        let canvas = (width: 1080.0, height: 1920.0)
        #expect(try MotionFocus.Within("auto") == .auto && MotionFocus.Within.auto.band(canvas: canvas) == nil)
        #expect(try MotionFocus.Within("full").band(canvas: canvas) == MotionFocus.Region(x: 0, y: 0, width: 1080, height: 1920))
        #expect(try MotionFocus.Within("bottom-half").band(canvas: canvas) == MotionFocus.Region(x: 0, y: 960, width: 1080, height: 960))
        #expect(try MotionFocus.Within("0,0.5,1,0.5").band(canvas: canvas) == MotionFocus.Region(x: 0, y: 960, width: 1080, height: 960))
        #expect(try MotionFocus.Within("0,1000,1080,920").band(canvas: canvas) == MotionFocus.Region(x: 0, y: 1000, width: 1080, height: 920))
        #expect(try MotionFocus.Within(json: .array([0, 0, 1, 0.5].map(JSONValue.number))).band(canvas: canvas)?.height == 960)
        for bad in ["middle", "0,0,1", "0,0.6,1,0.5", "0,0,0,1", "-1,0,1,1"] {
            #expect(throws: ProjectError.self) { try MotionFocus.Within(bad) }
        }
    }

    @Test("The visible band is what a camera across the top leaves; full-canvas pictures and picture-in-picture do not count")
    func infersBand() throws {
        var project = splitProject()
        let band = MotionFocus.visibleBand(in: project, track: "v1", at: 10)
        // Camera: 1080×1920 at zoom 1.15, tilt 350, 34.2 % cropped off the bottom: covers y 0…959.
        #expect(band.x == 0 && band.width == 1080)
        #expect(abs(band.y - 959) < 1 && abs(band.y + band.height - 1920) < 0.1)
        // Past the camera's end, and for the camera's own layer, the whole frame.
        #expect(MotionFocus.visibleBand(in: project, track: "v1", at: 700) == MotionFocus.Region(x: 0, y: 0, width: 1080, height: 1920))
        #expect(MotionFocus.visibleBand(in: project, track: "v2", at: 10).height == 1920)
        let overlay = project.tracks.firstIndex { $0.role == TrackRole.overlay }!
        // A see-through camera does not cover.
        project.tracks[overlay].items[0]["opacity"] = .number(0.5)
        #expect(MotionFocus.visibleBand(in: project, track: "v1", at: 10).height == 1920)
        // A full-canvas picture and a small picture-in-picture leave the band alone.
        var full = Item(id: "full", media: "cam", at: 0, duration: 600)
        full["fill"] = .bool(true)
        var pip = Item(id: "pip", media: "cam", at: 0, duration: 600)
        pip["transform"] = .object(["zoom": .number(0.3), "pan": .number(300)])
        project.tracks[overlay].items = [full]
        #expect(MotionFocus.visibleBand(in: project, track: "v1", at: 10).height == 1920)
        project.tracks[overlay].items = [pip]
        #expect(MotionFocus.visibleBand(in: project, track: "v1", at: 10).height == 1920)
    }

    @Test("Stops hold each framing until it departs, then ease into the next")
    func stopKeys() {
        let a = MotionFocus.Framing(zoom: 2, pan: 0, tilt: -480)
        let b = MotionFocus.Framing(zoom: 3, pan: 100, tilt: -600)
        let c = MotionFocus.Framing(zoom: 2.5, pan: -50, tilt: -500)
        let keys = MotionFocus.keys(
            [.init(depart: 0, arrive: 0, framing: a), .init(depart: 30, arrive: 45, framing: b),
             .init(depart: 40, arrive: 50, framing: c)],
            ease: .easeOut)
        #expect(keys["zoom"]?.map(\.frame) == [0, 30, 45, 50])
        #expect(keys["zoom"]?.map(\.value) == [2, 2, 3, 2.5])
        #expect(keys["zoom"]?.map(\.ease) == [.easeOut, .easeOut, .easeOut, .easeInOut])
        // focus with focus-to: one move over the whole item, as before.
        let move = MotionFocus.keys([.init(depart: 0, arrive: 0, framing: a), .init(depart: 0, arrive: 89, framing: b)], ease: .linear)
        #expect(move["pan"]?.map(\.frame) == [0, 89] && move["pan"]?.first?.ease == .linear)
    }

    // MARK: plan.cut

    func apply(_ json: String, on project: Project) throws -> Project {
        let spec = try plan.spec(json)
        let clips = PlanCut.resolve(spec, project: project, transcripts: [:]).clips
        let built = try PlanCut.build(spec, clips: clips, on: project)
        return try project.applying(.group(label: "Plan", author: .user, ops: built.planner.operations)).project
    }

    func item(_ id: String, in project: Project) throws -> Item {
        try #require(project.tracks.flatMap(\.items).first { $0.id == id })
    }

    func framing(of item: Item, at frame: Double) throws -> MotionFocus.Framing {
        let motion = try #require(item.motion)
        return MotionFocus.Framing(
            zoom: try #require(motion.value("zoom", at: frame)), pan: try #require(motion.value("pan", at: frame)),
            tilt: try #require(motion.value("tilt", at: frame)))
    }

    @Test("plan.cut focus, focusKeys, within and ease read back, and the list keeps them through a patch")
    func decodesFocus() throws {
        let json = #"""
            {"clips":[{"id":"a","media":"m","from":2,"to":8,"focusKeys":[{"at":2,"rect":[0,0,960,540]},
            {"at":5,"rect":"960,540,960,540","move":0.3}],"within":"bottom-half","ease":"out","keyframes":{"opacity":[{"frame":0,"value":1}]}},
            {"id":"b","media":"m","from":9,"to":12,"cover":[{"media":"m","from":12,"focus":[100,100,800,450],"focusTo":[900,500,800,450]}]}]}
            """#
        let spec = try plan.spec(json)
        let focus = try #require(spec.clips[0].focus)
        #expect(focus.keys.map(\.at) == [2, 5] && focus.keys[1].move == 0.3)
        #expect(focus.keys[1].rect == MotionFocus.Region(x: 960, y: 540, width: 960, height: 540))
        #expect(focus.within == .region(MotionFocus.Region(x: 0, y: 0.5, width: 1, height: 0.5), fractions: true))
        #expect(focus.ease == .easeOut && focus.rect == nil)
        let cover = try #require(spec.clips[1].cover.first?.focus)
        #expect(cover.rect?.width == 800 && cover.to?.x == 900 && cover.within == .auto)
        #expect(spec.unknownFields.isEmpty)
        // A patch merges over the row, and the list still reads.
        let list = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let patched = try PlanCut.patch(list, with: .object(["clips": .object(["a": .object(["within": .string("full")])])]))
        let again = try PlanCut.decode(patched)
        #expect(again.clips[0].focus?.within == .full && again.clips[0].focus?.keys.count == 2)
        for bad in [
            #"{"clips":[{"media":"m","from":0,"to":2,"focus":[0,0,10,10],"zoom":2}]}"#,
            #"{"clips":[{"media":"m","from":0,"to":2,"focus":[0,0,10,10],"keyframes":{"pan":[{"frame":0,"value":1}]}}]}"#,
            #"{"clips":[{"media":"m","from":0,"to":2,"focus":[0,0,10,10],"focusTo":[0,0,10,10],"focusKeys":[{"at":0,"rect":[0,0,9,9]}]}]}"#,
            #"{"clips":[{"media":"m","from":0,"to":2,"within":"bottom-half"}]}"#,
            #"{"clips":[{"media":"m","from":0,"to":2,"focus":[0,0,10]}]}"#,
            #"{"clips":[{"media":"m","from":0,"to":2,"focusKeys":[{"at":1,"rect":[0,0,9,9]},{"at":1,"rect":[0,0,9,9]}]}]}"#,
            #"{"clips":[{"media":"m","from":0,"to":2,"focus":[0,0,10,10],"ease":"bouncy"}]}"#,
        ] {
            #expect(throws: ProjectError.self) { try plan.spec(bad) }
        }
    }

    @Test("plan apply frames a focus into the band the camera overlay leaves, and focusKeys step from panel to panel")
    func appliesFocus() throws {
        let project = splitProject()
        let panelA = MotionFocus.Region(x: 0, y: 0, width: 960, height: 540)
        let panelB = MotionFocus.Region(x: 960, y: 540, width: 960, height: 540)
        let built = try apply(#"""
            {"clips":[{"id":"a","media":"m","from":2,"to":8,"focusKeys":[{"at":2,"rect":[0,0,960,540]},
            {"at":5,"rect":[960,540,960,540],"move":0.5}],"keyframes":{"opacity":[{"frame":0,"value":1}]}}]}
            """#, on: project)
        let clip = try item("plan-a", in: built)
        let band = MotionFocus.visibleBand(in: built, track: "v1", at: clip.at)
        #expect(band.y > 950 && band.height < 970)
        // From (5 − 2) s = frame 90, 0.5 s (15 frames) to arrive.
        #expect(clip.motion?.keys["zoom"]?.map(\.frame) == [0, 90, 105])
        #expect(clip.motion?.keys["opacity"] != nil)
        #expect(inside(landing(panelA, try framing(of: clip, at: 0)), band))
        #expect(inside(landing(panelA, try framing(of: clip, at: 89)), band))
        #expect(inside(landing(panelB, try framing(of: clip, at: 105)), band))
        #expect(clip[PlanCut.pictureTag]?.array.contains(.string("keyframes")) == true)
        // A later apply rebuilds the same keys (they are the list's, not a hand edit).
        let again = try apply(#"""
            {"clips":[{"id":"a","media":"m","from":2,"to":8,"focus":[0,0,960,540],"within":"full"}]}
            """#, on: built)
        let full = try framing(of: try item("plan-a", in: again), at: 0)
        #expect(inside(landing(panelA, full), MotionFocus.Region(x: 0, y: 0, width: 1080, height: 1920)))
        #expect(try item("plan-a", in: again).motion?.keys["opacity"] == nil)
        #expect(try item("plan-a", in: again).motion?.keys["zoom"]?.count == 1)
    }

    @Test("A cover's focus moves to focusTo by its last frame inside the band; keys outside the shot are reported")
    func coverFocus() throws {
        let project = splitProject()
        let built = try apply(#"""
            {"clips":[{"id":"a","media":"m","from":2,"to":6,"cover":[{"media":"m","from":10,"focus":[0,0,960,540],
            "focusTo":[960,540,960,540]}]}]}
            """#, on: project)
        let cover = try item("plan-a-cover1", in: built)
        let band = MotionFocus.visibleBand(in: built, track: "v1", at: cover.at)
        let last = Double(cover.duration - 1)
        #expect(cover.motion?.keys["tilt"]?.map(\.frame) == [0, cover.duration - 1])
        #expect(inside(landing(MotionFocus.Region(x: 960, y: 540, width: 960, height: 540), try framing(of: cover, at: last)), band))
        let spec = try plan.spec(#"""
            {"clips":[{"id":"a","media":"m","from":2,"to":6,"focusKeys":[{"at":3,"rect":[0,0,960,540]},{"at":9,"rect":[0,0,960,540]}]}]}
            """#)
        let after = try apply(#"""
            {"clips":[{"id":"a","media":"m","from":2,"to":6,"focusKeys":[{"at":3,"rect":[0,0,960,540]},{"at":9,"rect":[0,0,960,540]}]}]}
            """#, on: project)
        let problems = PlanCut.focusProblems(spec, on: after)
        #expect(problems.map(\.id) == ["focus-key-outside"] && problems.first?.facts["at"] == .number(9))
    }
}
