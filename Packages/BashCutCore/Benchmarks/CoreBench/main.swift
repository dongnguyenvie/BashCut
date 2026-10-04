import BashCutProject
import Foundation

// Core edit cost on synthetic projects. Run in release:
//   swift run -c release bashcut-core-bench [items...]
// Each project has 20 media; 60% of the items sit on the main track (every tenth cut has a dissolve),
// 20% are captions and 20% music.

func synthetic(items count: Int) throws -> Project {
    var ops: [EditOperation] = (0..<20).map { index in
        .addMedia(Media(fields: [
            "id": .string("m\(index)"), "path": .string("media/clip\(index).mov"), "kind": .string("video"),
            "frames": .integer(100_000), "fps": FrameRate(30, 1).json,
        ]))
    }
    let main = count * 6 / 10
    let captions = count * 2 / 10
    for index in 0..<main {
        ops.append(.insert(track: "v1", item: Item(
            id: "v\(index)", media: "m\(index % 20)", at: index * 60, duration: 60, sourceIn: index * 10)))
    }
    for index in 0..<captions {
        var item = Item(id: "t\(index)", at: index * 90, duration: 60)
        item.fields["text"] = .string("Caption \(index)")
        ops.append(.insert(track: "t1", item: item))
    }
    for index in 0..<(count - main - captions) {
        ops.append(.insert(track: "a3", item: Item(
            id: "a\(index)", media: "m\(index % 20)", at: index * 120, duration: 100)))
    }
    for index in stride(from: 10, to: main, by: 10) {
        ops.append(.upsertTransition(id: "x\(index)", kind: "dissolve", from: "v\(index - 1)", to: "v\(index)", duration: 10))
    }
    return try Project(name: "Bench", fps: FrameRate(30, 1)).applying(.group(label: "Setup", author: .user, ops: ops))
        .project
}

func measure(_ repeats: Int = 20, _ body: () throws -> Void) rethrows -> Double {
    var samples: [Double] = []
    for _ in 0..<repeats {
        let start = DispatchTime.now().uptimeNanoseconds
        try body()
        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
    }
    return samples.sorted()[samples.count / 2]
}

func format(_ milliseconds: Double) -> String {
    milliseconds >= 100 ? String(format: "%.0f ms", milliseconds) : String(format: "%.2f ms", milliseconds)
}

// `--profile <items>` repeats one setProperties edit for ten seconds, for `sample` or Instruments.
if CommandLine.arguments.dropFirst().first == "--profile" {
    let size = CommandLine.arguments.dropFirst(2).first.flatMap(Int.init) ?? 1_000
    let project = try synthetic(items: size)
    let end = Date().addingTimeInterval(10)
    while Date() < end { _ = try project.applying(.setProperties(item: "v1", patch: ["opacity": .number(0.5)])) }
    exit(0)
}
let sizes = CommandLine.arguments.dropFirst().compactMap(Int.init)
for size in sizes.isEmpty ? [100, 500, 1_000] : sizes {
    let project = try synthetic(items: size)
    let middle = "v\(size * 3 / 10)"
    let validate = try measure {
        var copy = project
        copy.revision += 0  // any change forgets that the project was already validated
        try copy.validate()
    }
    let property = try measure { _ = try project.applying(.setProperties(item: middle, patch: ["opacity": .number(0.5)])) }
    let ripple = try measure { _ = try project.applying(.delete(item: middle, ripple: true)) }
    let group = try measure {
        let ops = (0..<50).map { EditOperation.setProperties(item: "v\($0)", patch: ["opacity": .number(0.5)]) }
        _ = try project.applying(.group(label: "Batch", author: .user, ops: ops))
    }
    let file = try project.data()
    let open = try measure(3) { _ = try Project.decode(file) }
    var history = ProjectHistory(project: project)
    let steps = try measure(1) {
        for step in 0..<ProjectHistory.maximumDepth {
            try history.apply(
                .setProperties(item: "v\(step % (size * 6 / 10))", patch: ["opacity": .number(Double(step % 10) / 10)]),
                label: "Step")
        }
    } / Double(ProjectHistory.maximumDepth)
    var journal = Data()
    let encode = try measure(3) { journal = try JSONEncoder().encode(history) }
    let decode = try measure(3) { _ = try JSONDecoder().decode(ProjectHistory.self, from: journal) }
    let undo = try measure(1) { for _ in 0..<50 { try history.undo() } } / 50
    print("""
        \(size) items: open \(format(open)) (\(file.count / 1_000) KB), validate \(format(validate)), \
        setProperties \(format(property)), ripple delete \(format(ripple)), \
        50-op group \(format(group)), history step \(format(steps)), undo \(format(undo)); \
        200-step journal \(String(format: "%.1f", Double(journal.count) / 1e6)) MB, encode \(format(encode)), \
        decode \(format(decode))
        """)
}
