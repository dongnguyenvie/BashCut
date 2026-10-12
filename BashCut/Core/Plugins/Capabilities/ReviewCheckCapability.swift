import BashCutPlugin
import BashCutProject
import Foundation

/// `review.check` (API 9): a plugin's own review of the timeline (a model-scored hook, contrast, brand rules). The
/// request carries the project and its folder; the result is `issues` in the shape `review.run` returns. Issue IDs
/// are prefixed with the provider ID and carry the plugin as `source`.
///
/// A request is at most 1 MiB, so a project whose JSON is over `inlineProjectBytes` is not sent inline: it is
/// written once to a private file, `projectFile` gives its path, and the file is removed when every check is done.
public struct ReviewCheckCapability: CapabilityAdapter {
    public static let capability = PluginAPI.reviewCheck
    /// At most this many issues from one check; the rest are dropped.
    public static let maximumIssues = 50
    /// The largest project JSON sent inline; the rest of the request (options included) must fit in what is left of
    /// the 1 MiB request limit.
    public static let inlineProjectBytes = 512 * 1024

    public let project: Project
    public let projectRoot: URL?
    /// The project's JSON on disk, instead of inline, for a project over `inlineProjectBytes`.
    public let projectFile: URL?

    public init(project: Project, projectRoot: URL?, projectFile: URL? = nil) {
        self.project = project
        self.projectRoot = projectRoot
        self.projectFile = projectFile
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        var fields: [String: JSONValue] = [
            "revision": .integer(project.revision),
            "fps": .number(project.fps.value), "duration": .integer(project.duration),
            "width": .integer(project.width), "height": .integer(project.height),
        ]
        if let projectFile {
            fields["projectFile"] = .string(projectFile.path)
        } else {
            fields["project"] = .object(project.fields)
        }
        if let projectRoot { fields["projectRoot"] = .string(projectRoot.path) }
        return .object(fields)
    }

    /// Writes the project's JSON to a new private folder when it is too large to send inline; nil when it fits.
    /// The caller removes the file's folder when the checks are done.
    static func projectFile(for project: Project) throws -> URL? {
        let data = try JSONEncoder().encode(JSONValue.object(project.fields))
        guard data.count > inlineProjectBytes else { return nil }
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("bashcut-review-check-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = folder.appendingPathComponent("project.json")
        try data.write(to: file, options: .atomic)
        return file
    }

    public func output(from result: JSONValue, context: CapabilityContext) async throws -> [ReviewIssue] {
        try Self.issues(
            from: result, provider: context.provenance.providerID, source: context.provenance.pluginID,
            duration: project.duration)
    }

    /// Validates a result: `issues` is an array of objects with `id`, `title`, `detail` and `frame`; `endFrame`,
    /// `severity` (default warning) and `fix` (`command`, `arguments`, `hint`) are optional. Frames are clamped to the
    /// timeline.
    static func issues(from result: JSONValue, provider: String, source: String, duration: Int) throws -> [ReviewIssue] {
        guard let list = result.object["issues"]?.array else {
            throw PluginError.invalid("review.check must return issues")
        }
        return try list.prefix(maximumIssues).map { value in
            let fields = value.object
            guard let id = fields["id"]?.string, (1...64).contains(id.count),
                  let title = fields["title"]?.string, (1...120).contains(title.count),
                  let frame = fields["frame"]?.int
            else { throw PluginError.invalid("review.check issues need id, title and frame") }
            let detail = String((fields["detail"]?.string ?? "").prefix(1_000))
            let severity = try fields["severity"].map { value in
                guard let parsed = value.string.flatMap(ReviewSeverity.init(rawValue:)) else {
                    throw PluginError.invalid("review.check severity must be error, warning or info")
                }
                return parsed
            } ?? .warning
            let start = min(max(0, frame), max(0, duration - 1))
            let end = fields["endFrame"]?.int.map { min(max(start + 1, $0), duration) }
            return ReviewIssue(
                id: provider + ":" + id, title: title, detail: detail, frame: start, endFrame: end, severity: severity,
                fix: fields["fix"].flatMap(fix), source: source)
        }
    }

    private static func fix(_ value: JSONValue) -> ReviewFix? {
        let fields = value.object
        let command = fields["command"]?.string.flatMap { $0.count <= 64 ? $0 : nil }
        let hint = fields["hint"]?.string.map { String($0.prefix(500)) }
        guard command != nil || hint != nil else { return nil }
        return ReviewFix(command: command, arguments: fields["arguments"]?.object ?? [:], hint: hint)
    }
}

extension CapabilityService {
    /// Every ready `review.check` provider, minus those `disabled` names by provider or plugin ID.
    public func reviewCheckProviders(projectRoot: URL?, disabled: Set<String> = []) -> [ResolvedPluginProvider] {
        runnablePlugins(projectRoot: projectRoot).filter { !disabled.contains($0.id) }.flatMap { plugin in
            (plugin.manifest.providers ?? [])
                .filter { $0.capability == PluginAPI.reviewCheck && !disabled.contains($0.id) }
                .map { ResolvedPluginProvider(plugin: plugin, provider: $0) }
        }
    }

    /// Runs `providers` side by side, each for at most `timeout` seconds (or its own shorter `timeoutSeconds`). A
    /// check that fails or runs out of time becomes an info issue; it never stops the others or the review.
    public func runReviewChecks(
        _ providers: [ResolvedPluginProvider], project: Project, projectRoot: URL?, timeout: TimeInterval = 30
    ) async -> [ReviewIssue] {
        guard !providers.isEmpty else { return [] }
        let projectFile: URL?
        do {
            projectFile = try ReviewCheckCapability.projectFile(for: project)
        } catch {
            return providers.map { resolved in
                Self.failedCheck(resolved, reason: "could not be given the project (\(error.localizedDescription))")
            }
        }
        defer { if let projectFile { try? FileManager.default.removeItem(at: projectFile.deletingLastPathComponent()) } }
        let adapter = ReviewCheckCapability(project: project, projectRoot: projectRoot, projectFile: projectFile)
        return await withTaskGroup(of: (Int, [ReviewIssue]).self) { group in
            for (index, resolved) in providers.enumerated() {
                let limit = min(timeout, resolved.provider.timeoutSeconds.map(TimeInterval.init) ?? timeout)
                group.addTask {
                    do {
                        return (index, try await Self.withTimeout(limit) { try await run(adapter, using: resolved) })
                    } catch {
                        let reason = error is ReviewCheckTimeout
                            ? String(format: "did not finish within %.0f s", limit) : error.localizedDescription
                        return (index, [Self.failedCheck(resolved, reason: reason)])
                    }
                }
            }
            var results: [(Int, [ReviewIssue])] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
    }

    /// The info issue a check that failed becomes.
    static func failedCheck(_ resolved: ResolvedPluginProvider, reason: String) -> ReviewIssue {
        ReviewIssue(
            id: resolved.provider.id + ":failed", title: "Plugin check failed",
            detail: "\(resolved.provider.name) (\(resolved.plugin.manifest.displayName)) \(reason); "
                + "its issues are missing from this review.",
            frame: 0, severity: .info, source: resolved.plugin.id)
    }

    /// The work's result, or `ReviewCheckTimeout` after `seconds`; the work is cancelled (its process terminated).
    static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ReviewCheckTimeout()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw ReviewCheckTimeout() }
            return first
        }
    }
}

struct ReviewCheckTimeout: Error {}
