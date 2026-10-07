import Foundation

/// What a finished edit owes the people whose material it uses (P2-H9), from the media the timeline plays and their
/// `license` and `provenance` (P2-H8): credit lines, AI disclosure per output platform, Content ID notes and rights
/// flags. Facts only: BashCut does not decide whether a use is allowed.
public struct ProjectCredits: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        public let media: String
        /// "Title" by Author — Licence — link, or the licence's own attribution text.
        public let text: String
        /// The licence asks for it (CC BY family); other lines are courtesy credits.
        public let required: Bool
    }

    public struct Disclosure: Sendable, Equatable {
        public let platform: String
        public let rule: String
    }

    public let lines: [Line]
    /// Media made by AI that the edit plays (picture or sound).
    public let aiMedia: [String]
    /// Share (0–1) of the edit's length where the picture on top comes from AI media.
    public let aiPictureShare: Double
    /// The platform rules that apply because the edit plays AI media; empty without AI media.
    public let disclosures: [Disclosure]
    /// Stock or downloaded music the edit plays: platforms may claim it through Content ID.
    public let contentIDNotes: [String]
    /// Media whose licence forbids commercial use, reserves all rights, or is unknown or missing.
    public let nonCommercial: [String]
    public let allRightsReserved: [String]
    public let unknown: [String]

    /// The credit block for a video description: required lines first.
    public var text: String {
        (lines.filter(\.required) + lines.filter { !$0.required }).map(\.text).joined(separator: "\n")
    }

    public var json: JSONValue {
        .object([
            "lines": .array(lines.map { .object(["media": .string($0.media), "text": .string($0.text), "required": .bool($0.required)]) }),
            "text": .string(text),
            "ai": .object([
                "media": .array(aiMedia.map(JSONValue.string)),
                "pictureShare": .number((aiPictureShare * 1_000).rounded() / 1_000),
                "disclosures": .array(disclosures.map { .object(["platform": .string($0.platform), "rule": .string($0.rule)]) }),
            ]),
            "contentIDNotes": .array(contentIDNotes.map(JSONValue.string)),
            "flags": .object([
                "nonCommercial": .array(nonCommercial.map(JSONValue.string)),
                "allRightsReserved": .array(allRightsReserved.map(JSONValue.string)),
                "unknown": .array(unknown.map(JSONValue.string)),
            ]),
        ])
    }

    /// The credits of `project` as it plays now; `platforms` are its outputs' platforms (for disclosure rules).
    public static func of(_ project: Project, platforms: [OutputPlatform] = []) -> ProjectCredits {
        let played = project.tracks.filter { !$0.isHidden }.flatMap(\.items).compactMap(\.mediaID)
        let byID = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let used = played.reduce(into: [Media]()) { list, id in
            if let media = byID[id], !list.contains(where: { $0.id == id }) { list.append(media) }
        }
        var lines: [Line] = [], ai: [String] = [], contentID: [String] = []
        var nonCommercial: [String] = [], reserved: [String] = [], unknown: [String] = []
        for media in used {
            let provenance = media["provenance"]?.object ?? [:]
            let origin = provenance["origin"]?.string
            let terms = media["license"].flatMap(LicenseTerms.init(json:))
            if origin == "ai" { ai.append(media.id) }
            if let line = creditLine(media, terms: terms, provenance: provenance) { lines.append(line) }
            if claimable(media, terms: terms, origin: origin) {
                contentID.append("\(name(of: media)): stock or downloaded music can be claimed through Content ID; "
                    + "keep its licence page for disputes.")
            }
            switch flag(terms, origin: origin) {
            case .reserved?: reserved.append(media.id)
            case .nonCommercial?: nonCommercial.append(media.id)
            case .unknown?: unknown.append(media.id)
            case nil: break
            }
        }
        let disclosures = ai.isEmpty ? [] : platforms.compactMap { platform in
            platform.facts["disclosure"]?.value.string.map { Disclosure(platform: platform.id, rule: $0) }
        }
        return ProjectCredits(
            lines: lines, aiMedia: ai, aiPictureShare: aiPictureShare(project, ai: Set(ai)), disclosures: disclosures,
            contentIDNotes: contentID, nonCommercial: nonCommercial, allRightsReserved: reserved, unknown: unknown)
    }

    private enum Flag { case reserved, nonCommercial, unknown }

    /// Own, BashCut's and AI media without a licence are not unknown: there is no one else's terms to read.
    private static func flag(_ terms: LicenseTerms?, origin: String?) -> Flag? {
        switch terms?.id {
        case .allRightsReserved?: origin == "own" ? nil : .reserved
        case .ccByNc?, .ccByNcSa?, .ccByNcNd?: .nonCommercial
        case .custom?, .unknown?: .unknown
        case nil: origin == "stock" ? .unknown : nil
        default: nil
        }
    }

    /// Music from someone else: stock, or with a licence and not made here or by AI.
    private static func claimable(_ media: Media, terms: LicenseTerms?, origin: String?) -> Bool {
        media.kind == "audio" && (origin == "stock" || (terms != nil && origin != "own" && origin != "ai"))
    }

    private static func name(of media: Media) -> String {
        URL(fileURLWithPath: media.path).deletingPathExtension().lastPathComponent
    }

    private static func creditLine(_ media: Media, terms: LicenseTerms?, provenance: [String: JSONValue]) -> Line? {
        let required = terms?.facts.attributionRequired == true
        if let attribution = terms?.attribution { return Line(media: media.id, text: attribution, required: required) }
        let author = provenance["author"]?.string
        guard required || author != nil else { return nil }
        var parts = ["“\(name(of: media))”" + (author.map { " by \($0)" } ?? "")]
        if let terms { parts.append(terms.displayName) }
        if let url = provenance["sourceUrl"]?.string ?? terms?.url { parts.append(url) }
        return Line(media: media.id, text: parts.joined(separator: " — "), required: required)
    }

    /// The share of frames whose topmost visible picture (video or image media) is AI-made.
    private static func aiPictureShare(_ project: Project, ai: Set<String>) -> Double {
        guard !ai.isEmpty, project.duration > 0 else { return 0 }
        let byID = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // Tracks are back to front: the last visual track with an item at a frame is on top.
        let visual = project.tracks.filter { $0.kind == "video" && !$0.isHidden && !$0.isAdjustment }
        var aiFrames = 0
        for frame in 0..<project.duration {
            let top = visual.reversed().lazy.compactMap { track in
                track.items.first { $0.at <= frame && frame < $0.end && $0.mediaID.flatMap { byID[$0] } != nil }
            }.first
            if let media = top?.mediaID, ai.contains(media) { aiFrames += 1 }
        }
        return Double(aiFrames) / Double(project.duration)
    }
}
