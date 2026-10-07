import Foundation

extension ProjectSchema {
    /// `media.description` (P0-A4): shot facts in the closed vocabulary of `MediaDescription`.
    static var mediaDescriptionDefinitions: [String: JSONValue] {
        [
            "mediaDescription": object(
                "Shot facts written by an agent or the user (media.describe), in a closed vocabulary",
                required: ["shots"],
                properties: [
                    "shots": array("Shots in source order; they do not overlap", of: ref("describedShot"), minItems: 1,
                                   maxItems: MediaDescription.maximumShots),
                    "describedBy": string("Author that wrote it"), "describedAt": string("ISO 8601 time"),
                ]),
            "describedShot": object(
                "One described shot; at least one fact besides start and end", required: ["start", "end"],
                properties: [
                    "start": number("Source seconds", 0...10_000_000), "end": number("Source seconds", 0...10_000_000),
                    "size": enumeration("Shot size", MediaDescription.sizes),
                    "angle": enumeration("Camera angle", MediaDescription.angles),
                    "move": enumeration("Camera move", MediaDescription.moves),
                    "direction": enumeration("Where the subject moves on screen", MediaDescription.directions),
                    "subjects": array("What is in the shot", of: string("Subject", minLength: 1, maxLength: 60),
                                      maxItems: 12),
                    "people": integer("People in frame", minimum: 0, maximum: 1_000),
                    "onScreenText": boolean("Readable text in the picture"),
                    "confidence": number("How sure the describer is", 0...1),
                    "bestMoment": number("Source seconds of the best moment inside the shot", 0...10_000_000),
                    "looked": array("Source seconds of the frames looked at", of: number("Seconds", 0...10_000_000),
                                    maxItems: 50),
                    "note": string("Free note", maxLength: 300),
                ]),
        ]
    }
}
