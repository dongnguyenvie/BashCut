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
                    "Export presets, first one primary: review checks its platform and the Export sheet starts with it",
                    of: enumeration("Export preset", OutputPresetName.all), maxItems: 8),
            ])
    }

    static var reviewSchema: JSONValue {
        object(
            "Review profile: pacing, hook and severities (a recipe skill sets them) and plugin checks turned off",
            required: [],
            properties: [
                "minShotSeconds": number("Shots shorter than this are flagged", 0.04...60),
                "maxShotSeconds": number("Still shots longer than this are flagged", 0.1...600),
                "maxStillSeconds": number("Frozen picture longer than this is flagged", 0.1...600),
                "hookSeconds": number("Text or speech must start within this many seconds", 0.5...30),
                "severities": .object([
                    "type": .string("object"),
                    "description": .string(
                        "Check ID (or prefix before a hyphen, such as safe or shot-long) → error, warning, info or off"),
                    "additionalProperties": enumeration("Severity", ReviewSeverity.allCases.map(\.rawValue) + ["off"]),
                ]),
                "disabledChecks": array("Plugin or provider IDs whose review checks do not run", of: string("ID")),
            ])
    }
}
