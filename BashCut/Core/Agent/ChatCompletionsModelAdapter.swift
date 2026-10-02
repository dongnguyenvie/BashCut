import BashCutProject
import Foundation

/// OpenAI-compatible Chat Completions (`/chat/completions`), also served by local model servers.
public struct ChatCompletionsModelAdapter: ModelAdapter {
    public init() {}
    public let kind = ModelAPIKind.chatCompletions
    public let title = "OpenAI-compatible"
    public let endpointPath = "chat/completions"

    public func body(_ request: ModelRequest) -> [String: JSONValue] {
        let userContent: JSONValue = request.image.map {
            .array([
                .object(["type": .string("text"), "text": .string(request.prompt)]),
                .object(["type": .string("image_url"), "image_url": .object(["url": .string($0.dataURL)])]),
            ])
        } ?? .string(request.prompt)
        return [
            "model": .string(request.model),
            "messages": .array([
                .object(["role": .string("system"), "content": .string(request.system)]),
                .object(["role": .string("user"), "content": userContent]),
            ]),
            "max_tokens": .integer(request.maxOutputTokens),
        ]
    }

    public func authorize(_ request: inout URLRequest, key: String) {
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    }

    public func text(from response: [String: JSONValue]) -> String {
        response["choices"]?.array.first?.object["message"]?.object["content"]?.string ?? ""
    }
}
