import Foundation

/// Decoding `plan.cut` voiceover lines and graphics.
extension PlanCut {
    static func decodeLine(_ row: [String: JSONValue], id: String) throws -> Line {
        guard let text = row["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw ProjectError.invalid("Line \(id): give text")
        }
        let at = row["at"]?.double, pause = row["pause"]?.double ?? 0
        if let at, at < 0 { throw ProjectError.invalid("Line \(id): at must be 0 or more") }
        guard (0...30).contains(pause) else { throw ProjectError.invalid("Line \(id): pause 0…30 seconds") }
        return Line(
            id: id, text: text, caption: row["caption"]?.string.flatMap { $0.isEmpty ? nil : $0 }, take: row["take"]?.string,
            section: row["section"]?.string, at: at, pause: pause, volumeDb: row["volumeDb"]?.double)
    }

    static func decodeGraphic(
        _ row: [String: JSONValue], id: String, entries: [String], sections: Set<String>
    ) throws -> Graphic {
        let on = row["on"]?.string, section = row["section"]?.string, at = row["at"]?.double
        guard [on != nil, section != nil, at != nil].filter({ $0 }).count == 1 else {
            throw ProjectError.invalid("Graphic \(id): give one of on (a clip, line, title or graphic ID), section or at (seconds)")
        }
        if let on, on == id || !entries.contains(on) { throw ProjectError.invalid("Graphic \(id): no entry \(on)") }
        if let section, !sections.contains(section) { throw ProjectError.invalid("Graphic \(id): no clip or line is in section \(section)") }
        if let at, at < 0 { throw ProjectError.invalid("Graphic \(id): at must be 0 or more") }
        let seconds = row["seconds"]?.double, until = row["until"]?.string
        if let seconds, seconds <= 0 { throw ProjectError.invalid("Graphic \(id): seconds must be above 0") }
        if seconds != nil, until != nil { throw ProjectError.invalid("Graphic \(id): give seconds or until, not both") }
        if let until, !entries.contains(until) { throw ProjectError.invalid("Graphic \(id): no entry \(until) to run until") }
        if at != nil, seconds == nil, until == nil { throw ProjectError.invalid("Graphic \(id): give seconds or until with at") }
        let track = row["track"]?.string ?? "overlay"
        guard ["overlay", "main"].contains(track) else { throw ProjectError.invalid("Graphic \(id): track is overlay or main") }
        let from = row["from"]?.double ?? 0
        guard from >= 0 else { throw ProjectError.invalid("Graphic \(id): from must be 0 or more") }
        return Graphic(
            id: id, media: row["media"]?.string, on: on, section: section, at: at, offset: row["offset"]?.double ?? 0,
            seconds: seconds, until: until, main: track == "main", from: from)
    }

    static func decodeSound(
        _ row: [String: JSONValue], id: String, entries: [String], sections: Set<String>
    ) throws -> Sound {
        guard let media = row["media"]?.string, !media.isEmpty else { throw ProjectError.invalid("Sound \(id): give media") }
        let on = row["on"]?.string, section = row["section"]?.string, at = row["at"]?.double
        guard [on != nil, section != nil, at != nil].filter({ $0 }).count == 1 else {
            throw ProjectError.invalid("Sound \(id): give one of on (a clip or title ID), section or at (seconds)")
        }
        if let on, !entries.contains(on) { throw ProjectError.invalid("Sound \(id): no clip or title \(on)") }
        if let section, !sections.contains(section) { throw ProjectError.invalid("Sound \(id): no clip is in section \(section)") }
        if let at, at < 0 { throw ProjectError.invalid("Sound \(id): at must be 0 or more") }
        let seconds = row["seconds"]?.double
        if let seconds, seconds <= 0 { throw ProjectError.invalid("Sound \(id): seconds must be above 0") }
        return Sound(
            id: id, media: media, on: on, section: section, at: at, offset: row["offset"]?.double ?? 0, seconds: seconds,
            volumeDb: row["volumeDb"]?.double)
    }
}
