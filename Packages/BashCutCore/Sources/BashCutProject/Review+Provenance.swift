import CryptoKit
import Foundation

/// What a derived result was made from (P2-G6), so review can say when the source changed after it was made.
/// - Voice items keep `voice.textHash`, the hash of the text the take was synthesized from.
/// - Captions from a transcript and the beat grid keep `generatedBy.sourceKey`: the media file's content key
///   (`mediaNamespace`) when they were made. The app passes the current keys in `ReviewContext.mediaKeys`.
public enum SourceHash {
    /// The namespace of media content keys kept as `generatedBy.sourceKey`.
    public static let mediaNamespace = "media-source-v1"

    /// SHA-256 of the text as UTF-8, the first 12 bytes as hex.
    public static func text(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

extension Project {
    /// Media whose content key review needs: what captions and the beat grid were made from.
    public var sourceKeyedMedia: Set<String> {
        var ids = Set(tracks.flatMap(\.items).compactMap { item in
            item["generatedBy"]?.object["sourceKey"] == nil ? nil : item["captionMedia"]?.string
        })
        if let grid = self["beatGrid"]?.object, grid["generatedBy"]?.object["sourceKey"] != nil,
            let media = grid["media"]?.string
        {
            ids.insert(media)
        }
        return ids
    }
}

extension TimelineReview {
    /// Info issues for results whose source changed after they were made (P2-G6): a voice take whose text was
    /// edited, captions or a beat grid whose media file was replaced or edited.
    static func provenanceIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        var issues: [ReviewIssue] = []
        for item in project.tracks.flatMap(\.items) {
            guard let voice = item["voice"]?.object, let made = voice["textHash"]?.string,
                let text = voice["text"]?.string, SourceHash.text(text) != made
            else { continue }
            issues.append(ReviewIssue(
                id: "voice-text-changed-" + item.id, title: "The voice text changed after the take was made",
                detail: "The take says the text it was synthesized from, not “\(text.prefix(80))”.", frame: item.at,
                endFrame: item.end, severity: .info,
                fix: ReviewFix(command: "voice.speak", arguments: ["replace": .string(item.id)],
                               hint: "Speak the new text into this item, or restore the text the take says.")))
        }
        var captionMedia: [String: Int] = [:]
        for item in project.tracks.flatMap(\.items) {
            guard let media = item["captionMedia"]?.string, let made = item["generatedBy"]?.object["sourceKey"]?.string,
                let current = context.mediaKeys[media], current != made
            else { continue }
            captionMedia[media] = min(captionMedia[media] ?? item.at, item.at)
        }
        for (media, frame) in captionMedia.sorted(by: { $0.key < $1.key }) {
            issues.append(ReviewIssue(
                id: "captions-source-changed-" + media, title: "Captions were made from an earlier version of the media",
                detail: "The file of \(media) changed after its captions were transcribed.", frame: frame,
                severity: .info,
                fix: ReviewFix(command: "captions.generate", arguments: ["media": .string(media), "replace": .bool(true)],
                               hint: "Transcribe the media again and replace its captions.")))
        }
        if let grid = project["beatGrid"]?.object, let media = grid["media"]?.string,
            let made = grid["generatedBy"]?.object["sourceKey"]?.string, let current = context.mediaKeys[media],
            current != made
        {
            issues.append(ReviewIssue(
                id: "beats-source-changed-" + media, title: "The beat grid was made from an earlier version of the music",
                detail: "The file of \(media) changed after its beats were detected.", frame: 0, severity: .info,
                fix: ReviewFix(command: "beats.detect", arguments: ["media": .string(media)],
                               hint: "Detect the beats again.")))
        }
        return issues
    }
}
