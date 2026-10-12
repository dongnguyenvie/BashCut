import BashCutEngine
import BashCutProject
import SwiftUI

/// The shape of a library sound in the Audio panel: its peak envelope as thin bars, read in the background and
/// cached under the user's Caches folder by file, size and date (the timeline's waveform analysis).
struct LibraryWaveformView: View {
    let url: URL?
    /// How many bars to draw across the width.
    var bars = 64

    @State private var peaks: [Float] = []

    var body: some View {
        Canvas { context, size in
            guard !peaks.isEmpty else { return }
            let width = size.width / CGFloat(peaks.count)
            var path = Path()
            for (index, peak) in peaks.enumerated() {
                let height = max(1, CGFloat(peak) * size.height)
                path.addRect(CGRect(
                    x: CGFloat(index) * width, y: (size.height - height) / 2, width: max(1, width - 1), height: height))
            }
            context.fill(path, with: .color(.secondary.opacity(0.7)))
        }
        .frame(height: 14)
        .accessibilityHidden(true)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            peaks = []
            return
        }
        guard let waveform = try? await Self.analyzer.waveform(url: url, cacheDirectory: Self.cacheDirectory),
            waveform.hasAudio, !Task.isCancelled
        else { return }
        peaks = waveform.bars(bars)
    }

    private static let analyzer = WaveformAnalyzer()
    private static let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("BashCut/LibraryWaveforms", isDirectory: true)
}
