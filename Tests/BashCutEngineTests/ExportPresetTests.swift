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
        #expect(ExportPreset.tiktok.videoBitRate == 16_000_000)
        #expect(ExportPreset.proRes422HQ.videoBitRate == nil)
        #expect(ExportPreset(argument: "quick-draft") == .quickDraft)
        #expect(ExportPreset(argument: "youtube-4k") == .youtube4K)
        #expect(ExportPreset(argument: "unknown") == nil)
    }
}
