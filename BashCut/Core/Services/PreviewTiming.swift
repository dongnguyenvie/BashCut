import BashCutAutomation
import Foundation
import os

/// One rebuild's intervals, including cancelled/failed stages, visible in Instruments and the private debug log.
@MainActor
final class PreviewTiming {
    private static let signposter = OSSignposter(subsystem: "com.bashcut.app", category: "Preview")
    private var active: (name: StaticString, state: OSSignpostIntervalState, start: ContinuousClock.Instant)?
    private var milliseconds: [String: Double] = [:]

    func begin(_ name: StaticString) {
        end()
        active = (name, Self.signposter.beginInterval(name, id: Self.signposter.makeSignpostID()), .now)
    }

    func end() {
        guard let active else { return }
        Self.signposter.endInterval(active.name, active.state)
        let duration = active.start.duration(to: .now).components
        milliseconds[active.name.description, default: 0] += Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
        self.active = nil
    }

    func finish() {
        end()
        DebugLog.write("preview", summary)
    }

    var summary: String {
        ["build", "ready", "swap"].map { "\($0) \(String(format: "%.3f", milliseconds[$0, default: 0])) ms" }.joined(separator: ", ")
    }
}
