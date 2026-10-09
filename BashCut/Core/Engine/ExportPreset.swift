import AVFoundation
import BashCutProject
import Foundation

public enum ExportPreset: String, CaseIterable, Sendable, Identifiable {
    case tiktok
    /// Reels and Shorts render like TikTok; their platform targets differ (#441).
    case reels
    case shorts
    /// Feed shapes (P1-F2): 4:5 for Instagram and Facebook feeds, 1:1, and 3:4 (Xiaohongshu).
    case feed4x5
    case square
    case portrait3x4
    case youtube1080
    case youtube4K
    case quickDraft
    case proRes422HQ

    public var id: String { rawValue }
    /// Every spelling `export start --preset` and `output.presets` accept.
    static let aliases: [String: ExportPreset] = [
        "tiktok": .tiktok, "tiktok-9x16": .tiktok, "reels": .reels, "instagram-reels": .reels, "shorts": .shorts,
        "youtube-shorts": .shorts, "feed-4x5": .feed4x5, "4x5": .feed4x5, "instagram-feed": .feed4x5, "square": .square,
        "1x1": .square, "feed-1x1": .square, "portrait-3x4": .portrait3x4, "3x4": .portrait3x4,
        "xiaohongshu": .portrait3x4, "youtube1080": .youtube1080, "youtube-1080": .youtube1080,
        "youtube-1080p": .youtube1080, "youtube4k": .youtube4K, "youtube-4k": .youtube4K, "quickdraft": .quickDraft,
        "quick-draft": .quickDraft, "draft": .quickDraft, "720p": .quickDraft, "prores422hq": .proRes422HQ,
        "prores-422-hq": .proRes422HQ, "prores": .proRes422HQ,
    ]

    public init?(argument: String) {
        guard let preset = Self.aliases[argument.lowercased().replacingOccurrences(of: "_", with: "-")] else { return nil }
        self = preset
    }
    public var title: String {
        switch self {
        case .tiktok: "TikTok 9:16"
        case .reels: "Instagram Reels 9:16"
        case .shorts: "YouTube Shorts 9:16"
        case .feed4x5: "Feed 4:5"
        case .square: "Square 1:1"
        case .portrait3x4: "Portrait 3:4"
        case .youtube1080: "YouTube 16:9 1080p"
        case .youtube4K: "YouTube 16:9 4K"
        case .quickDraft: "Quick Draft 720p"
        case .proRes422HQ: "ProRes 422 HQ"
        }
    }
    public var size: CGSize? {
        switch self {
        case .tiktok, .reels, .shorts: CGSize(width: 1080, height: 1920)
        case .feed4x5: CGSize(width: 1080, height: 1350)
        case .square: CGSize(width: 1080, height: 1080)
        case .portrait3x4: CGSize(width: 1080, height: 1440)
        case .youtube1080: CGSize(width: 1920, height: 1080)
        case .youtube4K: CGSize(width: 3840, height: 2160)
        case .quickDraft: nil
        case .proRes422HQ: nil
        }
    }
    public var videoCodec: AVVideoCodecType {
        self == .proRes422HQ ? .proRes422HQ : .h264
    }
    public var fileType: AVFileType { self == .proRes422HQ ? .mov : .mp4 }
    public var fileExtension: String { self == .proRes422HQ ? "mov" : "mp4" }
    /// The default video bit rate: under the platform's recompression line when the platform table knows it
    /// (P1-F2: Reels about 5, TikTok and Shorts about 8 Mbps), else a fixed one; `export start --bitrate` overrides it.
    public var videoBitRate: Int? {
        if let mbps = platform?.bitrateMbps { return Int(mbps * 1_000_000) }
        return switch self {
        case .tiktok, .reels, .shorts: 8_000_000
        // Feeds share the vertical apps' recompression; Instagram's (about 5 Mbps) is the lowest seen.
        case .feed4x5: 5_000_000
        case .square, .portrait3x4: 8_000_000
        case .youtube1080: 12_000_000
        case .youtube4K: 45_000_000
        case .quickDraft: 4_000_000
        case .proRes422HQ: nil
        }
    }

    /// The CLI and project spelling (`export start --preset`, `output.presets`).
    public var argument: String {
        switch self {
        case .tiktok: "tiktok"
        case .reels: "reels"
        case .shorts: "shorts"
        case .feed4x5: "feed-4x5"
        case .square: "square"
        case .portrait3x4: "portrait-3x4"
        case .youtube1080: "youtube-1080"
        case .youtube4K: "youtube-4k"
        case .quickDraft: "quick-draft"
        case .proRes422HQ: "prores"
        }
    }

    /// The platform whose targets review checks for this preset; drafts and masters have none.
    public var platform: OutputPlatform? {
        switch self {
        case .tiktok: .tiktok
        case .reels: .reels
        case .shorts: .shorts
        case .youtube1080, .youtube4K: .youtube
        case .quickDraft, .proRes422HQ, .feed4x5, .square, .portrait3x4: nil
        }
    }

    public func dimensions(projectWidth: Int, projectHeight: Int) -> (Int, Int) {
        if let size { return (Int(size.width), Int(size.height)) }
        if self == .quickDraft {
            if projectWidth == projectHeight { return (720, 720) }
            if projectWidth >= projectHeight {
                return (1280, max(2, even(1280 * projectHeight / projectWidth)))
            }
            return (max(2, even(1280 * projectWidth / projectHeight)), 1280)
        }
        return (projectWidth, projectHeight)
    }

    private func even(_ value: Int) -> Int { value - value % 2 }
}

public struct ExportSettings: Sendable {
    public let preset: ExportPreset
    /// Overrides the preset's video bit rate (`export start --bitrate`).
    public let videoBitRate: Int?

    public init(preset: ExportPreset, videoBitRate: Int? = nil) {
        self.preset = preset
        self.videoBitRate = videoBitRate
    }

    public var effectiveVideoBitRate: Int? { preset.videoCodec == .h264 ? videoBitRate ?? preset.videoBitRate : nil }
}

public struct ExportReceipt: Sendable, Equatable {
    public let url: URL
    public let duration: Double
    public let bytes: Int64

    public init(url: URL, duration: Double, bytes: Int64) {
        self.url = url
        self.duration = duration
        self.bytes = bytes
    }
}
