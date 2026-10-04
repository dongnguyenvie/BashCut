import AVFoundation
import BashCutProject
import BashCutTestSupport
import CoreGraphics
import Testing

@testable import BashCutEngine

struct EngineControlsTests {
    @Test("Composition resolves shared workspace media")
    func sharedWorkspaceMedia() async throws {
        let fixture = try await TestFixtures.requireVideo()
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let assets = workspace.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.copyItem(at: fixture, to: assets.appendingPathComponent("shared.mp4"))
        let media = Media(fields: [
            "id": .string("shared"), "path": .string("@assets/shared.mp4"),
            "fps": FrameRate().json, "frames": .integer(59),
        ])
        let project = try Project(name: "Shared").applying(
            .group(
                label: "Fixture", author: .user,
                ops: [
                    .addMedia(media),
                    .insert(track: "v1", item: Item(media: "shared", at: 0, duration: 30)),
                ])
        ).project
        let snapshot = try await CompositionBuilder().build(
            project, root: workspace.appendingPathComponent("projects/test"), workspace: workspace)
        #expect(snapshot.composition.duration.seconds > 0.9)
    }

    @Test("Freeze frame holds one source image across the clip")
    func freezeFrame() async throws {
        let root = TestFixtures.mediaRoot
        let media = Media(fields: [
            "id": .string("m"), "path": .string("test.mp4"),
            "fps": FrameRate().json, "frames": .integer(59),
        ])
        var clip = Item(id: "c", media: "m", at: 0, duration: 45)
        clip["freezeFrame"] = .integer(10)
        let project = try Project(name: "Freeze").applying(
            .group(
                label: "Fixture", author: .user,
                ops: [.addMedia(media), .insert(track: "v1", item: clip)]
            )
        ).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        let early = try pixels(try await generator.image(at: project.fps.time(5)).image)
        let late = try pixels(try await generator.image(at: project.fps.time(35)).image)
        #expect(early == late)
    }

    @Test("Color, opacity and audio controls reach the shared composition")
    func controls() async throws {
        let root = TestFixtures.mediaRoot
        let media = Media(fields: [
            "id": .string("m"), "path": .string("test.mp4"),
            "fps": FrameRate().json, "frames": .integer(59),
        ])
        var clip = Item(id: "c", media: "m", at: 0, duration: 45)
        clip["color"] = .object(["saturation": .integer(0)])
        clip["muted"] = .bool(true)
        let project = try Project(name: "Controls").applying(
            .group(
                label: "Fixture", author: .user,
                ops: [
                    .addMedia(media), .insert(track: "v1", item: clip),
                ])
        ).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        let image = try await generator.image(at: project.fps.time(20)).image
        let colors = try pixels(image)
        let isGrayscale = stride(from: 0, to: colors.count, by: 4).allSatisfy { offset in
            let red = Int(colors[offset])
            let green = Int(colors[offset + 1])
            let blue = Int(colors[offset + 2])
            return abs(red - green) < 3 && abs(green - blue) < 3
        }
        #expect(isGrayscale)
        var start: Float = 1
        var end: Float = 1
        var range = CMTimeRange.invalid
        let audio = try #require(snapshot.audioMix.inputParameters.first)
        #expect(audio.getVolumeRamp(for: .zero, startVolume: &start, endVolume: &end, timeRange: &range))
        #expect(start == 0 && end == 0)

        let invisible = try project.applying(.setProperties(item: "c", patch: ["opacity": .integer(0)])).project
        let hidden = try await CompositionBuilder().build(invisible, root: root)
        let hiddenGenerator = AVAssetImageGenerator(asset: hidden.composition)
        hiddenGenerator.videoComposition = hidden.videoComposition
        let black = try pixels(try await hiddenGenerator.image(at: project.fps.time(20)).image)
        #expect(
            stride(from: 0, to: black.count, by: 4).allSatisfy {
                black[$0] < 3 && black[$0 + 1] < 3 && black[$0 + 2] < 3
            })
    }

    @Test("A hidden layer is left out of every frame")
    func hiddenLayer() async throws {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("test.mp4"), "fps": FrameRate().json, "frames": .integer(59),
        ])
        var caption = Item(id: "t", at: 0, duration: 45)
        caption["text"] = .string("Xin chào")
        let project = try Project(name: "Hidden").applying(
            .group(label: "Fixture", author: .user, ops: [
                .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "m", at: 0, duration: 45)),
                .insert(track: "t1", item: caption), .setTrackProperties(track: "v1", patch: ["hidden": .bool(true)]),
            ])
        ).project
        let snapshot = try await CompositionBuilder().build(project, root: TestFixtures.mediaRoot)
        let layers = snapshot.videoComposition.instructions.compactMap { $0 as? FrameInstruction }.flatMap(\.layers)
        #expect(!layers.isEmpty)
        #expect(layers.allSatisfy { if case .text = $0 { true } else { false } })
    }

    @Test("An adjustment grades the layers below it while on screen, and captions above it stay ungraded")
    func adjustmentLayer() async throws {
        let media = Media(fields: [
            "id": .string("m"), "path": .string("test.mp4"), "fps": FrameRate().json, "frames": .integer(59),
        ])
        var caption = Item(id: "t", at: 0, duration: 45)
        caption["text"] = .string("Xin chào")
        var planner = LayerPlanner(try Project(name: "Adjustment").applying(
            .group(label: "Fixture", author: .user, ops: [
                .addMedia(media), .insert(track: "v1", item: Item(id: "c", media: "m", at: 0, duration: 45)),
                .insert(track: "t1", item: caption),
            ])
        ).project)
        try planner.placeAdjustment(.adjustment(id: "g", at: 0, duration: 20, color: ["saturation": .integer(0)]))
        let project = planner.project
        let snapshot = try await CompositionBuilder().build(project, root: TestFixtures.mediaRoot)
        let first = try #require(snapshot.videoComposition.instructions.first as? FrameInstruction)
        #expect(first.layers.map(Self.kind) == ["video", "adjustment", "text"])
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        func isGrayscale(_ frame: Int) async throws -> Bool {
            let colors = try pixels(try await generator.image(at: project.fps.time(frame)).image)
            return stride(from: 0, to: colors.count, by: 4).allSatisfy { offset -> Bool in
                let red = Int(colors[offset])
                let green = Int(colors[offset + 1])
                let blue = Int(colors[offset + 2])
                return abs(red - green) < 3 && abs(green - blue) < 3
            }
        }
        let uncaptioned = try project.applying(.delete(item: "t", ripple: false)).project
        let plain = try await CompositionBuilder().build(uncaptioned, root: TestFixtures.mediaRoot)
        generator.videoComposition = plain.videoComposition
        #expect(try await isGrayscale(10))
        #expect(try await !isGrayscale(30))
        let bypassed = try await CompositionBuilder().build(
            uncaptioned.applying(.setTrackProperties(track: "fx1", patch: ["hidden": .bool(true)])).project,
            root: TestFixtures.mediaRoot)
        generator.videoComposition = bypassed.videoComposition
        #expect(try await !isGrayscale(10))
    }

    private static func kind(_ layer: VisualLayer) -> String {
        switch layer {
        case .video: "video"
        case .adjustment: "adjustment"
        case .text: "text"
        }
    }

    @Test("Transitions add a tweened outgoing hold and incoming layer")
    func transitions() async throws {
        let root = TestFixtures.mediaRoot
        let media = Media(fields: [
            "id": .string("m"), "path": .string("test.mp4"),
            "fps": FrameRate().json, "frames": .integer(59),
        ])
        let project = try Project(name: "Transition").applying(
            .group(label: "Fixture", author: .user, ops: [
                .addMedia(media),
                .insert(track: "v1", item: Item(id: "a", media: "m", at: 0, duration: 20)),
                .insert(
                    track: "v1", item: Item(id: "b", media: "m", at: 20, duration: 20, sourceIn: 20)),
                .upsertTransition(id: "cut", kind: "dissolve", from: "a", to: "b", duration: 10),
            ])).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let instruction = try #require(
            snapshot.videoComposition.instructions.compactMap { $0 as? FrameInstruction }.first {
                $0.timeRange.start == project.fps.time(20)
            })
        let transitions = instruction.layers.compactMap { layer -> RenderTransition? in
            guard case .video(let value) = layer else { return nil }
            return value.transition
        }
        #expect(instruction.containsTweening)
        #expect(transitions.count == 2)
        #expect(Set(transitions.map(\.incoming)) == Set([true, false]))
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        #expect(try await generator.image(at: project.fps.time(25)).image.width > 0)
    }

    @Test("Cube LUT parser and compositor accept a red-fastest identity LUT")
    func colorLUT() async throws {
        let cube = """
            TITLE "Identity"
            LUT_3D_SIZE 2
            DOMAIN_MIN 0 0 0
            DOMAIN_MAX 1 1 1
            0 0 0
            1 0 0
            0 1 0
            1 1 0
            0 0 1
            1 0 1
            0 1 1
            1 1 1
            """
        let parsed = try CubeLUT.parse(cube)
        #expect(parsed.dimension == 2)
        #expect(parsed.cubeData.count == 2 * 2 * 2 * 4 * MemoryLayout<Float>.size)

        let fixture = try await TestFixtures.requireVideo()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("luts"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: fixture, to: root.appendingPathComponent("test.mp4"))
        try cube.write(to: root.appendingPathComponent("luts/identity.cube"), atomically: true, encoding: .utf8)
        let media = Media(fields: [
            "id": .string("m"), "path": .string("test.mp4"),
            "fps": FrameRate().json, "frames": .integer(59),
        ])
        var project = Project(name: "LUT")
        project = try project.applying(.group(label: "Fixture", author: .user, ops: [
            .addMedia(media),
            .addColorLUT(ColorLUT(id: "identity", name: "Identity", path: "luts/identity.cube", size: 2)),
            .insert(track: "v1", item: Item(id: "clip", media: "m", at: 0, duration: 30)),
            .setProperties(item: "clip", patch: ["color": .object(["lut": .string("identity")])]),
        ])).project
        let snapshot = try await CompositionBuilder().build(project, root: root)
        let generator = AVAssetImageGenerator(asset: snapshot.composition)
        generator.videoComposition = snapshot.videoComposition
        #expect(try await generator.image(at: project.fps.time(10)).image.width > 0)
    }

    @Test("Caption presets and custom style produce distinct nonempty images")
    func textPresets() throws {
        var item = Item(at: 0, duration: 90)
        item["text"] = .string("Buôn Ma Thuột · ă â đ ê ô ơ ư")
        let size = CGSize(width: 540, height: 960)
        var outputs: [[UInt8]] = []
        for style in [
            "bold-outline", "cinematic-serif", "keyword-sticker", "place-card", "hook-title",
            "chapter-card",
        ] {
            item["textPreset"] = .string(style)
            let image = try #require(TextRenderer.image(item, size: size))
            let data = try pixels(image)
            #expect(data.contains { $0 != 0 })
            outputs.append(data)
        }
        #expect(Set(outputs).count == 6)
        item["textStyle"] = .object(["positionY": .number(0.7), "size": .number(0.08)])
        #expect(try pixels(#require(TextRenderer.image(item, size: size))) != outputs[5])
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try result.withUnsafeMutableBytes { bytes in
            let context = try #require(
                CGContext(
                    data: bytes.baseAddress, width: image.width, height: image.height,
                    bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return result
    }
}
