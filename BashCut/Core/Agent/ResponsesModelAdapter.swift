import BashCutProject
import Foundation

/// OpenAI Responses API (`/responses`), with `store: false`.
public struct ResponsesModelAdapter: ModelAdapter {
    public init() {}
    public let kind = ModelAPIKind.responses
    public let title = "OpenAI Responses"
    public let endpointPath = "responses"

    public func body(_ request: ModelRequest) -> [String: JSONValue] {
        let input: JSONValue = request.image.map {
            .array([.object([
                "role": .string("user"),
                "content": .array([
                    .object(["type": .string("input_text"), "text": .string(request.prompt)]),
                    .object(["type": .string("input_image"), "image_url": .string($0.dataURL)]),
                ]),
            ])])
        } ?? .string(request.prompt)
        return [
            "model": .string(request.model), "instructions": .string(request.system), "input": input,
            "store": .bool(false), "max_output_tokens": .integer(request.maxOutputTokens),
        ]
    }

    public func authorize(_ request: inout URLRequest, key: String) {
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    }

    public func text(from response: [String: JSONValue]) -> String {
        (response["output"]?.array ?? []).flatMap { $0.object["content"]?.array ?? [] }
            .filter { $0.object["type"]?.string == "output_text" }
            .compactMap { $0.object["text"]?.string }.joined(separator: "\n")
    }
}
