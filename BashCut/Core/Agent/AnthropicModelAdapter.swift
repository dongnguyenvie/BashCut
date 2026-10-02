import BashCutProject
import Foundation

/// Anthropic Messages API (`/messages`).
public struct AnthropicModelAdapter: ModelAdapter {
    public init() {}
    public let kind = ModelAPIKind.anthropic
    public let title = "Anthropic Messages"
    public let endpointPath = "messages"
    public let headers = ["anthropic-version": "2023-06-01"]

    public func body(_ request: ModelRequest) -> [String: JSONValue] {
        let userContent: JSONValue = request.image.map {
            .array([
                .object(["type": .string("text"), "text": .string(request.prompt)]),
                .object([
                    "type": .string("image"),
                    "source": .object([
                        "type": .string("base64"), "media_type": .string($0.mediaType),
                        "data": .string($0.data.base64EncodedString()),
                    ]),
                ]),
            ])
        } ?? .string(request.prompt)
        return [
            "model": .string(request.model), "system": .string(request.system),
            "messages": .array([.object(["role": .string("user"), "content": userContent])]),
            "max_tokens": .integer(request.maxOutputTokens),
        ]
    }

    public func authorize(_ request: inout URLRequest, key: String) {
        request.setValue(key, forHTTPHeaderField: "x-api-key")
    }

    public func text(from response: [String: JSONValue]) -> String {
        (response["content"]?.array ?? []).filter { $0.object["type"]?.string == "text" }
            .compactMap { $0.object["text"]?.string }.joined(separator: "\n")
    }
}
