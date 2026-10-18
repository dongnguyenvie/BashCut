import Foundation
import UniformTypeIdentifiers

/// One item of a batch: a media file that becomes a new project, or a project the steps run on (decision D4).
public struct BatchItemSource: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable { case file, project }

    public let name: String
    public let url: URL
    public let kind: Kind

    public init(name: String, url: URL, kind: Kind) {
        self.name = name
        self.url = url
        self.kind = kind
    }
}

extension BatchPipeline {
    public static let projectFileName = "project.bashcut.json"

    /// The items the inputs name, in input order (a folder's entries in name order): a file is one item; a folder
    /// gives its video, audio and image files and the project folders directly inside it; a project folder or
    /// project file is one project item. Relative paths resolve against `base`. The same file or project twice
    /// counts once. Throws for a path that does not exist or a folder with nothing to run on.
    public func items(relativeTo base: URL? = nil) throws -> [BatchItemSource] {
        var items: [BatchItemSource] = []
        var seen = Set<String>()
        func add(_ item: BatchItemSource) {
            if seen.insert(item.url.standardizedFileURL.path).inserted { items.append(item) }
        }
        for input in inputs {
            let expanded = (input.path as NSString).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded, relativeTo: base).standardizedFileURL
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else {
                throw ProjectError.invalid(BatchMessages.text(BatchMessages.inputMissing, input.path))
            }
            let kind = input.kind ?? Self.detectedKind(url, isFolder: isFolder.boolValue)
            switch kind {
            case .project:
                guard let file = Self.projectFile(url) else { throw ProjectError.invalid(BatchMessages.text(BatchMessages.noProject, input.path)) }
                add(BatchItemSource(name: file.deletingLastPathComponent().lastPathComponent, url: file, kind: .project))
            case .file:
                guard !isFolder.boolValue else { throw ProjectError.invalid(BatchMessages.text(BatchMessages.inputFolder, input.path)) }
                add(BatchItemSource(name: url.deletingPathExtension().lastPathComponent, url: url, kind: .file))
            case .folder:
                guard isFolder.boolValue else { throw ProjectError.invalid(BatchMessages.text(BatchMessages.inputNotFolder, input.path)) }
                let found = try Self.folderItems(url)
                guard !found.isEmpty else {
                    throw ProjectError.invalid(BatchMessages.text(BatchMessages.noMedia, input.path))
                }
                found.forEach(add)
            }
        }
        return items
    }

    static func detectedKind(_ url: URL, isFolder: Bool) -> BatchInput.Kind {
        if url.lastPathComponent == projectFileName { return .project }
        guard isFolder else { return .file }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent(projectFileName).path) ? .project : .folder
    }

    static func projectFile(_ url: URL) -> URL? {
        let file = url.lastPathComponent == projectFileName ? url : url.appendingPathComponent(projectFileName)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private static func folderItems(_ folder: URL) throws -> [BatchItemSource] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        return entries.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
            if values?.isDirectory == true {
                return projectFile(url).map { BatchItemSource(name: url.lastPathComponent, url: $0, kind: .project) }
            }
            guard values?.isRegularFile == true, let type = UTType(filenameExtension: url.pathExtension),
                type.conforms(to: .audiovisualContent) || type.conforms(to: .image)
            else { return nil }
            return BatchItemSource(name: url.deletingPathExtension().lastPathComponent, url: url, kind: .file)
        }
    }
}

/// Where a batch, an item or a step stands. A batch ends `completed` (its items may have failed or been skipped
/// under `onFailure: skip`), `failed` (stopped by `onFailure: stop`, or it could not start), `cancelled`, `denied`
/// (the user refused its approval) or `interrupted` (BashCut quit or stopped while it ran; `batch retry` resumes it).
public enum BatchState: String, Sendable, Codable {
    case awaitingApproval = "awaiting_approval"
    case waiting, running, completed, failed, skipped, cancelled, denied, interrupted

    public var isFinished: Bool { ![.awaitingApproval, .waiting, .running].contains(self) }
}

/// One step of one item.
public struct BatchStepStatus: Sendable, Equatable, Codable {
    public let action: String
    public let label: String?
    public var state: BatchState = .waiting
    /// The job the step ran as (`jobs status`), kept after the project switch drops it from the job list.
    public var job: String?
    public var error: String?
    public var errorCategory: String?
    /// Files the step wrote (exports).
    public var outputs: [String] = []
    public var result: JSONValue = .null

    public init(action: String, label: String?) {
        self.action = action
        self.label = label
    }

    public var json: JSONValue {
        .object([
            "action": .string(action), "label": label.map(JSONValue.string) ?? .null, "state": .string(state.rawValue),
            "job": job.map(JSONValue.string) ?? .null, "error": error.map(JSONValue.string) ?? .null,
            "errorCategory": errorCategory.map(JSONValue.string) ?? .null,
            "outputs": .array(outputs.map(JSONValue.string)), "result": result,
        ])
    }
}

/// One item: its input, the project it became and each step's status.
public struct BatchItemStatus: Sendable, Equatable, Codable {
    public let source: BatchItemSource
    public var state: BatchState = .waiting
    /// The project file the steps ran on, once it is open.
    public var project: URL?
    public var steps: [BatchStepStatus]
    /// The step running now (0-based), or nil.
    public var currentStep: Int?
    public var error: String?
    /// When the item's last run started and ended, for the batch's time estimate.
    public var startedAt: Date?
    public var finishedAt: Date?

    public init(source: BatchItemSource, steps: [BatchStep]) {
        self.source = source
        self.steps = steps.map { BatchStepStatus(action: $0.action, label: $0.label) }
    }

    public var outputs: [String] { steps.flatMap(\.outputs) }

    public var json: JSONValue {
        .object([
            "name": .string(source.name), "input": .string(source.url.path), "kind": .string(source.kind.rawValue),
            "state": .string(state.rawValue), "project": project.map { .string($0.path) } ?? .null,
            "step": currentStep.map { .integer($0 + 1) } ?? .null, "error": error.map(JSONValue.string) ?? .null,
            "outputs": .array(outputs.map(JSONValue.string)), "steps": .array(steps.map(\.json)),
        ])
    }
}

/// One batch run as `batch status` reports it.
public struct BatchRunStatus: Sendable, Equatable, Codable {
    public let id: String
    public let pipeline: BatchPipeline
    public var state: BatchState
    public var items: [BatchItemStatus]
    public let createdAt: Date
    /// When the run, or its latest retry, started running.
    public var runningSince: Date?
    public var finishedAt: Date?
    /// Items run at once.
    public var concurrency: Int
    public var error: String?

    public init(id: String, pipeline: BatchPipeline, items: [BatchItemSource], state: BatchState, createdAt: Date = Date()) {
        self.id = id
        self.pipeline = pipeline
        self.state = state
        self.items = items.map { BatchItemStatus(source: $0, steps: pipeline.steps) }
        self.createdAt = createdAt
        concurrency = 1
    }

    public func count(_ state: BatchState) -> Int { items.filter { $0.state == state }.count }

    /// With `full`, every item's steps; otherwise each item's state, current step and outputs. `now` dates the
    /// time estimate.
    public func json(full: Bool = true, now: Date = Date()) -> JSONValue {
        let formatter = ISO8601DateFormatter()
        let items = items.map { item -> JSONValue in
            guard !full else { return item.json }
            var fields = item.json.object
            fields["steps"] = nil
            return .object(fields)
        }
        return .object([
            "batch": .string(id), "name": pipeline.name.map(JSONValue.string) ?? .null, "state": .string(state.rawValue),
            "concurrency": .object(["asked": .integer(pipeline.concurrency), "used": .integer(concurrency)]),
            "onFailure": .string(pipeline.onFailure.rawValue),
            "counts": .object([
                "items": .integer(self.items.count), "completed": .integer(count(.completed)),
                "failed": .integer(count(.failed)), "skipped": .integer(count(.skipped)),
                "cancelled": .integer(count(.cancelled)), "waiting": .integer(count(.waiting)),
                "interrupted": .integer(count(.interrupted)),
            ]),
            "elapsedSeconds": .integer(Int(elapsed(now: now))),
            "remainingSeconds": remaining(now: now).map { .integer(Int($0.rounded())) } ?? .null,
            "retryable": .integer(retryableItems.count),
            "error": error.map(JSONValue.string) ?? .null, "items": .array(items),
            "startedAt": .string(formatter.string(from: createdAt)),
            "finishedAt": finishedAt.map { .string(formatter.string(from: $0)) } ?? .null,
        ])
    }
}
