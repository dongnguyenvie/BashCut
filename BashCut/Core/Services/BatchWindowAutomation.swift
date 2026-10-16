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
