import BashCutPlugin
import BashCutProject
import Foundation

/// `review.check` (API 9): a plugin's own review of the timeline (a model-scored hook, contrast, brand rules). The
/// request carries the project and its folder; the result is `issues` in the shape `review.run` returns. Issue IDs
/// are prefixed with the provider ID and carry the plugin as `source`.
public struct ReviewCheckCapability: CapabilityAdapter {
    public static let capability = PluginAPI.reviewCheck
    /// At most this many issues from one check; the rest are dropped.
    public static let maximumIssues = 50

    public let project: Project
    public let projectRoot: URL?

    public init(project: Project, projectRoot: URL?) {
        self.project = project
        self.projectRoot = projectRoot
    }

    public func params(outputDirectory: URL?) -> JSONValue {
        var fields: [String: JSONValue] = [
            "project": .object(project.fields), "revision": .integer(project.revision),
            "fps": .number(project.fps.value), "duration": .integer(project.duration),
            "width": .integer(project.width), "height": .integer(project.height),
        ]
        if let projectRoot { fields["projectRoot"] = .string(projectRoot.path) }
        return .object(fields)
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
        let adapter = ReviewCheckCapability(project: project, projectRoot: projectRoot)
        return await withTaskGroup(of: (Int, [ReviewIssue]).self) { group in
            for (index, resolved) in providers.enumerated() {
                let limit = min(timeout, resolved.provider.timeoutSeconds.map(TimeInterval.init) ?? timeout)
                group.addTask {
                    do {
                        return (index, try await Self.withTimeout(limit) { try await run(adapter, using: resolved) })
                    } catch {
                        let reason = error is ReviewCheckTimeout
                            ? String(format: "did not finish within %.0f s", limit) : error.localizedDescription
                        return (index, [ReviewIssue(
                            id: resolved.provider.id + ":failed", title: "Plugin check failed",
                            detail: "\(resolved.provider.name) (\(resolved.plugin.manifest.displayName)) \(reason); "
                                + "its issues are missing from this review.",
                            frame: 0, severity: .info, source: resolved.plugin.id)])
                    }
                }
            }
            var results: [(Int, [ReviewIssue])] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
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
