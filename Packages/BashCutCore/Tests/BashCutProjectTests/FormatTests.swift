import BashCutProjectFixtures
import Testing

@testable import BashCutProject

struct FormatTests {
    @Test("setFormat turns a portrait project landscape and scales clip framing offsets")
    func portraitToLandscape() throws {
        var project = try ProjectFixtures.twoClips()
        project = try project.applying(.setFormat(width: 1080, height: 1920)).project
        project = try project.applying(
            .setProperties(
                item: "left", patch: ["transform": .object(["zoom": .number(1.2), "pan": .integer(60), "tilt": .integer(-40)])])
        ).project
        let landscape = try project.applying(.setFormat(width: 1920, height: 1080)).project
        #expect(landscape.width == 1920 && landscape.height == 1080)
        let transform = try #require(landscape.tracks.flatMap(\.items).first { $0.id == "left" }?["transform"]?.object)
        #expect(transform["zoom"]?.double == 1.2)
        #expect(transform["pan"]?.double == 107)  // 60 × 1920/1080, rounded
        #expect(transform["tilt"]?.double == -23)  // -40 × 1080/1920, rounded
        // Timing is untouched.
        #expect(landscape.duration == project.duration)
    }

    @Test("Odd, tiny or huge sizes are refused, and the codec reads setFormat")
    func validation() throws {
        let project = try ProjectFixtures.twoClips()
        #expect(throws: ProjectError.self) { try project.applying(.setFormat(width: 1921, height: 1080)) }
        #expect(throws: ProjectError.self) { try project.applying(.setFormat(width: 8, height: 1080)) }
        #expect(throws: ProjectError.self) { try project.applying(.setFormat(width: 10_000, height: 1080)) }
        let decoded = try EditOperation(json: .object(["op": .string("setFormat"), "width": .integer(1080), "height": .integer(1080)]))
        #expect(decoded == .setFormat(width: 1080, height: 1080))
    }

    @Test("Canvas dimensions match the New Project sizes")
    func canvasDimensions() {
        #expect(ProjectSetup.Canvas.portrait.dimensions(shortSide: 1080) == (1080, 1920))
        #expect(ProjectSetup.Canvas.landscape.dimensions(shortSide: 720) == (1280, 720))
        #expect(ProjectSetup.Canvas.square.dimensions(shortSide: 2160) == (2160, 2160))
    }

    private func autoProject() throws -> Project {
        var setup = ProjectSetup()
        setup.name = "Auto"
        var project = try setup.project()
        for (id, width, height) in [("wide", 1920, 1080), ("tall", 1080, 1920), ("square", 1000, 1040)] {
            var media = ProjectFixtures.media(id, kind: "video")
            media.fields["width"] = .integer(width)
            media.fields["height"] = .integer(height)
            project = try project.applying(.addMedia(media)).project
        }
        return project
    }

    @Test("The first picture clip sets the canvas shape, keeping the short side, only once")
    func firstClipSetsCanvas() throws {
        let empty = try autoProject()
        #expect(empty.canvasFromFirstClip && empty.width == 1080 && empty.height == 1920)
        let placed = try empty.applying(.insert(track: "v1", item: Item(id: "a", media: "wide", at: 0, duration: 30))).project
        let format = try #require(empty.formatForFirstClip(in: placed))
        #expect(format.canvas == .landscape && format.width == 1920 && format.height == 1080)

        // Setting the format, by hand or for the first clip, makes the canvas final.
        let landscape = try placed.applying(.setFormat(width: format.width, height: format.height)).project
        #expect(!landscape.canvasFromFirstClip)
        let next = try landscape.applying(.insert(track: "v1", item: Item(id: "b", media: "tall", at: 30, duration: 30))).project
        #expect(landscape.formatForFirstClip(in: next) == nil)

        // A matching shape needs no change; a near-square picture makes a square canvas.
        let tall = try empty.applying(.insert(track: "v1", item: Item(id: "c", media: "tall", at: 0, duration: 30))).project
        #expect(empty.formatForFirstClip(in: tall) == nil)
        let square = try empty.applying(.insert(track: "v1", item: Item(id: "d", media: "square", at: 0, duration: 30))).project
        #expect(empty.formatForFirstClip(in: square)?.canvas == .square)
    }

    @Test("A canvas chosen on purpose, or a project from before, is never changed by a clip")
    func chosenCanvasStays() throws {
        let empty = try autoProject()
        let chosen = try empty.applying(.setFormat(width: 1080, height: 1920)).project
        #expect(!chosen.canvasFromFirstClip)
        let placed = try chosen.applying(.insert(track: "v1", item: Item(id: "a", media: "wide", at: 0, duration: 30))).project
        #expect(chosen.formatForFirstClip(in: placed) == nil)

        var setup = ProjectSetup()
        setup.name = "Fixed"
        setup.canvasFromFirstClip = false
        #expect(try !setup.project().canvasFromFirstClip)
        #expect(!Project(name: "Older").canvasFromFirstClip)
        #expect(throws: ProjectError.self) {
            var invalid = Project(name: "Bad")
            invalid["canvasFromFirstClip"] = .string("yes")
            try invalid.validate()
        }
    }

    @Test("A bad layer position says so, not 'frame'")
    func layerPositionMessage() {
        #expect {
            try EditOperation(json: .object([
                "op": .string("moveTrack"), "track": .string("v2"), "toIndex": .number(1.5),
            ]))
        } throws: { error in
            "\(error)".contains("layer position")
        }
    }

    @Test("New projects fit clips inside the frame; older projects fill it; a clip can choose")
    func clipFill() throws {
        var setup = ProjectSetup()
        setup.name = "Fit"
        let created = try setup.project()
        #expect(!created.clipsFill)
        #expect(Project(name: "Older").clipsFill)
        var item = Item(at: 0, duration: 10)
        #expect(!created.fills(item))
        item["fill"] = .bool(true)
        #expect(created.fills(item))
        var invalid = created
        invalid["clipFill"] = .string("yes")
        #expect(throws: ProjectError.self) { try invalid.validate() }
    }
}
