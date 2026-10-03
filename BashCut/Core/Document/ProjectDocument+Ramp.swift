import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation

/// Speed ramps (Inspector › Speed › Curve, the clip menu, `clip speed-curve`) and Reverse (`clip reverse`).
extension ProjectDocument {
    /// Gives a clip (and its linked sound) a speed ramp, or removes it with nil, as one undoable edit.
    @discardableResult
    func setClipSpeedCurve(
        _ curve: SpeedCurve?, item id: String? = nil, keepDuration: Bool = false, author: Author = .user,
        baseRevision: Int? = nil
    ) throws -> Int {
        guard let id = id ?? selectedID else { throw ProjectError.invalid("Select a clip to change its speed") }
        let label = curve == nil ? "Remove speed curve" : "Speed curve"
        return try commit(
            .setSpeedCurve(item: id, curve: curve, keepDuration: keepDuration), label: label, author: author,
            baseRevision: baseRevision)
    }

    /// The preset whose points match the clip's curve, if any.
    func speedCurvePreset(of item: Item) -> String? {
        guard let curve = item.speedCurve else { return nil }
        return SpeedCurve.presets.first { SpeedCurve.preset($0.id) == curve }?.id ?? "custom"
    }

    // MARK: Reverse

    /// Where a reversed copy of `media`'s frames `[sourceIn, sourceIn + frames)` goes: `<project>/reversed/`, named
    /// after the original file so the clip still reads as it.
    static func reversedPath(media: Media, sourceIn: Int, frames: Int) -> String {
        let stem = URL(fileURLWithPath: media.path).deletingPathExtension().lastPathComponent
        let safe = String(stem.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" }.prefix(60))
        return "reversed/\(safe.isEmpty ? media.id : safe)-reversed-\(sourceIn)-\(frames).mov"
    }

    /// Plays a clip (and its linked sound) backwards: renders a reversed copy of the source it uses, then points the
    /// clip at it. Reversing a reversed clip points it back at the original. Runs as a job; the edit is one undo step.
    func reverseClip(_ id: String? = nil, author: Author = .user) throws -> String {
        guard let root = fileURL?.deletingLastPathComponent() else { throw ProjectError.invalid("Save the project first") }
        guard let id = id ?? selectedID, let item = project.tracks.flatMap(\.items).first(where: { $0.id == id }),
            let media = project.media.first(where: { $0.id == item.mediaID })
        else { throw ProjectError.invalid("Select a clip with media to reverse") }
        guard item.fields["freezeFrame"] == nil else { throw ProjectError.invalid("A freeze frame cannot be reversed") }
        guard media.kind != "audio", media.kind != "image" else {
            throw ProjectError.invalid("Reverse works on video clips")
        }
        let consumed = max(1, Int((item.sourceSeconds(afterFrames: item.duration, fps: project.fps) * media.fps.value)
            .rounded(.up)))
        if let original = item.fields["reversed"]?.object, let originalID = original["media"]?.string,
            let originalIn = original["in"]?.int, let frames = original["frames"]?.int,
            project.media.contains(where: { $0.id == originalID })
        {
            // Back to the original: the reversed copy's frame r is original frame (in + frames - 1 - r).
            let back = max(originalIn, originalIn + frames - (item.sourceIn + consumed))
            try commit(
                .setSource(item: id, media: originalID, sourceIn: back, reversed: nil), label: "Reverse clip", author: author)
            return ""
        }
        let source = try MediaPathResolver.resolve(media.path, projectRoot: root, workspaceRoot: settings.workspace)
        let relative = Self.reversedPath(media: media, sourceIn: item.sourceIn, frames: consumed)
        let destination = root.appendingPathComponent(relative)
        let range = Double(item.sourceIn) / media.fps.value...Double(item.sourceIn + consumed) / media.fps.value
        let fps = media.fps
        let session = sessionID
        return jobs.start("clip.reverse", author: author, detail: URL(fileURLWithPath: media.path).lastPathComponent,
            work: { [weak self] reporter in
                let existing = self?.project.media.first { $0.path == relative }
                var reversedMedia = existing
                if existing == nil || !FileManager.default.fileExists(atPath: destination.path) {
                    reporter.detail("Reversing")
                    let output = try await MediaReverser.reverse(
                        source: source, range: range, to: destination, fps: fps.value,
                        progress: { value in Task { @MainActor in reporter.progress(value, detail: nil) } })
                    var fields = media.fields
                    fields["id"] = .string(existing?.id ?? UUID().uuidString)
                    fields["path"] = .string(relative)
                    fields["frames"] = .integer(output.frames)
                    fields["hasAudio"] = .bool(output.hasAudio)
                    fields["reverseOf"] = .string(media.id)
                    reversedMedia = Media(fields: fields)
                }
                guard let self, let reversedMedia else { throw CancellationError() }
                try self.ensureSession(session)
                let frames = reversedMedia.frames
                // The clip's last used frame becomes the copy's first.
                let start = max(0, frames - consumed)
                var operations: [EditOperation] = []
                if existing == nil { operations.append(.addMedia(reversedMedia)) }
                operations.append(.setSource(
                    item: id, media: reversedMedia.id, sourceIn: start,
                    reversed: .object(["media": .string(media.id), "in": .integer(item.sourceIn), "frames": .integer(consumed)])))
                let revision = try self.commit(
                    .group(label: "Reverse clip", author: author, ops: operations), label: "Reverse clip", author: author)
                return .object(["rev": .integer(revision), "item": .string(id), "media": .string(reversedMedia.id)])
            }, finished: { [weak self] outcome in
                guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
                self?.message = error.localizedDescription
            })
    }

    func registerRampCommands() {
        handleAuthored("clip.speed-curve") { document, arguments, author in
            let id = arguments.optionalString("item") ?? document.selectedID
            guard let id else { throw RPCFailure(-32602, "Give an item or select a clip first") }
            let curve: SpeedCurve?
            do { curve = try Self.curve(preset: arguments.optionalString("preset"), points: arguments.optionalString("points")) } catch {
                throw RPCFailure(-32602, error.localizedDescription)
            }
            let before = document.project.tracks.flatMap(\.items).first { $0.id == id }?.duration
            let revision = try document.setClipSpeedCurve(
                curve, item: id, keepDuration: arguments.bool("keepDuration"), author: author,
                baseRevision: try arguments.int("baseRev"))
            let item = document.project.tracks.flatMap(\.items).first { $0.id == id }
            return .object([
                "rev": .integer(revision), "item": .string(id), "speed": .number(item?.speed ?? 1),
                "duration": item.map { .integer($0.duration) } ?? .null, "curve": item?.speedCurve?.json ?? .null,
                "shortened": .bool(Self.shortened(before: before, after: item?.duration, keepDuration: arguments.bool("keepDuration"))),
            ])
        }
        handleAuthored("clip.reverse") { document, arguments, author in
            let id = arguments.optionalString("item") ?? document.selectedID
            let job = try document.reverseClip(id, author: author)
            if job.isEmpty { return .object(["rev": .integer(document.project.revision), "restored": .bool(true)]) }
            return .object(["job": .string(job), "state": .string("running")])
        }
    }

    /// A preset name ("none" removes the curve) or JSON points (`[[t, speed], …]` or `[{"t":…,"speed":…}, …]`).
    static func curve(preset: String?, points: String?) throws -> SpeedCurve? {
        if let points {
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(points.utf8)), case .array(let list) = value else {
                throw ProjectError.invalid("points must be a JSON array such as [[0,1],[0.5,3],[1,1]]")
            }
            let objects: [JSONValue] = list.map { point in
                if case .array(let pair) = point, pair.count == 2 { return .object(["t": pair[0], "speed": pair[1]]) }
                return point
            }
            return try SpeedCurve(json: .array(objects))
        }
        guard let preset, preset != "none" else { return nil }
        guard let curve = SpeedCurve.preset(preset) else {
            throw ProjectError.invalid("Unknown preset \(preset); use " + SpeedCurve.presets.map(\.id).joined(separator: ", "))
        }
        return curve
    }
}
