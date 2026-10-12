import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// Plugin overlays on the timeline and viewer (#407).
@Suite("Plugin overlays")
struct PluginOverlayTests {
    private func parse(_ json: String) throws -> [PluginOverlay] {
        try PluginOverlay.parse(JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)))
    }

    @Test("Ranges, markers and regions parse and round-trip")
    func parses() throws {
        let overlays = try parse("""
            [{"id": "hook", "kind": "range", "start": 0, "end": 90, "label": "Hook", "color": "orange"},
             {"id": "beat", "kind": "marker", "start": 120, "track": "t1"},
             {"id": "face", "kind": "region", "rect": {"x": 0.1, "y": 0.2, "width": 0.3, "height": 0.4},
              "start": 30, "end": 60, "style": "fill", "color": "#ff0000"}]
            """)
        #expect(overlays.map(\.kind) == [.range, .marker, .region])
        #expect(overlays[0].frames == 0..<90 && overlays[1].frames == 120..<121 && overlays[2].frames == nil)
        #expect(overlays[2].shows(at: 30) && !overlays[2].shows(at: 60) && !overlays[2].shows(at: 29))
        #expect(try PluginOverlay.parse(.array(overlays.map(\.json))) == overlays)
        #expect(PluginFeature.all.contains("overlays"))
    }

    @Test("Bad overlays are refused", arguments: [
        #"{"kind": "range"}"#,
        #"[{"id": "a", "kind": "circle", "start": 0}]"#,
        #"[{"id": "a", "kind": "range", "start": 10, "end": 5}]"#,
        #"[{"id": "a", "kind": "range", "start": -1, "end": 5}]"#,
        #"[{"id": "a", "kind": "marker"}]"#,
        #"[{"id": "a", "kind": "region", "rect": {"x": 0.8, "y": 0, "width": 0.5, "height": 1}}]"#,
        #"[{"id": "a", "kind": "marker", "start": 1, "color": "teal"}]"#,
        #"[{"id": "a", "kind": "marker", "start": 1}, {"id": "a", "kind": "marker", "start": 2}]"#,
    ])
    func refused(_ json: String) {
        #expect(throws: PluginError.self) { try parse(json) }
    }

    @Test("At most 500 overlays per plugin")
    func capped() {
        let many = JSONValue.array((0...PluginOverlay.maximumPerPlugin).map { index in
            .object(["id": .string("m\(index)"), "kind": .string("marker"), "start": .integer(index)])
        })
        #expect(throws: PluginError.self) { try PluginOverlay.parse(many) }
    }

    @Test("The index finds the overlays in a part of the timeline, ranges that began earlier included")
    func index() throws {
        let long = try parse(#"[{"id": "long", "kind": "range", "start": 0, "end": 1000}]"#)
        let marks = try parse(#"[{"id": "m1", "kind": "marker", "start": 100}, {"id": "m2", "kind": "marker", "start": 500}]"#)
        let regions = try parse(#"[{"id": "r", "kind": "region", "rect": {"x": 0, "y": 0, "width": 1, "height": 1}, "start": 10, "end": 20}]"#)
        let index = PluginOverlayIndex(["a.long": long, "b.marks": marks, "c.regions": regions])
        #expect(index.timeline(in: 400..<600).map(\.overlay.id) == ["long", "m2"])
        #expect(index.timeline(in: 1000..<2000).isEmpty)
        #expect(index.timeline(in: 100..<101).map(\.overlay.id) == ["long", "m1"])
        #expect(index.regions(at: 15).map(\.plugin) == ["c.regions"] && index.regions(at: 25).isEmpty)
    }
}
