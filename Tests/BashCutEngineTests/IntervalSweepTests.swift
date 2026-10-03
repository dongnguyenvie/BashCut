import Testing

@testable import BashCutEngine

struct IntervalSweepTests {
    @Test("Sweep matches half-open filtering through overlaps, gaps, repeated queries and skipped boundaries")
    func intervals() {
        let entries = [
            (start: 8, end: 14, value: "top"), (start: 0, end: 10, value: "bottom"),
            (start: 4, end: 8, value: "middle"), (start: 8, end: 8, value: "empty"),
            (start: 30, end: 31, value: "last")
        ]
        var sweep = IntervalSweep(entries)
        for frame in [-1, 0, 4, 7, 8, 8, 9, 10, 14, 29, 31, 40] {
            #expect(sweep.values(at: frame) == entries.filter { $0.start <= frame && $0.end > frame }.map(\.value))
        }
    }

    @Test("Unsorted overlapping intervals retain input order at every frame")
    func unsorted() {
        let entries = (0..<300).map { index in
            let start = (index * 47) % 101
            return (start: start, end: start + index % 23, value: index)
        }
        var sweep = IntervalSweep(entries)
        for frame in 0...130 {
            #expect(sweep.values(at: frame) == entries.filter { $0.start <= frame && $0.end > frame }.map(\.value))
        }
    }
}
