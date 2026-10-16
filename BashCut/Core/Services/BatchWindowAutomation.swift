import BashCutProject
import Foundation

/// An answer to the batch window's dialog (`ui respond --dialog sheet:batch <option>`), so an agent builds and runs a
/// pipeline in the window as the user does. Numbers are 1-based, as `ui dialog` lists the steps and the queue.
public enum BatchWindowOption: Equatable, Sendable {
    case addInputs, savePreset, run, cancel, close
    /// A step from `BatchStepCatalog` ("＋ Add step"), by action ID.
    case addStep(String)
    case removeStep(Int)
    case moveStep(Int, up: Bool)
    /// A saved preset (Presets menu), by name.
    case loadPreset(String)
    case openItem(Int)
    case revealItem(Int)

    public init?(_ id: String) {
        if let fixed = Self.fixed[id] {
            self = fixed
        } else if let parsed = Self.parsers.lazy.compactMap({ $0(id) }).first {
            self = parsed
        } else {
            return nil
        }
    }

    private static let fixed: [String: BatchWindowOption] = [
        "add-inputs": .addInputs, "save-preset": .savePreset, "run": .run, "cancel": .cancel, "close": .close,
    ]

    private static let parsers: [@Sendable (String) -> BatchWindowOption?] = [
        { value($0, "add-step:").map { .addStep($0) } },
        { value($0, "load-preset:").map { .loadPreset($0) } },
        { id in
            let parts = value(id, "move-step-")?.split(separator: "-") ?? []
            guard parts.count == 2, let number = Int(parts[0]), number > 0, ["up", "down"].contains(parts[1]) else { return nil }
            return .moveStep(number, up: parts[1] == "up")
        },
        { number($0, "remove-step-").map { .removeStep($0) } },
        { number($0, "open-").map { .openItem($0) } },
        { number($0, "reveal-").map { .revealItem($0) } },
    ]

    public var id: String {
        switch self {
        case .addInputs: "add-inputs"
        case .savePreset: "save-preset"
        case .run: "run"
        case .cancel: "cancel"
        case .close: "close"
        case .addStep(let action): "add-step:" + action
        case .removeStep(let number): "remove-step-\(number)"
        case .moveStep(let number, let up): "move-step-\(number)-" + (up ? "up" : "down")
        case .loadPreset(let name): "load-preset:" + name
        case .openItem(let number): "open-\(number)"
        case .revealItem(let number): "reveal-\(number)"
        }
    }

    /// The pipeline-editing options for `steps` steps and the saved `presets`: Add step for every catalog entry,
    /// Remove and Move for each step (no Move past either end), Load for each preset.
    public static func editing(steps: Int, presets: [String]) -> [BatchWindowOption] {
        var options = BatchStepCatalog.entries.map { BatchWindowOption.addStep($0.action) }
        for number in stride(from: 1, through: steps, by: 1) {
            options.append(.removeStep(number))
            if number > 1 { options.append(.moveStep(number, up: true)) }
            if number < steps { options.append(.moveStep(number, up: false)) }
        }
        return options + presets.map { .loadPreset($0) }
    }

    private static func value(_ id: String, _ prefix: String) -> String? {
        guard id.hasPrefix(prefix), id.count > prefix.count else { return nil }
        return String(id.dropFirst(prefix.count))
    }

    private static func number(_ id: String, _ prefix: String) -> Int? {
        value(id, prefix).flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
    }
}

/// The batch's own messages in the user's language. The pipeline checks and the runner word them in English, which
/// agents read in CLI and MCP results; the batch window and its queue show them through here. Each pattern is a
/// Localizable.xcstrings key, its `%@` the parts that vary (themselves translated when they are batch messages too,
/// as the failure inside "Step 2 (export): …").
public enum BatchMessage {
    /// Most specific first: the generic "Step %@ (%@): %@" comes after the step messages it would swallow.
    public static let patterns: [String] = [
        "Give at least one input",
        "Give at least one step",
        "A preset needs a name with letters or digits",
        "A preset needs a name",
        "A preset needs at least one step",
        "outputName needs {name} or {index} so each item's files stay apart",
        "outputName has an unknown {%@}; use %@",
        "concurrency must be 1…%@",
        "template outputs has an empty preset \"%@\"",
        "template outputs: unknown export preset %@; use %@",
        "Input %@ does not exist",
        "Input %@ is not a folder",
        "Input %@ is a folder",
        "No project at %@",
        "No video, audio, image or project in %@",
        "No batch preset \"%@\"; saved: %@",
        "No batch preset \"%@\"",
        "Step %@ (%@) needs params.presets or template outputs",
        "Step %@ (%@): unknown export preset %@",
        "Step %@ (%@): no command or installed plugin action has this ID (plugins actions lists plugin actions)",
        "Step %@ (%@) needs the user's approval each time, so it cannot run in a batch; use the export step instead",
        "Step %@ (%@) needs the user's approval each time, so it cannot run in a batch",
        "Step %@ (%@) cannot run in a batch: the runner opens each item's project itself",
        "Step %@ (%@): %@",
        "Stopped after a failed item (onFailure stop)",
        "Could not open its project: %@",
        "The open project changed during the batch",
        "No project opened",
        "Its job %@ was dropped",
        "The job failed",
    ]

    private static let expressions: [(key: String, regex: NSRegularExpression)] = patterns.map { key in
        let parts = key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:))
        let pattern = "^" + parts.joined(separator: "(.+?)") + "$"
        // swiftlint:disable:next force_try
        return (key, try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]))
    }

    /// The pattern `message` fits and its varying parts; nil for a message the batch does not word itself.
    public static func match(_ message: String) -> (key: String, arguments: [String])? {
        let range = NSRange(message.startIndex..., in: message)
        for (key, regex) in expressions {
            guard let found = regex.firstMatch(in: message, range: range) else { continue }
            let arguments = (1..<found.numberOfRanges).compactMap { Range(found.range(at: $0), in: message) }
                .map { String(message[$0]) }
            return (key, arguments)
        }
        return nil
    }

    /// `message` in the app's language; unchanged when it is not a batch message or has no translation.
    public static func localized(_ message: String, bundle: Bundle = .main) -> String {
        guard let (key, arguments) = match(message) else { return message }
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        let translated: [any CVarArg] = arguments.map { localized($0, bundle: bundle) as NSString }
        return String(format: format, arguments: translated)
    }
}
