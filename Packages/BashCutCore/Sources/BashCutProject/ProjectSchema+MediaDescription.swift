import Foundation

extension ProjectSchema {
    /// `media.description` (P0-A4): shot facts as open labels; the `MediaDescription` lists are suggestions.
    static var mediaDescriptionDefinitions: [String: JSONValue] {
        [
            "mediaDescription": object(
                "Shot facts written by an agent or the user (media.describe); open labels, other fields kept",
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
                    "size": string("Shot size, e.g. " + MediaDescription.sizes.joined(separator: ", "), maxLength: 60),
                    "angle": string("Camera angle, e.g. " + MediaDescription.angles.joined(separator: ", "), maxLength: 60),
                    "move": string("Camera move, e.g. " + MediaDescription.moves.joined(separator: ", "), maxLength: 60),
                    "direction": string("Where the subject moves on screen, e.g. " + MediaDescription.directions.joined(separator: ", "),
                                        maxLength: 60),
                    "subjects": array("What is in the shot", of: string("Subject", minLength: 1, maxLength: 60),
                                      maxItems: 12),
                    "people": integer("People in frame", minimum: 0, maximum: 1_000),
                    "onScreenText": boolean("Readable text in the picture"),
                    "confidence": number("How sure the describer is", 0...1),
                    "bestMoment": number("Source seconds of the best moment inside the shot", 0...10_000_000),
                    "looked": array("Source seconds of the frames looked at", of: number("Seconds", 0...10_000_000),
                                    maxItems: 50),
                    "note": string("Free note", maxLength: 300),
                    "tags": array("Free labels", of: string("Label", minLength: 1, maxLength: 60), maxItems: 50),
                ]),
        ]
    }

    /// A voiceover item's own text and where it came from (P0-C6), so it can be checked, re-taken in place and
    /// captioned from its script.
    static var voiceItemSchema: JSONValue {
        object(
            "Voiceover facts set by voice speak and voice check", required: [],
            properties: [
                "text": string("The text the take was synthesized from"), "language": string("Content language"),
                "provider": string("voice.synthesize provider ID"), "voice": string("provider/voice the rate store uses"),
                "textHash": string("Hash of the text the take says (SourceHash.text); review notes when text differs"),
                "words": array("Words heard in the take, in its seconds", of: object(
                    "A word", required: ["text", "start", "end"],
                    properties: [
                        "text": string("Word"), "start": number("Seconds", 0...86_400), "end": number("Seconds", 0...86_400),
                    ]), maxItems: 10_000),
            ])
    }
}
