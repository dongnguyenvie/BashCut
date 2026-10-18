import AVFoundation
import BashCutPlugin
import BashCutDocument
import BashCutProject
import Foundation
import UniformTypeIdentifiers

/// One thing found before a batch starts that would make items fail or the run stop.
struct BatchPreflightIssue: Equatable {
    enum Kind: Equatable {
        /// A plugin step's key is missing or refused: the plugin and why.
        case key(plugin: String, title: String, reason: String)
        /// Input files that cannot be read or played, by item index.
        case files([Int])
        /// Free space on the projects folder's volume, and a rough estimate of what the run writes.
        case disk(free: Int64, needed: Int64)
    }

    let kind: Kind
    /// Item names for `files`.
    var names: [String] = []

    /// English, for agents (CLI and MCP results).
    var message: String {
        switch kind {
        case .key(_, let title, let reason):
            return "\(title): \(reason). Its steps that need the key will fail on every item; add the key in Settings › "
                + "Plugins › \(title)"
        case .files:
            return "\(names.count) input file(s) cannot be read or played: \(Self.list(names))"
        case .disk(let free, let needed):
            return "Only \(Self.bytes(free)) free where the projects go; the batch may write about \(Self.bytes(needed))"
        }
    }

    /// The batch window's text, in the app's language.
    var localized: String {
        switch kind {
        case .key(_, let title, let reason):
            return String(format: String(localized: "%@: %@. Its steps that need the key will fail on every item."),
                          title, reason)
        case .files:
            return String(format: String(localized: "%lld files cannot be read or played: %@"), names.count,
                          Self.list(names))
        case .disk(let free, let needed):
            return String(format: String(localized: "Only %@ free where the projects go; the batch may write about %@."),
                          Self.bytes(free), Self.bytes(needed))
        }
    }

    private static func list(_ names: [String]) -> String {
        names.count <= 5 ? names.joined(separator: ", ") : names.prefix(5).joined(separator: ", ") + " +\(names.count - 5)"
    }

    static func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}

/// Checks a batch before it starts, so a run of many items does not fail on each one for the same reason: each
/// plugin step's keys (the plugin's own `options.check` when it has one), input files that do not read or play, and
/// free disk space against a rough estimate.
@MainActor
enum BatchPreflight {
    /// Bytes kept free beyond the estimate.
    static let diskMargin: Int64 = 1_000_000_000

    static func check(_ pipeline: BatchPipeline, items: [BatchItemSource], document: ProjectDocument) async
        -> [BatchPreflightIssue]
    {
        var issues = await keyIssues(pipeline, document: document)
        let unreadable = await unreadableItems(items)
        if !unreadable.isEmpty {
            issues.append(BatchPreflightIssue(kind: .files(unreadable), names: unreadable.map { items[$0].name }))
        }
        let folder = pipeline.projectsFolder.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? document.settings.defaultProjectsFolder
        if let free = freeSpace(at: folder) {
            let needed = estimatedBytes(pipeline, items: items)
            if free < needed + diskMargin { issues.append(BatchPreflightIssue(kind: .disk(free: free, needed: needed))) }
        }
        return issues
    }

    // MARK: Keys

    /// Each plugin with a step in the pipeline, once: its secret options that are empty, or that its `options.check`
    /// refuses with the stored value (a plugin that can work without a key, such as one using a server on this Mac,
    /// says so there).
    static func keyIssues(_ pipeline: BatchPipeline, document: ProjectDocument) async -> [BatchPreflightIssue] {
        var seen = Set<String>()
        var issues: [BatchPreflightIssue] = []
        for step in pipeline.steps {
            guard let plugin = document.plugins.action(step.action)?.plugin, seen.insert(plugin.id).inserted else {
                continue
            }
            let options = plugin.manifest.options ?? []
            let values = document.pluginOptionValues(plugin, revealSecrets: true)
            for option in options where option.type == .secret {
                let value = values[option.id]?.string ?? ""
                let reason: String?
                if option.isChecked {
                    let answer = await document.plugins.service.checkOption(
                        option.id, value: value, options: values, plugin: plugin)
                    reason = answer.flatMap { $0.ok ? nil : ($0.message ?? "\(option.title.text) is not set") }
                } else {
                    reason = value.isEmpty ? "\(option.title.text) is not set" : nil
                }
                if let reason {
                    issues.append(BatchPreflightIssue(kind: .key(
                        plugin: plugin.id, title: plugin.manifest.displayName, reason: reason)))
                }
            }
        }
        return issues
    }

    // MARK: Files

    /// File items that are not readable, empty, or (video and audio) not playable; projects whose file is not readable.
    static func unreadableItems(_ items: [BatchItemSource]) async -> [Int] {
        await withTaskGroup(of: (Int, Bool).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask { (index, await readable(item)) }
            }
            var bad: [Int] = []
            for await (index, ok) in group where !ok { bad.append(index) }
            return bad.sorted()
        }
    }

    nonisolated static func readable(_ item: BatchItemSource) async -> Bool {
        let path = item.url.path
        guard FileManager.default.isReadableFile(atPath: path) else { return false }
        guard item.kind == .file else { return true }
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        guard size > 0 else { return false }
        guard let type = UTType(filenameExtension: item.url.pathExtension), type.conforms(to: .audiovisualContent)
        else { return true }
        return (try? await AVURLAsset(url: item.url).load(.isPlayable)) ?? false
    }

    // MARK: Disk

    /// Free space for important use on the volume of `url` (its nearest existing folder).
    static func freeSpace(at url: URL) -> Int64? {
        var folder = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: folder.path), folder.path != "/" {
            folder.deleteLastPathComponent()
        }
        return (try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    /// A rough guess of what the run writes: per file item a fifth of its size (project, proxies, covers) plus half
    /// of it per export; per project item 100 MB per export.
    static func estimatedBytes(_ pipeline: BatchPipeline, items: [BatchItemSource]) -> Int64 {
        let exports = Int64(pipeline.steps.filter { $0.action == BatchRunner.exportAction }
            .reduce(0) { $0 + BatchRunner.presets($1, pipeline).count })
        return items.reduce(Int64(0)) { total, item in
            guard item.kind == .file else { return total + exports * 100_000_000 }
            let size = (try? FileManager.default.attributesOfItem(atPath: item.url.path)[.size] as? Int64) ?? 0
            return total + size / 5 + size * exports / 2
        }
    }
}
