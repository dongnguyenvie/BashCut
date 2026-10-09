import Foundation

/// The export presets a project may name (`output.presets`, `export start --preset`), in the CLI spelling. The app's
/// `ExportPreset` resolves each one.
public enum OutputPresetName {
    public static let all = [
        "tiktok", "reels", "shorts", "feed-4x5", "square", "portrait-3x4", "youtube-1080", "youtube-4k", "quick-draft",
        "prores",
    ]
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

/// What a platform expects of a finished video (#441): shape, longest upload, loudness and the zones its UI covers.
/// Export presets name their platform; review checks the project against the platforms of its outputs
/// (`output.presets`), and `review.platform` overrides the facts when an app changes (#469). The numbers come from
/// the platform table (`PlatformData`, P1-F1), each with its source, date and confidence in `facts`.
public struct OutputPlatform: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let vertical: Bool
    /// Longest video the platform takes as this format; nil has no practical limit.
    public let maxSeconds: Double?
    public let targetLUFS: Double
    public let maxTruePeakDbTP: Double
    public let safeArea: SafeArea
    /// Every field of the platform's table entry with its provenance.
    public let facts: [String: PlatformFact]

    public init(
        id: String, title: String, vertical: Bool, maxSeconds: Double?, targetLUFS: Double = -14,
        maxTruePeakDbTP: Double = -1, safeArea: SafeArea, facts: [String: PlatformFact] = [:]
    ) {
        self.id = id
        self.title = title
        self.vertical = vertical
        self.maxSeconds = maxSeconds
        self.targetLUFS = targetLUFS
        self.maxTruePeakDbTP = maxTruePeakDbTP
        self.safeArea = safeArea
        self.facts = facts
    }

    init(_ record: PlatformTable.Record) {
        let number = { (key: String) in record.number(key) ?? 0 }
        self.init(
            id: record.id, title: record.title, vertical: record.vertical, maxSeconds: record.number("maxSeconds"),
            targetLUFS: number("targetLUFS"), maxTruePeakDbTP: number("maxTruePeakDbTP"),
            safeArea: SafeArea(
                top: number("safeArea.top"), bottom: number("safeArea.bottom"), sideWidth: number("safeArea.sideWidth"),
                sideHeight: number("safeArea.sideHeight"), margin: number("safeArea.margin")),
            facts: record.fields)
    }

    /// The bitrate below which the platform does not re-compress, when known (P1-F2).
    public var bitrateMbps: Double? { facts["bitrateMbps"]?.value.double }

    public static var tiktok: OutputPlatform { named("tiktok")! }
    public static var reels: OutputPlatform { named("reels")! }
    public static var shorts: OutputPlatform { named("shorts")! }
    public static var youtube: OutputPlatform { named("youtube")! }

    /// The platforms of the table in use.
    public static var all: [OutputPlatform] { PlatformData.current.platforms.map(OutputPlatform.init) }

    public static func named(_ id: String) -> OutputPlatform? {
        PlatformData.current.platforms.first { $0.id == id }.map(OutputPlatform.init)
            ?? PlatformData.builtIn.platforms.first { $0.id == id }.map(OutputPlatform.init)
    }

    public var json: JSONValue {
        .object([
            "id": .string(id), "title": .string(title), "vertical": .bool(vertical),
            "maxSeconds": maxSeconds.map(JSONValue.number) ?? .null, "targetLUFS": .number(targetLUFS),
            "maxTruePeakDbTP": .number(maxTruePeakDbTP), "safeArea": safeArea.json,
            "bitrateMbps": bitrateMbps.map(JSONValue.number) ?? .null,
        ])
    }
}

extension Project {
    /// The export presets this project is made for (`output.presets`), first one primary; set by the user, a recipe
    /// skill or the format menu. Empty when none were chosen.
    public var outputPresets: [String] { self["output"]?.object["presets"]?.array.compactMap(\.string) ?? [] }

    /// The loudness an export of `preset` is normalized to and reviewed against (P0-K2): the project's
    /// `output.targets` for that preset, else the preset's platform, else the project's mix target.
    public func loudnessTarget(preset: String, platform: OutputPlatform?) -> (lufs: Double, truePeak: Double) {
        let own = self["output"]?.object["targets"]?.object[preset]?.object ?? [:]
        return (
            own["integratedLUFS"]?.double ?? platform?.targetLUFS ?? targetLUFS,
            own["truePeakDbTP"]?.double ?? platform?.maxTruePeakDbTP ?? -1
        )
    }
}
