import BashCutProject
import Foundation

/// The chat command boundary. New commands are unavailable until explicitly reviewed here.
@MainActor public final class ChatCommandSession {
    public static let allowedMethods: Set<String> = [
        "context.get", "project.get", "project.save", "project.format", "timeline.get", "timeline.apply",
        "timeline.undo", "timeline.redo", "timeline.move", "timeline.close-gap", "media.list", "media.import",
        "media.proxy", "media.place", "review.run", "captions.export", "captions.import", "captions.words",
        "captions.generate", "export.status", "export.start", "export.otio", "plugins.list", "plugins.actions",
        "plugins.hooks", "plugins.options", "plugins.health", "jobs.status", "jobs.cancel", "layers.add", "layers.set",
        "adjustment.add", "style.apply", "style.save", "style.delete", "looks.save", "looks.delete", "schema.get",
        "clip.speed", "clip.speed-curve", "clip.motion", "clip.keyframe", "clip.reverse", "beats.detect", "voice.speak",
        "audio.measure", "media.sync",
        "storage.get", "ui.select", "ui.view", "ui.source", "ui.seek", "ui.frame", "ui.panel", "luts.import",
        "knowledge.get", "knowledge.memo", "library.list", "library.get", "library.stats", "library.add", "library.update",
        "library.remove", "library.apply", "library.place",
    ]
    private var token: String?

    public init() {}

    public func revoke(in registry: CommandRegistry) {
        if let token { registry.revoke(token) }
        token = nil
    }

    public func perform(
        _ method: String, params: [String: JSONValue], allowEdits: Bool, registry: CommandRegistry
    ) async -> RPCResponse {
        // Check every host call, including reads and calls rejected by the allow-list.
        if !allowEdits { revoke(in: registry) }
        let id = JSONValue.string(UUID().uuidString)
        guard Self.allowedMethods.contains(method) else {
            return RPCResponse(id: id, error: RPCFailure(-32601, "Chat agents cannot run \(method)"))
        }
        if token == nil, allowEdits { token = registry.issueToken(author: .agent) }
        return await registry.handle(RPCRequest(id: id, method: method, params: params, token: token))
    }
}
