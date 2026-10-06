import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation

extension ProjectDocument {
    enum ProxyState: String {
        case none, queued, ready
    }

    /// Whether `media` has a preview proxy on disk or one being made.
    func proxyState(_ media: Media) -> ProxyState {
        guard let root = fileURL?.deletingLastPathComponent() else { return .none }
        if ProxyMediaSource.proxyURL(for: media, root: root) != nil { return .ready }
        let label = URL(fileURLWithPath: media.path).lastPathComponent
        return proxies.active.contains { $0.detail == label } ? .queued : .none
    }

    /// Queues preview proxies for video media: the listed IDs, or every video when nil. Without `force`,
    /// media that already has a proxy or is light enough to preview directly (see `ProxyManager.Policy`)
    /// is skipped. Returns one status per media: `queued` (with its job), `exists`, `not-needed` or `skipped`.
    @discardableResult
    func requestProxies(mediaIDs: [String]? = nil, force: Bool = false, author: Author = .user) async throws
        -> [JSONValue]
    {
        guard let root = fileURL?.deletingLastPathComponent() else {
            throw ProjectError.invalid("Open a saved project first")
        }
        // A sticker movie with alpha (#64) is previewed from its original: proxies have no alpha channel.
        var selected = project.media.filter {
            !["audio", "image"].contains($0["kind"]?.string ?? "video") && $0["alpha"]?.bool != true
        }
        if let mediaIDs {
            for id in mediaIDs where !project.media.contains(where: { $0.id == id }) {
                throw ProjectError.invalid("Unknown media \(id)")
            }
            selected = selected.filter { mediaIDs.contains($0.id) }
        }
        let manager = ProxyManager()
        var results: [JSONValue] = []
        for media in selected {
            var result: [String: JSONValue] = ["media": .string(media.id)]
            defer { results.append(.object(result)) }
            guard let destination = ProxyManager.destination(for: media, root: root),
                let source = try? MediaPathResolver.resolve(media.path, projectRoot: root, workspaceRoot: settings.workspace)
            else {
                result["status"] = .string("skipped")
                continue
            }
            if !force, FileManager.default.fileExists(atPath: destination.path) {
                result["status"] = .string("exists")
                continue
            }
            if !force {
                guard let probe = try? await manager.probe(source) else {
                    result["status"] = .string("skipped")
                    continue
                }
                if !probe.needsProxy {
                    result["status"] = .string("not-needed")
                    continue
                }
            }
            let job = proxies.request(
                source: source, destination: destination, label: URL(fileURLWithPath: media.path).lastPathComponent,
                author: author)
            DebugLog.write("proxy", "\(media.id) queued (job \(job), force=\(force))")
            result["status"] = .string("queued")
            result["job"] = .string(job)
        }
        return results
    }

    /// After an import: proxies for the new media that need one, without blocking the import.
    func requestProxiesAfterImport(_ mediaIDs: [String], author: Author) {
        guard !mediaIDs.isEmpty else { return }
        Task { [weak self] in
            do { try await self?.requestProxies(mediaIDs: mediaIDs, author: author) } catch {
                DebugLog.write("proxy", "not queued: \(error.localizedDescription)")
            }
        }
    }

    func registerProxyCommands() {
        handleAuthored("media.proxy") { document, arguments, author in
            let media = arguments.optionalString("media")
            let results = try await document.requestProxies(
                mediaIDs: media.map { [$0] }, force: arguments.bool("force"), author: author)
            return .array(results)
        }
    }
}
