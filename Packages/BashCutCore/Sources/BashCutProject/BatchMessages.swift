import Foundation

/// The batch's own messages. Throw sites word them through these keys, in English for agents (CLI and MCP results);
/// the batch window matches a message back to its key to translate it (`BatchMessage` in the app), so a key is both
/// the English text and the Localizable.xcstrings key. `%@` marks the parts that vary.
public enum BatchMessages {
    public static let noInputs = "Give at least one input"
    public static let noSteps = "Give at least one step"
    public static let presetNameLetters = "A preset needs a name with letters or digits"
    public static let presetName = "A preset needs a name"
    public static let presetSteps = "A preset needs at least one step"
    public static let outputNameApart = "outputName needs {name} or {index} so each item's files stay apart"
    public static let outputNameToken = "outputName has an unknown {%@}; use %@"
    public static let concurrency = "concurrency must be 1…%@"
    public static let emptyOutput = "template outputs has an empty preset \"%@\""
    public static let unknownOutput = "template outputs: unknown export preset %@; use %@"
    public static let inputMissing = "Input %@ does not exist"
    public static let inputRelative = "Input %@ is relative: give absolute paths or base"
    public static let projectsFolderRelative = "projectsFolder %@ is relative: give an absolute path or base"
    public static let relativePath =
        "%@ is a relative path with no folder to resolve it against: choose it again, or save the preset again from its pipeline file"
    public static let inputNotFolder = "Input %@ is not a folder"
    public static let inputFolder = "Input %@ is a folder"
    public static let noProject = "No project at %@"
    public static let noMedia = "No video, audio, image or project in %@"
    public static let noPresetSaved = "No batch preset \"%@\"; saved: %@"
    public static let noPreset = "No batch preset \"%@\""
    public static let exportNeedsPresets = "Step %@ (%@) needs params.presets or template outputs"
    public static let exportUnknownPreset = "Step %@ (%@): unknown export preset %@"
    public static let unknownAction =
        "Step %@ (%@): no command or installed plugin action has this ID (plugins actions lists plugin actions)"
    public static let approvalExport =
        "Step %@ (%@) needs the user's approval each time, so it cannot run in a batch; use the export step instead"
    public static let approval = "Step %@ (%@) needs the user's approval each time, so it cannot run in a batch"
    public static let opensProjects = "Step %@ (%@) cannot run in a batch: the runner opens each item's project itself"
    public static let stepFailed = "Step %@ (%@): %@"
    public static let stoppedAfterFailure = "Stopped after a failed item (onFailure stop)"
    public static let openFailed = "Could not open its project: %@"
    public static let projectChanged = "The open project changed during the batch"
    public static let noProjectOpened = "No project opened"
    public static let jobDropped = "Its job %@ was dropped"
    public static let jobFailed = "The job failed"

    /// Every message, most specific first: the generic `stepFailed` comes after the step messages it would swallow.
    public static let all: [String] = [
        noInputs, noSteps, presetNameLetters, presetName, presetSteps, outputNameApart, outputNameToken, concurrency,
        emptyOutput, unknownOutput, inputMissing, inputRelative, projectsFolderRelative, relativePath, inputNotFolder,
        inputFolder, noProject, noMedia, noPresetSaved, noPreset, exportNeedsPresets, exportUnknownPreset, unknownAction,
        approvalExport, approval, opensProjects, stepFailed, stoppedAfterFailure, openFailed, projectChanged, noProjectOpened, jobDropped, jobFailed,
    ]

    /// `key` with its `%@` filled by `parts` in order.
    public static func text(_ key: String, _ parts: CustomStringConvertible...) -> String { fill(key, parts) }

    /// A step's message: `key`'s first two parts are the step's number (from 1) and action.
    public static func step(_ key: String, _ index: Int, _ action: String, _ parts: CustomStringConvertible...) -> String {
        fill(key, [index + 1, action] + parts)
    }

    private static func fill(_ key: String, _ parts: [CustomStringConvertible]) -> String {
        var pieces = key.components(separatedBy: "%@")
        var result = pieces.removeFirst()
        for (index, piece) in pieces.enumerated() {
            result += (index < parts.count ? parts[index].description : "") + piece
        }
        return result
    }
}
