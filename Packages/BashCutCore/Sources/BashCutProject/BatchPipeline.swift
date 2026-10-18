import Foundation

/// A batch pipeline (P2-C1): the same steps run over many inputs, each input its own project (decision D4: a file
/// becomes a new project from `template`, a project input is that project). Plain JSON, so the agent can write one,
/// the CLI can run it (`batch run pipeline.json`) and the batch window can edit it. Unknown fields round-trip at
/// every level.
public struct BatchPipeline: Codable, Sendable, Equatable {
    public static let version = 1
    /// `outputName` tokens: the item's name (file name without extension, or project folder), the export preset, the
    /// item's 1-based position and the pipeline's name.
    public static let outputTokens = ["name", "preset", "index", "pipeline"]
    public static let defaultOutputName = "{name}-{preset}"
    public static let maximumConcurrency = 8

    public var name: String?
    public var inputs: [BatchInput]
    public var template: BatchTemplate
    public var steps: [BatchStep]
    public var onFailure: BatchFailurePolicy
    /// Items asked to run at once (1…8). The app runs every step against its one open project, so it runs items
    /// one at a time today and reports the value it used.
    public var concurrency: Int
    /// The export file name pattern, `{name}-{preset}` by default.
    public var outputName: String
    /// Parent folder of the projects made for file inputs; the projects folder when nil.
    public var projectsFolder: String?
    public var extra: [String: JSONValue]

    public init(
        name: String? = nil, inputs: [BatchInput], template: BatchTemplate = BatchTemplate(), steps: [BatchStep],
        onFailure: BatchFailurePolicy = .skipItem, concurrency: Int = 1, outputName: String = defaultOutputName,
        projectsFolder: String? = nil
    ) {
        self.name = name
        self.inputs = inputs
        self.template = template
        self.steps = steps
        self.onFailure = onFailure
        self.concurrency = concurrency
        self.outputName = outputName
        self.projectsFolder = projectsFolder
        extra = [:]
    }

    private static let known: Set<String> = [
        "version", "name", "inputs", "template", "steps", "onFailure", "concurrency", "outputName", "projectsFolder",
    ]

    /// Reads a pipeline, refusing a newer version and fields of the wrong type with the field's name.
    public init(json: JSONValue) throws {
        guard case .object(let fields) = json else { throw ProjectError.invalid("A pipeline is a JSON object") }
        if let version = fields["version"]?.int, version > Self.version {
            throw ProjectError.invalid("The pipeline is version \(version); this BashCut reads version \(Self.version)")
        }
        name = try Self.optionalString(fields["name"], "name")
        guard case .array(let inputs)? = fields["inputs"] else { throw ProjectError.invalid("inputs must be a list") }
        self.inputs = try inputs.enumerated().map { try BatchInput(json: $1, index: $0) }
        template = try fields["template"].map(BatchTemplate.init(json:)) ?? BatchTemplate()
        guard case .array(let steps)? = fields["steps"] else { throw ProjectError.invalid("steps must be a list") }
        self.steps = try steps.enumerated().map { try BatchStep(json: $1, index: $0) }
        let policy = try Self.optionalString(fields["onFailure"], "onFailure") ?? BatchFailurePolicy.skipItem.rawValue
        guard let onFailure = BatchFailurePolicy(rawValue: policy) else {
            throw ProjectError.invalid("onFailure must be skip or stop")
        }
        self.onFailure = onFailure
        switch fields["concurrency"] {
        case nil, .null?: concurrency = 1
        case .integer(let value)?: concurrency = value
        default: throw ProjectError.invalid("concurrency must be an integer")
        }
        outputName = try Self.optionalString(fields["outputName"], "outputName") ?? Self.defaultOutputName
        projectsFolder = try Self.optionalString(fields["projectsFolder"], "projectsFolder")
        extra = fields.filter { !Self.known.contains($0.key) }
    }

    public var json: JSONValue {
        var fields = extra
        fields["version"] = .integer(Self.version)
        fields["name"] = name.map(JSONValue.string)
        fields["inputs"] = .array(inputs.map(\.json))
        fields["template"] = template.json
        fields["steps"] = .array(steps.map(\.json))
        fields["onFailure"] = .string(onFailure.rawValue)
        fields["concurrency"] = .integer(concurrency)
        fields["outputName"] = .string(outputName)
        fields["projectsFolder"] = projectsFolder.map(JSONValue.string)
        return .object(fields)
    }

    public init(from decoder: any Decoder) throws { try self.init(json: JSONValue(from: decoder)) }
    public func encode(to encoder: any Encoder) throws { try json.encode(to: encoder) }

    /// Checks what does not need the app: at least one input and step, concurrency in range, a known `outputName`
    /// that keeps each item's files apart. Whether each step's action may run in a batch is the runner's check.
    public func validate() throws {
        guard !inputs.isEmpty else { throw ProjectError.invalid(BatchMessages.noInputs) }
        guard !steps.isEmpty else { throw ProjectError.invalid(BatchMessages.noSteps) }
        guard (1...Self.maximumConcurrency).contains(concurrency) else {
            throw ProjectError.invalid(BatchMessages.text(BatchMessages.concurrency, Self.maximumConcurrency))
        }
        let tokens = Self.tokens(in: outputName)
        if let unknown = tokens.first(where: { !Self.outputTokens.contains($0) }) {
            throw ProjectError.invalid(
                BatchMessages.text(BatchMessages.outputNameToken, unknown, Self.outputTokens.map { "{\($0)}" }.joined(separator: ", ")))
        }
        guard tokens.contains("name") || tokens.contains("index") else {
            throw ProjectError.invalid(BatchMessages.outputNameApart)
        }
        if let bad = template.outputs.first(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            throw ProjectError.invalid(BatchMessages.text(BatchMessages.emptyOutput, bad))
        }
        // Left relative, a path would resolve against the app's working folder (`/`): the batch window has no base.
        if let relative = ([projectsFolder].compactMap { $0 } + inputs.map(\.path)).first(where: Self.isRelative) {
            throw ProjectError.invalid(BatchMessages.text(BatchMessages.relativePath, relative))
        }
    }

    /// The pipeline with its relative input paths and `projectsFolder` made absolute against `base` (a pipeline
    /// file's folder), so it runs the same from the batch window or a preset; without `base` a relative path is refused.
    public func resolvingPaths(against base: URL?) throws -> BatchPipeline {
        var resolved = self
        func absolute(_ path: String, _ refusal: String) throws -> String {
            guard Self.isRelative(path) else { return path }
            guard let base else { throw ProjectError.invalid(BatchMessages.text(refusal, path)) }
            return base.appendingPathComponent(path).standardizedFileURL.path
        }
        for index in resolved.inputs.indices {
            resolved.inputs[index].path = try absolute(resolved.inputs[index].path, BatchMessages.inputRelative)
        }
        resolved.projectsFolder = try projectsFolder.map { try absolute($0, BatchMessages.projectsFolderRelative) }
        return resolved
    }

    /// Neither absolute nor from the home folder (`~`).
    static func isRelative(_ path: String) -> Bool { !path.hasPrefix("/") && !path.hasPrefix("~") }

    /// The export file name (no extension) of item `index` (0-based) for `preset`: `outputName` with its tokens
    /// filled; characters a file name cannot hold become dashes.
    public func outputFileName(item: String, index: Int, preset: String) -> String {
        let values = ["name": item, "preset": preset, "index": String(index + 1), "pipeline": name ?? "batch"]
        var text = outputName
        for (token, value) in values { text = text.replacingOccurrences(of: "{\(token)}", with: value) }
        let cleaned = String(text.map { "/:\\".contains($0) ? "-" : $0 }).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "item-\(index + 1)" : cleaned
    }

    static func tokens(in pattern: String) -> [String] {
        var tokens: [String] = []
        var rest = Substring(pattern)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            tokens.append(String(rest[rest.index(after: open)..<close]))
            rest = rest[rest.index(after: close)...]
        }
        return tokens
    }

    static func optionalString(_ value: JSONValue?, _ name: String) throws -> String? {
        switch value {
        case nil, .null?: return nil
        case .string(let text)?: return text.isEmpty ? nil : text
        default: throw ProjectError.invalid("\(name) must be a string")
        }
    }
}

/// What a failed step does to the batch: skip the rest of that item and go on, or stop the batch.
public enum BatchFailurePolicy: String, Codable, Sendable, CaseIterable {
    case skipItem = "skip"
    case stop
}

/// One input: a media file, a folder (its media files, and project folders directly inside it) or a project.
public struct BatchInput: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable { case file, folder, project }

    public var path: String
    /// Detected from the file system when nil.
    public var kind: Kind?
    public var extra: [String: JSONValue]

    public init(path: String, kind: Kind? = nil) {
        self.path = path
        self.kind = kind
        extra = [:]
    }

    /// A bare string is a path.
    init(json: JSONValue, index: Int) throws {
        if case .string(let path) = json {
            self.init(path: path)
            return
        }
        guard case .object(let fields) = json, let path = fields["path"]?.string, !path.isEmpty else {
            throw ProjectError.invalid("inputs[\(index)] must be a path or {path, kind}")
        }
        let kind = try BatchPipeline.optionalString(fields["kind"], "inputs[\(index)].kind")
        guard kind == nil || Kind(rawValue: kind ?? "") != nil else {
            throw ProjectError.invalid("inputs[\(index)].kind must be file, folder or project")
        }
        self.init(path: path, kind: kind.flatMap(Kind.init(rawValue:)))
        extra = fields.filter { $0.key != "path" && $0.key != "kind" }
    }

    var json: JSONValue {
        guard kind != nil || !extra.isEmpty else { return .string(path) }
        var fields = extra
        fields["path"] = .string(path)
        fields["kind"] = kind.map { .string($0.rawValue) }
        return .object(fields)
    }
}

/// How a project made for a file input starts: the New Project settings (`project create`) and the outputs it is
/// made for. Fields left out take `project create`'s defaults.
public struct BatchTemplate: Sendable, Equatable {
    /// auto, portrait, landscape or square.
    public var canvas: String?
    /// Short side: 720, 1080 or 2160.
    public var resolution: String?
    /// 29.97, 30, 24 or 60.
    public var fps: String?
    /// Content language (BCP 47).
    public var language: String?
    /// Brand kit library reference, applied like `library apply`.
    public var brand: String?
    /// Export presets the project is made for; the `export` step exports each unless it names its own.
    public var outputs: [String]
    public var extra: [String: JSONValue]

    public init(
        canvas: String? = nil, resolution: String? = nil, fps: String? = nil, language: String? = nil,
        brand: String? = nil, outputs: [String] = []
    ) {
        self.canvas = canvas
        self.resolution = resolution
        self.fps = fps
        self.language = language
        self.brand = brand
        self.outputs = outputs
        extra = [:]
    }

    private static let known: Set<String> = ["canvas", "resolution", "fps", "language", "brand", "outputs"]

    init(json: JSONValue) throws {
        guard case .object(let fields) = json else { throw ProjectError.invalid("template must be an object") }
        func text(_ key: String) throws -> String? {
            // Numbers are accepted where the CLI takes their text (resolution 1080, fps 30).
            switch fields[key] {
            case .integer(let value)?: return String(value)
            case .number(let value)?: return String(value)
            default: return try BatchPipeline.optionalString(fields[key], "template.\(key)")
            }
        }
        canvas = try text("canvas")
        resolution = try text("resolution")
        fps = try text("fps")
        language = try text("language")
        brand = try text("brand")
        switch fields["outputs"] {
        case nil, .null?: outputs = []
        case .string(let list)?:
            outputs = list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        case .array(let list)?:
            outputs = try list.map {
                guard let name = $0.string else { throw ProjectError.invalid("template.outputs must list preset names") }
                return name
            }
        default: throw ProjectError.invalid("template.outputs must list preset names")
        }
        extra = fields.filter { !Self.known.contains($0.key) }
    }

    var json: JSONValue {
        var fields = extra
        for (key, value) in ["canvas": canvas, "resolution": resolution, "fps": fps, "language": language, "brand": brand] {
            fields[key] = value.map(JSONValue.string)
        }
        fields["outputs"] = outputs.isEmpty ? nil : .array(outputs.map(JSONValue.string))
        return .object(fields)
    }

    /// The `project create` parameters this template sets.
    public var createParameters: [String: JSONValue] {
        var values: [String: JSONValue] = [:]
        for (key, value) in ["canvas": canvas, "resolution": resolution, "fps": fps, "language": language, "brand": brand] {
            if let value { values[key] = .string(value) }
        }
        return values
    }
}

/// One step: a command or plugin action ID and its parameters. String parameters may hold `{input}` (the item's
/// input path), `{name}` (its name), `{project}` (its project file) and `{media}` (the media ID the last step
/// returned, else the project's first media).
public struct BatchStep: Sendable, Equatable {
    public static let variables = ["input", "name", "project", "media"]

    public var action: String
    public var params: [String: JSONValue]
    /// What the step does, for the queue; the action ID when nil.
    public var label: String?
    public var extra: [String: JSONValue]

    public init(_ action: String, params: [String: JSONValue] = [:], label: String? = nil) {
        self.action = action
        self.params = params
        self.label = label
        extra = [:]
    }

    init(json: JSONValue, index: Int) throws {
        guard case .object(let fields) = json, let action = fields["action"]?.string,
            !action.trimmingCharacters(in: .whitespaces).isEmpty
        else { throw ProjectError.invalid("steps[\(index)] must be {action, params}") }
        switch fields["params"] {
        case nil, .null?: params = [:]
        case .object(let values)?: params = values
        default: throw ProjectError.invalid("steps[\(index)].params must be an object")
        }
        self.action = action.trimmingCharacters(in: .whitespaces)
        label = try BatchPipeline.optionalString(fields["label"], "steps[\(index)].label")
        extra = fields.filter { !["action", "params", "label"].contains($0.key) }
    }

    var json: JSONValue {
        var fields = extra
        fields["action"] = .string(action)
        fields["params"] = .object(params)
        fields["label"] = label.map(JSONValue.string)
        return .object(fields)
    }

    /// The parameters with each `{variable}` in a string (also inside lists and objects) replaced by its value;
    /// variables without a value stay as written.
    public func resolvedParams(_ values: [String: String]) -> [String: JSONValue] {
        params.mapValues { Self.resolve($0, values) }
    }

    private static func resolve(_ value: JSONValue, _ values: [String: String]) -> JSONValue {
        switch value {
        case .string(let text):
            var result = text
            for (name, replacement) in values { result = result.replacingOccurrences(of: "{\(name)}", with: replacement) }
            return .string(result)
        case .array(let list): return .array(list.map { resolve($0, values) })
        case .object(let fields): return .object(fields.mapValues { resolve($0, values) })
        default: return value
        }
    }
}
