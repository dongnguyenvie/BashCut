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
