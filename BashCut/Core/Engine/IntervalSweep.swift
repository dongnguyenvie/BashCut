/// Active half-open intervals at monotonically increasing frame positions, preserving input (layer) order.
/// Each start/end is visited once; work per query depends on active layers, not all timeline items.
struct IntervalSweep<Value> {
    private let entries: [(start: Int, end: Int, value: Value)]
    private let starts: [Int]
    private let ends: [Int]
    private var nextStart = 0
    private var nextEnd = 0
    private var active: Set<Int> = []
    private var previous = Int.min

    init(_ entries: [(start: Int, end: Int, value: Value)]) {
        self.entries = entries
        starts = entries.indices.sorted { (entries[$0].start, $0) < (entries[$1].start, $1) }
        ends = entries.indices.sorted { (entries[$0].end, $0) < (entries[$1].end, $1) }
    }

    mutating func values(at frame: Int) -> [Value] {
        precondition(frame >= previous, "IntervalSweep requires ascending frames")
        previous = frame
        while nextStart < starts.count, entries[starts[nextStart]].start <= frame {
            let index = starts[nextStart]
            if entries[index].end > frame { active.insert(index) }
            nextStart += 1
        }
        while nextEnd < ends.count, entries[ends[nextEnd]].end <= frame {
            active.remove(ends[nextEnd])
            nextEnd += 1
        }
        return active.sorted().map { entries[$0].value }
    }
}
