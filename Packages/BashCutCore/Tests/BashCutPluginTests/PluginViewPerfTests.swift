import BashCutPlugin
import BashCutProject
import Foundation
import Testing

/// Times what the app does on the main actor for plugin views and requirements (#390). Runs only with BASHCUT_PERF=1
/// (`scripts/verify.sh perf`).
@Suite("Plugin view performance", .enabled(if: ProcessInfo.processInfo.environment["BASHCUT_PERF"] == "1"))
struct PluginViewPerfTests {
    private static func time(_ runs: Int = 20, _ body: () throws -> Void) rethrows -> (median: Double, worst: Double) {
        var samples: [Double] = []
        for _ in 0..<runs {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        samples.sort()
        return (samples[samples.count / 2], samples.last ?? 0)
    }

    /// The largest tree a plugin may send: sections of text, inputs and badges, and one list of 500 rows.
    static func largestAnswer() -> JSONValue {
        var sections: [JSONValue] = []
        var count = 1
        for section in 0..<30 where count < PluginViewTree.maximumNodes - 60 {
            var children: [JSONValue] = []
            for index in 0..<45 {
                let id = "s\(section)n\(index)"
                children.append(index % 3 == 0
                    ? .object(["type": .string("textField"), "id": .string(id), "value": .string("value \(index)")])
                    : .object(["type": .string("text"), "text": .string(String(repeating: "Lorem ipsum ", count: 8))]))
            }
            count += 1 + children.count
            sections.append(.object(["type": .string("section"), "title": .string("Section \(section)"),
                                     "children": .array(children)]))
        }
        let items: [JSONValue] = (0..<PluginViewTree.maximumListItems).map { index in
            .object(["id": .string("item\(index)"), "title": .string("Item \(index)"), "subtitle": .string("Subtitle"),
                     "icon": .string("film"), "actions": .array([.object(["id": .string("star"), "icon": .string("star")])])])
        }
        sections.append(.object(["type": .string("list"), "id": .string("list"), "items": .array(items)]))
        return .object(["title": .string("Perf"), "state": .object(["page": .integer(1)]), "body": .array(sections)])
    }

    @Test("Parsing the largest view and reading its inputs stays far below a frame")
    func parseLargest() throws {
        let answer = Self.largestAnswer()
        let data = try JSONEncoder().encode(answer)
        var tree: PluginViewTree?
        let decode = try Self.time { _ = try JSONDecoder().decode(JSONValue.self, from: data) }
        let fast = try Self.time { _ = try JSONValue(parsing: data) }
        let parse = try Self.time { tree = try PluginViewTree(parsing: answer) }
        let nodes = tree?.nodes.count ?? 0
        let inputs = Self.time { _ = tree?.inputValues }
        let lookup = Self.time { _ = tree?.node("list") }
        print(String(
            format: "[perf] view %d components, %d KB: JSONDecoder %.2f ms, JSONValue(parsing:) %.2f ms (worst %.2f), "
                + "parse %.2f ms (worst %.2f), inputValues %.2f ms, node(id) %.3f ms",
            nodes, data.count / 1024, decode.median, fast.median, fast.worst, parse.median, parse.worst, inputs.median,
            lookup.median))
        #expect(fast.median < 15, "reading a \(data.count / 1024) KB answer took \(fast.median) ms")
        #expect(nodes > 1300)
        #expect(parse.median < 8, "parsing \(nodes) components took \(parse.median) ms")
    }

    @Test("Requirement checks over 1000 plugins with chains")
    func requirements() {
        let plugins: [InstalledPlugin] = (0..<1000).map { index in
            let requires = index == 0 ? nil : [PluginRequirement(id: String(format: "perf.p%04d", index - 1), version: ">=1.0.0")]
            return InstalledPlugin(
                manifest: PluginManifest(
                    id: String(format: "perf.p%04d", index), name: LocalizedText(["en": "P\(index)"]), version: "1.2.0",
                    apiVersion: 8, entrypoint: "bin/provider", capabilities: ["x.y"], requires: requires),
                directory: URL(fileURLWithPath: "/tmp/perf/\(index)"))
        }
        var problems: [String: String] = [:]
        let chained = Self.time(5) { problems = PluginRequirements.problems(plugins) { _ in true } }
        #expect(problems.isEmpty)
        let broken = Self.time(5) { problems = PluginRequirements.problems(plugins) { $0.id != "perf.p0000" } }
        #expect(problems.count == 999)
        print(String(format: "[perf] requires over 1000 chained plugins: %.2f ms; with the root off %.2f ms",
                     chained.median, broken.median))
        #expect(chained.median < 50)
    }
}
