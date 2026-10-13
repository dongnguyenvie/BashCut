import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// Placeholders for blocks being made (#534), derived from the commands that start the jobs: the track and range
/// they already name (a voiceover take placed with choose or replacing an item, captions over the clips of their
/// media, a plan graphic's span) or the media they work on. The agent declares nothing; nothing is saved or exported.
extension ProjectDocument {
    /// Speech rate used to size a voiceover placeholder before its take exists.
    static let placeholderWordsPerSecond = 2.6

    /// Tracks a capability job's placeholder, when the command knows where its result lands; Retry runs `work` again.
    func trackPlaceholder(
        _ job: String, method: String, author: Author, arguments: CommandArguments?,
        work: @escaping @MainActor (ProjectDocument) async throws -> JSONValue
    ) {
        guard let arguments, let target = placeholderTarget(method, arguments) else { return }
        activity.placeholders.track(job, target) { [weak self] in
            guard let self else { return nil }
            return try await startCapabilityJob(method, author: author, work: work).object["job"]?.string
        }
    }

    /// Where `method` puts its result, from its arguments and the edit as it is.
    func placeholderTarget(_ method: String, _ arguments: CommandArguments) -> PlaceholderTarget? {
        switch method {
        case "voice.speak": return voiceoverTarget(arguments)
        case "captions.generate":
            guard let media = arguments.optionalString("media") else { return nil }
            let label = project.media.first { $0.id == media }?.fileName ?? media
            let items = project.tracks.flatMap(\.items).filter { $0.mediaID == media }
            guard let start = items.map(\.at).min(), let end = items.map(\.end).max(),
                let track = project.tracks.first(where: { $0.role == TrackRole.captions })
            else { return PlaceholderTarget(kind: .captions, label: label, mediaIDs: [media]) }
            return PlaceholderTarget(kind: .captions, label: label, trackID: track.id, frames: start..<end, mediaIDs: [media])
        case "media.transcribe":
            let ids = arguments.optionalString("media").map { [$0] } ?? project.media.filter { !$0.isImage }.map(\.id)
            return ids.isEmpty ? nil : PlaceholderTarget(kind: .captions, label: String(localized: "Transcript"), mediaIDs: ids)
        default: return nil
        }
    }

    private func voiceoverTarget(_ arguments: CommandArguments) -> PlaceholderTarget? {
        let text = arguments.optionalString("text") ?? ""
        let label = String(text.prefix(40))
        if let id = arguments.optionalString("replace"),
            let track = project.tracks.first(where: { $0.items.contains { $0.id == id } }),
            let item = track.items.first(where: { $0.id == id })
        {
            return PlaceholderTarget(kind: .voiceover, label: label, trackID: track.id, frames: item.at..<item.end)
        }
        guard arguments.optionalInt("choose") != nil,
            let track = project.tracks.first(where: { $0.role == TrackRole.voiceover && $0.kind == "audio" })
        else { return PlaceholderTarget(kind: .voiceover, label: label) }
        let words = Double(max(1, text.split(whereSeparator: \.isWhitespace).count))
        let frames = Int((max(1, words / Self.placeholderWordsPerSecond) * project.fps.value).rounded())
        let start = arguments.optionalInt("atFrame") ?? playhead
        return PlaceholderTarget(kind: .voiceover, label: label, trackID: track.id, frames: start..<(start + frames))
    }

    /// A `graphics.render` call (`plugins invoke`): the plan.cut graphic it renders, matched by its render name or
    /// composition folder, shows at the span the plan gives it; any other render shows as a library tile.
    func trackGraphicPlaceholder(
        _ job: String, capability: String, params: [String: JSONValue], retry: @escaping WorkPlaceholders.Retry
    ) {
        guard capability == "graphics.render" else { return }
        let composition = params["composition"]?.string.map { URL(fileURLWithPath: $0).lastPathComponent }
        let name = params["name"]?.string
        var target = PlaceholderTarget(kind: .graphic, label: name ?? composition ?? String(localized: "Graphic"))
        let rows = project["plan"]?.object["cut"]?.object["graphics"]?.array ?? []
        let match = rows.first { row in
            let render = row.object["render"]?.object ?? [:]
            let folder = render["composition"]?.string.map { URL(fileURLWithPath: $0).lastPathComponent }
            return (name != nil && render["name"]?.string == name) || (composition != nil && folder == composition)
                || (row.object["id"]?.string).map { id in name?.contains(id) == true } == true
        }
        if let match, let id = match.object["id"]?.string, let plan = project["plan"]?.object["cut"],
            let spec = try? PlanCut.decode(plan), let span = PlanCut.graphicSpans(spec, in: project)[id]
        {
            let role = match.object["track"]?.string == "main" ? TrackRole.main : TrackRole.overlay
            target.trackID = project.tracks.first { $0.role == role }?.id
            target.frames = span
        }
        activity.placeholders.track(job, target, retry: retry)
    }

    /// Jump from a run panel step to the items it changed: selects them, moves the playhead to the first, scrolls
    /// the timeline there and flashes them (Show Changes' Jump, #534).
    func jumpToAgentItems(_ ids: [String]) {
        let items = project.tracks.flatMap { track in track.items.filter { ids.contains($0.id) }.map { (track, $0) } }
        guard let (track, first) = items.min(by: { $0.1.at < $1.1.at }) else {
            message = String(localized: "Those items are no longer on the timeline")
            return
        }
        select(items.map(\.1.id), primary: first.id)
        selectedTrackID = track.id
        preview.seek(first.at)
        ui.timelineReveal = TimelineReveal(frame: first.at)
        activity.flash(items.map(\.1.id))
    }
}
