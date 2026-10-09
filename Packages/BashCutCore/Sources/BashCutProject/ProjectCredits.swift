import Foundation

/// The rights facts of what a finished edit plays (P2-H9): per used media its licence and provenance as stored, the
/// share of the edit where it is the picture on top, and the share of AI picture. Raw facts only: credit wording,
/// disclosure and what a use allows are the agent's (the rights skill), never core's.
public struct ProjectCredits: Sendable, Equatable {
    public struct Entry: Sendable, Equatable {
        public let media: String
        public let name: String
        public let kind: String
        public let license: JSONValue?
        public let provenance: JSONValue?
        /// Frames where this media is the topmost visible picture.
        public let framesOnTop: Int
    }

    public let entries: [Entry]
    /// Media whose provenance origin is `ai`.
    public let aiMedia: [String]
    /// Share (0–1) of the edit's length where the picture on top comes from AI media.
    public let aiPictureShare: Double
    public let frames: Int

    public var json: JSONValue {
        .object([
            "media": .array(entries.map { entry in
                var row: [String: JSONValue] = [
                    "media": .string(entry.media), "name": .string(entry.name), "kind": .string(entry.kind),
                    "framesOnTop": .integer(entry.framesOnTop),
                ]
                row["license"] = entry.license
                row["provenance"] = entry.provenance
                return .object(row)
            }),
            "frames": .integer(frames),
            "ai": .object([
                "media": .array(aiMedia.map(JSONValue.string)),
                "pictureShare": .number((aiPictureShare * 1_000).rounded() / 1_000),
            ]),
        ])
    }

    /// The rights facts of `project` as it plays now.
    public static func of(_ project: Project) -> ProjectCredits {
        let played = project.tracks.filter { !$0.isHidden }.flatMap(\.items).compactMap(\.mediaID)
        let byID = Dictionary(project.media.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let used = played.reduce(into: [Media]()) { list, id in
            if let media = byID[id], !list.contains(where: { $0.id == id }) { list.append(media) }
        }
        let onTop = framesOnTop(project)
        let ai = used.filter { $0["provenance"]?.object["origin"]?.string == "ai" }.map(\.id)
        let aiFrames = ai.reduce(0) { $0 + (onTop[$1] ?? 0) }
        let entries = used.map { media in
            Entry(media: media.id, name: URL(fileURLWithPath: media.path).deletingPathExtension().lastPathComponent,
                  kind: media.kind, license: media["license"], provenance: media["provenance"],
                  framesOnTop: onTop[media.id] ?? 0)
        }
        return ProjectCredits(
            entries: entries, aiMedia: ai,
            aiPictureShare: project.duration > 0 ? Double(aiFrames) / Double(project.duration) : 0, frames: project.duration)
    }

    /// Per media, the frames where it is the topmost visible picture (video or image media).
    private static func framesOnTop(_ project: Project) -> [String: Int] {
        let ids = Set(project.media.map(\.id))
        // Tracks are back to front: the last visual track with an item at a frame is on top.
        let visual = project.tracks.filter { $0.kind == "video" && !$0.isHidden && !$0.isAdjustment }
        var counts: [String: Int] = [:]
        for frame in 0..<max(0, project.duration) {
            let top = visual.reversed().lazy.compactMap { track in
                track.items.first { $0.at <= frame && frame < $0.end && $0.mediaID.map(ids.contains) == true }
            }.first
            if let media = top?.mediaID { counts[media, default: 0] += 1 }
        }
        return counts
    }
}
