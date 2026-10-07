import Foundation

/// Project-level settings: mix, what the project is made for (#441) and its review profile.
extension ProjectSchema {
    static var audioSchema: JSONValue {
        .object(fields(
            "Mix settings and the last loudness measurement", required: [],
            properties: [
                "targetLUFS": number("Normalization target", -30 ... -5),
                "normalizeEnabled": boolean("Two-pass normalization on export"),
                "mixGainDb": number("Master gain", -60...24),
                "measuredLUFS": number("Measured integrated loudness", -100...10),
                "truePeakDbTP": number("Measured true peak", -100...20),
                "loudnessRangeLU": number("Measured loudness range", 0...100),
                "measurementVerified": boolean("The final file was re-measured"),
            ]))
    }

    static var outputSchema: JSONValue {
        object(
            "What the project is made for (#441)", required: [],
            properties: [
                "presets": array(
                    "Export presets, first one primary: review checks every output's platform and the Export sheet "
                        + "starts with the first", of: enumeration("Export preset", OutputPresetName.all), maxItems: 8),
                "captions": .object([
                    "type": .string("object"),
                    "description": .string("Export preset → how that output carries captions (P1-F4)"),
                    "additionalProperties": object(
                        "Captions of one output", required: [],
                        properties: [
                            "mode": enumeration("Burned in, a sidecar file, both or none", OutputPackaging.captionModes),
                            "format": enumeration("Sidecar format", OutputPackaging.captionFormats),
                            "track": string("Caption layer ID; default the first caption layer"),
                        ]),
                ]),
                "targets": .object([
                    "type": .string("object"),
                    "description": .string(
                        "Export preset → {integratedLUFS, truePeakDbTP}: that export's loudness target instead of the "
                            + "platform's (P0-K2)"),
                    "additionalProperties": object(
                        "Loudness target", required: [],
                        properties: [
                            "integratedLUFS": number("LUFS", -30 ... -5), "truePeakDbTP": number("dBTP", -12...0),
                        ]),
                ]),
            ])
    }

    static let reviewSummaries: [String: String] = [
        "minShotSeconds": "Shots on Main shorter than this are flagged",
        "maxShotSeconds": "Shots on Main longer than this are flagged (with stillMotion, only those that barely move)",
        "maxStillSeconds": "Frozen picture longer than this is flagged",
        "hookSeconds": "Text or speech must start within this many seconds",
        "maxSilenceSeconds": "Dead air longer than this is flagged",
        "maxMusicGapSeconds": "A music bed stopping for longer than this is flagged",
        "voiceoverMarginSeconds": "Voiceover closer than this to tagged speech is flagged",
        "captionLineChars": "Caption lines longer than this many characters are flagged",
        "captionMaxLines": "Captions with more lines than this are flagged",
        "stillMotion": "Mean picture change under which a long shot counts as still (0–1)",
        "jumpCutChange": "Picture change across a hard cut under which it counts as a jump cut (0–1)",
        "blackMinSeconds": "Black picture at least this long is flagged",
        "loudnessToleranceLU": "Loudness further than this from the export's target is flagged",
        "minTextSize": "Text smaller than this share of the frame's short side is flagged",
        "minSpeechCoverage": "Tagged speech covering less than this share of the edit is flagged",
    ]

    static var reviewSchema: JSONValue {
        var properties: [String: JSONValue] = Dictionary(uniqueKeysWithValues: ReviewProfile.numberKeys.map { key, range in
            (key, number((reviewSummaries[key] ?? key) + "; unset: no check, or the measured value as info", range))
        })
        properties["credits"] = boolean(
            "Report credit lines, AI disclosure and licence flags in review and export results (P2-H9); off by default")
        properties["severities"] = .object([
            "type": .string("object"),
            "description": .string(
                "Check ID (or prefix before a hyphen, such as safe or shot-long; or a plugin provider ID ending in ':') → "
                    + "error, warning, info or off"),
            "additionalProperties": enumeration("Severity", ReviewProfile.severityValues),
        ])
        properties["platform"] = object(
            "Overrides of platform facts when an app changes its interface (#469)", required: [],
            properties: [
                "safeArea": object(
                    "Covered zones as fractions of the frame", required: [],
                    properties: Dictionary(uniqueKeysWithValues: ["top", "bottom", "sideWidth", "sideHeight", "margin"].map {
                        ($0, number("Fraction", 0...1))
                    })),
                "maxSeconds": number("Longest upload", 1...86_400),
            ])
        properties["disabledChecks"] = array("Plugin or provider IDs whose review checks do not run", of: string("ID"))
        properties["accepted"] = .object([
            "type": .string("object"),
            "description": .string("Issue ID → {reason, rev, author}: warnings and notes kept on purpose (P1-E2); never errors"),
            "additionalProperties": object(
                "Accepted issue", required: ["reason"],
                properties: ["reason": string("Why it stays"), "rev": integer("Revision", minimum: 0), "author": string("Author")]),
        ])
        properties["blockExport"] = array(
            "Issue ID prefixes (such as font, glyph, cut-in-word) that stop an export while open (P1-E1)", of: string("Prefix"))
        return object(
            "Review profile (#466): every editorial limit is the project's (a recipe skill sets them); core has none",
            required: [], properties: properties)
    }

    /// The brief and the edit plan (P1-D1, P1-D2); their shape is checked, their content is the agent's and user's.
    static var planSchemas: [String: JSONValue] {
        let field = object(
            "A brief field", required: ["value", "status"],
            properties: [
                "value": .object(["description": .string("Any JSON value")]),
                "status": enumeration("Who said it", ProjectPlan.statuses), "source": string("Where it came from"),
            ])
        var brief = Dictionary(uniqueKeysWithValues: ProjectPlan.briefFields.map { ($0, field) })
        brief["ideas"] = array("Ideas", of: .object(["type": .string("object")]), maxItems: 100)
        brief["references"] = array("Reference videos or notes", of: .object(["type": .string("object")]), maxItems: 100)
        let range = object(
            "A range", required: ["min", "max"],
            properties: ["min": number("Low", -1e9...1e9), "max": number("High", -1e9...1e9), "source": string("Source"),
                         "reason": string("Why")])
        return [
            "brief": object("What the edit is for (P1-D1)", required: [], properties: brief),
            "plan": object(
                "How the agent means to make it (P1-D2)", required: [],
                properties: [
                    "mode": enumeration("Mode", ProjectPlan.modes), "stage": string("Current stage"),
                    "options": array("Story options", of: .object(["type": .string("object")])),
                    "sections": array("Sections [{id, label, lengthSeconds {min, max}, reason, frozen}]",
                                      of: .object(["type": .string("object")]), maxItems: 500),
                    "shots": array("Shot rows [{id, purpose, section, size, move, mustShow, targetSeconds, source}]",
                                   of: .object(["type": .string("object")]), maxItems: 500),
                    "beats": array("Script beats [{id, section, text}]", of: .object(["type": .string("object")]), maxItems: 500),
                    "decisions": array("Decisions [{text}]", of: .object(["type": .string("object")]), maxItems: 500),
                    "ranges": .object([
                        "type": .string("object"), "description": .string("Review key → the range chosen"),
                        "additionalProperties": range,
                    ]),
                    "notes": string("Notes"),
                ]),
        ]
    }
}
