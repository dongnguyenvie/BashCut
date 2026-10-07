import AVFoundation
import BashCutProject
import Foundation

public enum ExportPreset: String, CaseIterable, Sendable, Identifiable {
    case tiktok
    /// Reels and Shorts render like TikTok; their platform targets differ (#441).
    case reels
    case shorts
    case youtube1080
    case youtube4K
    case quickDraft
    case proRes422HQ

    public var id: String { rawValue }
    public init?(argument: String) {
        switch argument.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "tiktok", "tiktok-9x16": self = .tiktok
        case "reels", "instagram-reels": self = .reels
        case "shorts", "youtube-shorts": self = .shorts
        case "youtube1080", "youtube-1080", "youtube-1080p": self = .youtube1080
        case "youtube4k", "youtube-4k": self = .youtube4K
        case "quickdraft", "quick-draft", "draft", "720p": self = .quickDraft
        case "prores422hq", "prores-422-hq", "prores": self = .proRes422HQ
        default: return nil
        }
    }
    public var title: String {
        switch self {
        case .tiktok: "TikTok 9:16"
        case .reels: "Instagram Reels 9:16"
        case .shorts: "YouTube Shorts 9:16"
        case .youtube1080: "YouTube 16:9 1080p"
        case .youtube4K: "YouTube 16:9 4K"
        case .quickDraft: "Quick Draft 720p"
        case .proRes422HQ: "ProRes 422 HQ"
        }
    }
    public var size: CGSize? {
        switch self {
        case .tiktok, .reels, .shorts: CGSize(width: 1080, height: 1920)
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
    public var videoBitRate: Int? {
        switch self {
        case .tiktok, .reels, .shorts: 16_000_000
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
        case .quickDraft, .proRes422HQ: nil
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
    public init(preset: ExportPreset) { self.preset = preset }
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
