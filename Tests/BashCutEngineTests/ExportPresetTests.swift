import BashCutEngine
import Testing

struct ExportPresetTests {
    @Test("Export presets resolve documented dimensions, codecs and containers")
    func presets() {
        #expect(ExportPreset.tiktok.dimensions(projectWidth: 1920, projectHeight: 1080) == (1080, 1920))
        #expect(ExportPreset.youtube1080.dimensions(projectWidth: 1080, projectHeight: 1920) == (1920, 1080))
        #expect(ExportPreset.youtube4K.dimensions(projectWidth: 1080, projectHeight: 1920) == (3840, 2160))
        #expect(ExportPreset.quickDraft.dimensions(projectWidth: 1080, projectHeight: 1920) == (720, 1280))
        #expect(ExportPreset.quickDraft.dimensions(projectWidth: 1920, projectHeight: 1080) == (1280, 720))
        #expect(ExportPreset.quickDraft.dimensions(projectWidth: 1080, projectHeight: 1080) == (720, 720))
        #expect(ExportPreset.proRes422HQ.dimensions(projectWidth: 1080, projectHeight: 1920) == (1080, 1920))
        #expect(ExportPreset.tiktok.fileExtension == "mp4")
        #expect(ExportPreset.proRes422HQ.fileExtension == "mov")
        #expect(ExportPreset.tiktok.videoBitRate == 8_000_000)
        #expect(ExportPreset.youtube1080.videoBitRate == 12_000_000)
        #expect(ExportSettings(preset: .tiktok, videoBitRate: 3_000_000).effectiveVideoBitRate == 3_000_000)
        #expect(ExportSettings(preset: .proRes422HQ, videoBitRate: 3_000_000).effectiveVideoBitRate == nil)
        #expect(ExportPreset.proRes422HQ.videoBitRate == nil)
        #expect(ExportPreset(argument: "quick-draft") == .quickDraft)
        #expect(ExportPreset(argument: "youtube-4k") == .youtube4K)
        #expect(ExportPreset(argument: "unknown") == nil)
    }

    @Test("Reels and Shorts render like TikTok and name their own platform (#441)")
    func platforms() {
        for preset in [ExportPreset.reels, .shorts] {
            #expect(preset.dimensions(projectWidth: 1920, projectHeight: 1080) == (1080, 1920))
        }
        // Under each platform's recompression line (P1-F2).
        #expect(ExportPreset.reels.videoBitRate == 5_000_000 && ExportPreset.shorts.videoBitRate == 8_000_000)
        #expect(ExportPreset(argument: "reels") == .reels)
        #expect(ExportPreset(argument: "youtube-shorts") == .shorts)
        // Feed shapes (P1-F2).
        #expect(ExportPreset(argument: "feed-4x5") == .feed4x5 && ExportPreset(argument: "square") == .square)
        #expect(ExportPreset.feed4x5.dimensions(projectWidth: 1080, projectHeight: 1920) == (1080, 1350))
        #expect(ExportPreset.square.dimensions(projectWidth: 1920, projectHeight: 1080) == (1080, 1080))
        #expect(ExportPreset(argument: "3x4") == .portrait3x4 && ExportPreset.portrait3x4.platform == nil)
        #expect(ExportPreset.allCases.allSatisfy { ExportPreset(argument: $0.argument) == $0 })
        #expect(ExportPreset.reels.platform?.id == "reels")
        #expect(ExportPreset.youtube4K.platform?.id == "youtube")
        #expect(ExportPreset.quickDraft.platform == nil)
        for preset in ExportPreset.allCases { #expect(ExportPreset(argument: preset.argument) == preset) }
    }
}
