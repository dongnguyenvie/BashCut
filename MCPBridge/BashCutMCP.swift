import BashCutAutomation
import Foundation
import MCP

private struct ToolRoute: Sendable {
    let name: String
    let method: String
    let description: String
    let schema: Value
}

private let emptySchema: Value = .object([
    "type": .string("object"), "properties": .object([:]),
    "additionalProperties": .bool(false),
])

private let revisionSchema = objectSchema(
    ["baseRev": integerProperty("Current project revision")], required: ["baseRev"])

private let routes: [ToolRoute] = [
    .init(name: "bashcut_context_get", method: "context.get", description: "Read editor context and current selection.", schema: emptySchema),
    .init(name: "bashcut_project_get", method: "project.get", description: "Read the open BashCut project.", schema: emptySchema),
    .init(name: "bashcut_timeline_get", method: "timeline.get", description: "Read the timeline and revision.", schema: objectSchema(["format": stringProperty("json or text")])),
    .init(name: "bashcut_media_list", method: "media.list", description: "List project media.", schema: emptySchema),
    .init(name: "bashcut_review_run", method: "review.run", description: "Run structural project review.", schema: emptySchema),
    .init(name: "bashcut_captions_export", method: "captions.export", description: "Export captions as SRT text.", schema: emptySchema),
    .init(name: "bashcut_export_status", method: "export.status", description: "Read export progress or the latest receipt.", schema: emptySchema),
    .init(name: "bashcut_timeline_apply", method: "timeline.apply", description: "Atomically apply validated timeline operations with one undo step.", schema: objectSchema([
        "baseRev": integerProperty("Revision returned by timeline_get"),
        "label": stringProperty("Short description of the edit"),
        "ops": .object(["type": .string("array"), "items": .object(["type": .string("object")])]),
    ], required: ["baseRev", "ops"])),
    .init(name: "bashcut_timeline_undo", method: "timeline.undo", description: "Undo one timeline action.", schema: revisionSchema),
    .init(name: "bashcut_timeline_redo", method: "timeline.redo", description: "Redo one timeline action.", schema: revisionSchema),
    .init(name: "bashcut_captions_import", method: "captions.import", description: "Import UTF-8 SRT captions atomically.", schema: objectSchema([
        "baseRev": integerProperty("Current project revision"), "text": stringProperty("SRT text"),
        "replace": .object(["type": .string("boolean")]),
    ], required: ["baseRev", "text"])),
    .init(name: "bashcut_ui_select", method: "ui.select", description: "Select a timeline item in the app.", schema: objectSchema(["item": stringProperty("Stable item ID")])),
    .init(name: "bashcut_ui_seek", method: "ui.seek", description: "Seek the viewer to an integer timeline frame.", schema: objectSchema(["frame": integerProperty("Timeline frame")], required: ["frame"])),
    .init(name: "bashcut_ui_notify", method: "ui.notify", description: "Show a short status message in BashCut.", schema: objectSchema(["message": stringProperty("Message")], required: ["message"])),
    .init(name: "bashcut_export_start", method: "export.start", description: "Request an app-approved background video export.", schema: objectSchema([
        "preset": stringProperty("tiktok, youtube-1080, youtube-4k, quick-draft, or prores"),
        "name": stringProperty("Output base name"), "directory": stringProperty("Optional output directory"),
        "includeSRT": .object(["type": .string("boolean")]),
        "normalizeAudio": .object([
            "type": .string("boolean"),
            "description": .string("Run optional two-pass LUFS normalization"),
        ]),
    ], required: ["preset", "name"])),
    .init(name: "bashcut_plugins_list", method: "plugins.list", description: "List installed plugins, providers and project provider preferences.", schema: emptySchema),
    .init(name: "bashcut_jobs_status", method: "jobs.status", description: "Read one provider-backed job, or all recent jobs when job is omitted.", schema: objectSchema(["job": stringProperty("Job ID")])),
    .init(name: "bashcut_jobs_cancel", method: "jobs.cancel", description: "Cancel a running provider-backed job.", schema: objectSchema(["job": stringProperty("Job ID")], required: ["job"])),
    .init(name: "bashcut_captions_generate", method: "captions.generate", description: "Start a background job that transcribes project media with the captions.transcribe provider and imports captions as one undoable edit.", schema: objectSchema([
        "media": stringProperty("Project media ID"), "replace": .object(["type": .string("boolean")]),
        "provider": stringProperty("Optional provider ID overriding the project preference"),
    ], required: ["media"])),
    .init(name: "bashcut_beats_detect", method: "beats.detect", description: "Start a background job that detects beats in audio media and sets the beat grid as one undoable edit.", schema: objectSchema([
        "media": stringProperty("Audio media ID already placed on the timeline"),
        "provider": stringProperty("Optional provider ID overriding the project preference"),
    ], required: ["media"])),
    .init(name: "bashcut_voice_speak", method: "voice.speak", description: "Start a background job that synthesizes voice takes and inserts the best take on the Voiceover track.", schema: objectSchema([
        "text": stringProperty("Voiceover text in the project content language"),
        "takes": .object(["type": .string("integer"), "minimum": .int(1), "maximum": .int(8)]),
        "atFrame": integerProperty("Timeline frame; defaults to the playhead"),
        "provider": stringProperty("Optional provider ID overriding the project preference"),
    ], required: ["text"])),
    .init(name: "bashcut_export_otio", method: "export.otio", description: "Request an app-approved OpenTimelineIO export.", schema: objectSchema([
        "name": stringProperty("Output base name"), "directory": stringProperty("Optional output directory"),
    ], required: ["name"])),
]

private func stringProperty(_ description: String) -> Value {
    .object(["type": .string("string"), "description": .string(description)])
}

private func integerProperty(_ description: String) -> Value {
    .object(["type": .string("integer"), "minimum": .int(0), "description": .string(description)])
}

private func objectSchema(_ properties: [String: Value], required: [String] = []) -> Value {
    var schema: [String: Value] = [
        "type": .string("object"), "properties": .object(properties),
        "additionalProperties": .bool(false),
    ]
    if !required.isEmpty { schema["required"] = .array(required.map(Value.string)) }
    return .object(schema)
}

@main enum BashCutMCP {
    static func main() async throws {
        let server = Server(
            name: "bashcut-mcp", version: "0.1.0",
            capabilities: .init(tools: .init()))
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: routes.map { route in
                Tool(name: route.name, description: route.description, inputSchema: route.schema)
            })
        }
        await server.withMethodHandler(CallTool.self) { request in
            guard let route = routes.first(where: { $0.name == request.name }) else {
                return .init(content: [.text(text: "Unknown BashCut tool", annotations: nil, _meta: nil)], isError: true)
            }
            do {
                let arguments = try JSONEncoder().encode(request.arguments ?? [:])
                let response = try MCPBridgeClient.call(
                    method: route.method, arguments: arguments,
                    token: ProcessInfo.processInfo.environment["BASHCUT_SESSION_TOKEN"])
                let structured = try JSONDecoder().decode(Value.self, from: response.data)
                return CallTool.Result(
                    content: [.text(text: response.text, annotations: nil, _meta: nil)],
                    structuredContent: Optional.some(structured), isError: false)
            } catch {
                return .init(
                    content: [.text(text: error.localizedDescription, annotations: nil, _meta: nil)],
                    isError: true)
            }
        }
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
