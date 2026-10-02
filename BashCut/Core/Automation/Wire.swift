import BashCutProject
import Foundation

public struct RPCRequest: Codable, Sendable {
    public var jsonrpc = "2.0"
    public let id: JSONValue
    public let method: String
    public var params: [String: JSONValue]
    public let token: String?
    public init(
        id: JSONValue = .integer(1), method: String, params: [String: JSONValue] = [:],
        token: String? = nil
    ) {
        self.id = id
        self.method = method
        self.params = params
        self.token = token
    }
}
public struct RPCFailure: Error, Codable, Sendable, LocalizedError {
    public let code: Int
    public let message: String
    public init(_ code: Int, _ message: String) {
        self.code = code
        self.message = message
    }
    public var errorDescription: String? { message }
}
public struct RPCResponse: Codable, Sendable {
    public var jsonrpc = "2.0"
    public let id: JSONValue
    public let result: JSONValue?
    public let error: RPCFailure?
    public init(id: JSONValue, result: JSONValue? = nil, error: RPCFailure? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public enum CommandMode: String, Sendable { case read, ui, edit, privileged }
public enum CommandCatalog {
    public static let modes: [String: CommandMode] = [
        "context.get": .read, "project.get": .read, "timeline.get": .read, "media.list": .read,
        "review.run": .read, "captions.export": .read, "captions.import": .edit, "export.status": .read,
        "export.start": .privileged, "export.otio": .privileged,
        "timeline.apply": .edit, "timeline.undo": .edit, "timeline.redo": .edit,
        "ui.select": .ui, "ui.seek": .ui, "ui.notify": .ui,
    ]
    public static let instructions = """
        You are inside BashCut, a native video editor. Prefer the bashcut_* MCP tools; the bashcut CLI on PATH is the fallback.
        Read `bashcut context get` and `bashcut timeline get` before editing.
        Run `bashcut review run` for structural timeline issues (not measured audio loudness).
        Run `bashcut export status` to inspect the active or most recently completed export.
        Export with `bashcut export start --preset quick-draft --name draft --normalize-audio`; the app always asks the user first.
        Export interchange with `bashcut export otio --name timeline`; the app asks before writing.
        Use `bashcut timeline apply /absolute/path/ops.json --base-rev N --label "Describe the edit"`.
        One request is one atomic apply call. On staleRevision, re-read and retry. Changes appear in the UI and can be undone.
        ops.json is an array of objects. Supported operations:
        {"op":"split","item":"ID","atFrame":30}, {"op":"delete","item":"ID","ripple":true},
        {"op":"trim","item":"ID","edge":"end","toFrame":120,"ripple":true},
        {"op":"move","item":"ID","toTrack":"v1","atFrame":0},
        {"op":"reorder","item":"ID","before":"OTHER_ID"}; omit before to move to the end of Main,
        {"op":"setProperties","item":"ID","patch":{"transform":{"zoom":1.2}}},
        Cycle or choose framing with setProperties patches such as
        {"op":"setProperties","item":"ID","patch":{"reframePreset":"close","transform":{"zoom":1.3,"pan":0,"tilt":0}}},
        {"op":"setLinkedAudio","video":"VIDEO_ID","audio":"AUDIO_ID"}; omit audio to unlink,
        {"op":"insert","track":"t1","item":{"id":"new-id","at":0,"dur":90,"text":"Caption"}},
        {"op":"addTrack","track":{"id":"v3","kind":"video","role":"overlay","name":"B-roll 2","items":[]},"atIndex":2},
        {"op":"moveTrack","track":"v3","toIndex":3},
        {"op":"setTrackProperties","track":"v3","patch":{"name":"Product shots"}},
        {"op":"setProjectProperties","patch":{"audio":{"targetLUFS":-14,"normalizeEnabled":true}}},
        {"op":"deleteTrack","track":"v3"},
        {"op":"setProviderPreference","capability":"voice.synthesize","provider":"acme.voice.fast"}.
        {"op":"setBeatGrid","media":"MEDIA_ID","bpm":120,"frames":[0,15,30]}.
        {"op":"upsertSection","id":"section-hook","label":"Hook","atFrame":0},
        {"op":"deleteSection","id":"section-hook"}.
        {"op":"upsertTransition","id":"cut-a-b","kind":"dissolve","from":"CLIP_A","to":"CLIP_B","duration":12},
        {"op":"deleteTransition","id":"cut-a-b"}.
        {"op":"addColorLUT","lut":{"id":"look","name":"Look","path":"luts/look.cube","size":33}},
        {"op":"deleteColorLUT","id":"look"}.
        {"op":"roll","item":"ID","edge":"end","toFrame":120},
        {"op":"slip","item":"ID","sourceIn":60}.
        Roll moves a shared cut without changing total duration. Slip changes only the source start.
        atFrame/toFrame are absolute integer timeline frames. in is an integer source frame at the media fps.
        Never hand-edit project.bashcut.json while the app is open, never overwrite original footage, and never render with ffmpeg.
        Ask the user before downloading media or installing tools. Reply in the user's language.
        """
}

public enum WireOperations {
    public static func decode(_ value: JSONValue) throws -> [EditOperation] {
        guard case .array(let array) = value, !array.isEmpty, array.count <= 1000 else {
            throw RPCFailure(-32602, "ops must be a nonempty array of at most 1000 operations")
        }
        return try array.map(decodeOperation)
    }

    // Wire decoding stays exhaustive so malformed variants fail at one boundary.
    // swiftlint:disable:next cyclomatic_complexity
    private static func decodeOperation(_ value: JSONValue) throws -> EditOperation {
        let fields = value.object
        let parameters = OperationParameters(fields: fields)
        let string = parameters.string
        let frame = parameters.frame
        let ripple = fields["ripple"] == .bool(true)
        switch try string("op") {
        case "insert":
            let item = try parameters.object("item")
            return .insert(track: try string("track"), item: Item(fields: item))
        case "delete": return .delete(item: try string("item"), ripple: ripple)
        case "split":
            return .split(
                item: try string("item"), atFrame: try frame("atFrame"),
                newID: fields["newID"]?.string ?? UUID().uuidString)
        case "trim":
            let edge = try parameters.edge()
            return .trim(
                item: try string("item"), edge: edge, toFrame: try frame("toFrame"), ripple: ripple)
        case "slip":
            return .slip(item: try string("item"), sourceIn: try frame("sourceIn"))
        case "roll":
            return .roll(item: try string("item"), edge: try parameters.edge(), toFrame: try frame("toFrame"))
        case "move":
            return .move(
                item: try string("item"), toTrack: try string("toTrack"), atFrame: try frame("atFrame"))
        case "reorder":
            return .reorder(item: try string("item"), before: fields["before"]?.string)
        case "setProperties":
            let patch = try parameters.object("patch")
            return .setProperties(item: try string("item"), patch: patch)
        case "setLinkedAudio":
            return .setLinkedAudio(video: try string("video"), audio: fields["audio"]?.string)
        case "addTrack":
            return .addTrack(
                track: Track(fields: try parameters.object("track")), atIndex: try frame("atIndex"))
        case "deleteTrack": return .deleteTrack(track: try string("track"))
        case "moveTrack":
            return .moveTrack(track: try string("track"), toIndex: try frame("toIndex"))
        case "setTrackProperties":
            return .setTrackProperties(
                track: try string("track"), patch: try parameters.object("patch"))
        case "setProjectProperties":
            return .setProjectProperties(patch: try parameters.object("patch"))
        case "setProviderPreference":
            return .setProviderPreference(
                capability: try string("capability"), provider: fields["provider"]?.string)
        case "setBeatGrid":
            guard let bpm = fields["bpm"]?.double, case .array(let values) = fields["frames"],
                values.allSatisfy({ $0.int != nil })
            else { throw RPCFailure(-32602, "bpm and integer frames are required") }
            return .setBeatGrid(
                media: try string("media"), bpm: bpm, frames: values.compactMap(\.int),
                provenance: fields["generatedBy"]?.object)
        case "upsertSection":
            return .upsertSection(
                id: try string("id"), label: try string("label"), atFrame: try frame("atFrame"))
        case "deleteSection":
            return .deleteSection(id: try string("id"))
        case "upsertTransition":
            return .upsertTransition(
                id: try string("id"), kind: try string("kind"), from: try string("from"),
                to: try string("to"), duration: try frame("duration"))
        case "deleteTransition":
            return .deleteTransition(id: try string("id"))
        case "addColorLUT":
            return .addColorLUT(ColorLUT(fields: try parameters.object("lut")))
        case "deleteColorLUT":
            return .deleteColorLUT(id: try string("id"))
        default: throw RPCFailure(-32602, "Unknown edit operation")
        }
    }
}

private struct OperationParameters {
    let fields: [String: JSONValue]
    func string(_ key: String) throws -> String {
        guard let value = fields[key]?.string, !value.isEmpty else { throw RPCFailure(-32602, "Missing \(key)") }
        return value
    }
    func frame(_ key: String) throws -> Int {
        guard let value = fields[key]?.int, (0...2_000_000_000).contains(value) else {
            throw RPCFailure(-32602, "\(key) must be an integer frame")
        }
        return value
    }
    func object(_ key: String) throws -> [String: JSONValue] {
        guard case .object(let value) = fields[key] else { throw RPCFailure(-32602, "Missing \(key) object") }
        return value
    }
    func edge() throws -> Edge {
        guard let edge = Edge(rawValue: try string("edge")) else { throw RPCFailure(-32602, "Invalid edge") }
        return edge
    }
}
