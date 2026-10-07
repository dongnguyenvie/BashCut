import Foundation

/// The export presets a project may name (`output.presets`, `export start --preset`), in the CLI spelling. The app's
/// `ExportPreset` resolves each one.
public enum OutputPresetName {
    public static let all = ["tiktok", "reels", "shorts", "youtube-1080", "youtube-4k", "quick-draft", "prores"]
}

/// Where a vertical platform's own UI covers the picture, as fractions of the frame: the caption bar along the
/// bottom, the like/comment buttons on the right of the lower part, the tabs along the top. Landscape platforms
/// use a title-safe margin on every side instead.
public struct SafeArea: Sendable, Equatable {
    public let top: Double
    public let bottom: Double
    public let sideWidth: Double
    public let sideHeight: Double
    /// Landscape and square frames: keep text inside the central `1 - 2 × margin`.
    public let margin: Double

    public init(top: Double = 0, bottom: Double = 0, sideWidth: Double = 0, sideHeight: Double = 0, margin: Double = 0.05) {
        self.top = top
        self.bottom = bottom
        self.sideWidth = sideWidth
        self.sideHeight = sideHeight
        self.margin = margin
    }

    public var json: JSONValue {
        .object([
            "top": .number(top), "bottom": .number(bottom), "sideWidth": .number(sideWidth),
            "sideHeight": .number(sideHeight), "margin": .number(margin),
        ])
    }
}

/// What a platform expects of a finished video (#441): shape, longest upload, loudness, the zones its UI covers and
/// the smallest readable text. Export presets name their platform; review checks the project against the platform
/// of its first output preset (`output.presets`). Numbers are each app's documented limits in 2026, rounded to the
/// safe side; every short-form app plays at about -14 LUFS.
public struct OutputPlatform: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let vertical: Bool
    /// Longest video the platform takes as this format; nil has no practical limit.
    public let maxSeconds: Double?
    public let targetLUFS: Double
    public let maxTruePeakDbTP: Double
    public let safeArea: SafeArea
    /// Smallest text, as a share of the frame's short side (about 32 px on 1080).
    public let minTextSize: Double

    public init(
        id: String, title: String, vertical: Bool, maxSeconds: Double?, targetLUFS: Double = -14,
        maxTruePeakDbTP: Double = -1, safeArea: SafeArea, minTextSize: Double = 0.03
    ) {
        self.id = id
        self.title = title
        self.vertical = vertical
        self.maxSeconds = maxSeconds
        self.targetLUFS = targetLUFS
        self.maxTruePeakDbTP = maxTruePeakDbTP
        self.safeArea = safeArea
        self.minTextSize = minTextSize
    }

    /// TikTok: in-app uploads up to 10 minutes. Reels: 3 minutes, a taller caption area. Shorts: 3 minutes (since
    /// October 2024). YouTube: landscape, title safe 5 %.
    public static let tiktok = OutputPlatform(
        id: "tiktok", title: "TikTok", vertical: true, maxSeconds: 600,
        safeArea: SafeArea(top: 0.08, bottom: 0.16, sideWidth: 0.14, sideHeight: 0.46))
    public static let reels = OutputPlatform(
        id: "reels", title: "Instagram Reels", vertical: true, maxSeconds: 180,
        safeArea: SafeArea(top: 0.1, bottom: 0.2, sideWidth: 0.14, sideHeight: 0.5))
    public static let shorts = OutputPlatform(
        id: "shorts", title: "YouTube Shorts", vertical: true, maxSeconds: 180,
        safeArea: SafeArea(top: 0.08, bottom: 0.18, sideWidth: 0.14, sideHeight: 0.46))
    public static let youtube = OutputPlatform(
        id: "youtube", title: "YouTube", vertical: false, maxSeconds: nil, safeArea: SafeArea(margin: 0.05),
        minTextSize: 0.025)

    public static let all: [OutputPlatform] = [tiktok, reels, shorts, youtube]

    public static func named(_ id: String) -> OutputPlatform? { all.first { $0.id == id } }

    /// The platform review assumes when the project names none: TikTok for vertical frames, YouTube otherwise.
    public static func fallback(for project: Project) -> OutputPlatform {
        project.height > project.width ? .tiktok : .youtube
    }

    public var json: JSONValue {
        .object([
            "id": .string(id), "title": .string(title), "vertical": .bool(vertical),
            "maxSeconds": maxSeconds.map(JSONValue.number) ?? .null, "targetLUFS": .number(targetLUFS),
            "maxTruePeakDbTP": .number(maxTruePeakDbTP), "safeArea": safeArea.json, "minTextSize": .number(minTextSize),
        ])
    }
}

extension Project {
    /// The export presets this project is made for (`output.presets`), first one primary; set by the user, a recipe
    /// skill or the format menu. Empty when none were chosen.
    public var outputPresets: [String] { self["output"]?.object["presets"]?.array.compactMap(\.string) ?? [] }
}
