import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation

extension ProjectDocument {
    static let convertMethod = "media.convert"

    /// Queues a decodable copy of `media`, whose video this Mac cannot decode (AV1, VP9), as a `media.convert` job:
    /// ffmpeg writes H.264 to `media/converted/<id>.mov` and the media is pointed at it when it lands, keeping the
    /// original's path in `originalPath`. Returns the proxy-style status: `converting` with the job, or `unsupported`
    /// with a reason when there is no ffmpeg to convert with. A transcript of the original is carried over to the copy.
    func requestConversion(of media: Media, source: URL, codec: String, root: URL, author: Author) -> [String: JSONValue] {
        var result: [String: JSONValue] = ["codec": .string(codec)]
        let label = URL(fileURLWithPath: media.path).lastPathComponent
        if let running = jobs.jobs.first(where: { $0.method == Self.convertMethod && $0.isActive && $0.detail == label }) {
            result["status"] = .string("converting")
            result["job"] = .string(running.id)
            return result
        }
        guard let destination = MediaConverter.destination(for: media, root: root),
            let converter = MediaConverter.locate(in: [agents.toolsDirectory])
        else {
            result["status"] = .string("unsupported")
            result["reason"] = .string(
                "This Mac cannot decode \(codec) video and BashCut converts it with ffmpeg, which is not installed: "
                    + "install it (brew install ffmpeg), then run media proxy \(media.id)")
            return result
        }
        let mediaID = media.id
        let job = jobs.start(Self.convertMethod, author: author, detail: label, work: { reporter in
            try await converter.convert(from: source, to: destination, progress: reporter.progressHandler())
            // A transcript made before the conversion stays with the media (the copy has the same sound and times).
            do {
                try MediaConverter.carryTranscript(from: source, to: destination, projectRoot: root)
            } catch {
                DebugLog.write("convert", "\(mediaID) transcript not carried over: \(error.localizedDescription)")
            }
            return .object(["media": .string(mediaID), "path": .string(destination.path)])
        }, finished: { [weak self] outcome in
            guard let self, case .success = outcome else { return }
            useConvertedCopy(mediaID: mediaID, copy: destination, root: root, author: author)
        })
        DebugLog.write("convert", "\(media.id) \(codec) → \(destination.lastPathComponent) (job \(job))")
        result["status"] = .string("converting")
        result["job"] = .string(job)
        return result
    }

    /// Points media `mediaID` at its converted copy (one undo step), then queues a proxy if the copy needs one.
    private func useConvertedCopy(mediaID: String, copy: URL, root: URL, author: Author) {
        guard let index = project.media.firstIndex(where: { $0.id == mediaID }) else { return }
        var updated = project
        var media = updated.media[index]
        if media["originalPath"] == nil { media.fields["originalPath"] = .string(media.path) }
        media.fields["path"] = .string(Self.relativePath(copy, root: root))
        updated.media[index] = media
        do {
            try commit(.restore(updated), label: "Use converted video", author: author)
            let original = URL(fileURLWithPath: media["originalPath"]?.string ?? media.path).lastPathComponent
            message = String(localized: "Converted \(original) so this Mac can play it")
            DebugLog.write("convert", "\(mediaID) now reads \(media.path)")
            requestProxiesAfterImport([mediaID], author: author)
        } catch {
            DebugLog.write("convert", "\(mediaID) not relinked: \(error.localizedDescription)")
            message = error.localizedDescription
        }
    }
}
