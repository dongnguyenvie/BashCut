import BashCutProject
import Foundation

/// Stable model API identifier, stored in `ModelConfiguration` and the credential account.
public struct ModelAPIKind: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let responses: ModelAPIKind = "responses"
    public static let chatCompletions: ModelAPIKind = "chatCompletions"
    public static let anthropic: ModelAPIKind = "anthropic"
}

/// One model API wire format: endpoint, request body, authentication and response text.
/// Adding an API means one conforming type registered in `ModelAdapters.all`, plus a test.
public protocol ModelAdapter: Sendable {
    var kind: ModelAPIKind { get }
    var title: String { get }
    /// Path appended to the configured base URL.
    var endpointPath: String { get }
    /// Headers sent with every request, with or without a key.
    var headers: [String: String] { get }
    func body(_ request: ModelRequest) -> [String: JSONValue]
    /// Adds the API key.
    func authorize(_ request: inout URLRequest, key: String)
    func text(from response: [String: JSONValue]) -> String
}

extension ModelAdapter {
    public var headers: [String: String] { [:] }
}

/// The provider-neutral content of one generation request.
public struct ModelRequest: Sendable {
    public let model: String
    public let system: String
    public let prompt: String
    public let image: ModelImage?
    public let maxOutputTokens: Int
}

public enum ModelAdapters {
    public static let all: [any ModelAdapter] = [
        ResponsesModelAdapter(), ChatCompletionsModelAdapter(), AnthropicModelAdapter(),
    ]

    public static func adapter(_ kind: ModelAPIKind) throws -> any ModelAdapter {
        guard let adapter = all.first(where: { $0.kind == kind }) else {
            throw ModelError.invalid("Unknown model API \(kind.rawValue)")
        }
        return adapter
    }
}
