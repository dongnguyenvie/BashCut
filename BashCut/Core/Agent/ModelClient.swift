import BashCutProject
import CryptoKit
import Foundation

public struct ModelConfiguration: Codable, Sendable, Equatable {
    public var kind: ModelAPIKind = .responses
    public var baseURL = "https://api.openai.com/v1"
    public var model = ""
    public var maxOutputTokens = 4096
    public init() {}
    public var credentialAccount: String {
        SHA256.hash(data: Data((kind.rawValue + "|" + baseURL).utf8)).map { String(format: "%02x", $0) }
            .joined()
    }
    public func endpoint() throws -> URL {
        guard let base = URL(string: baseURL), let host = base.host, base.user == nil,
            base.password == nil,
            base.query == nil, base.fragment == nil,
            base.scheme == "https"
                || (base.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host))
        else {
            throw ModelError.invalid("Use an HTTPS API base URL, or HTTP for a localhost model")
        }
        return base.appendingPathComponent(try ModelAdapters.adapter(kind).endpointPath)
    }
}

public enum ModelError: Error, LocalizedError {
    case invalid(String)
    case http(Int)
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): return message
        case .http(let code):
            return "Model API returned HTTP \(code). Check the endpoint, model, key and quota."
        }
    }
}

public struct ModelImage: Sendable, Equatable {
    public let data: Data
    public let mediaType: String
    public init(data: Data, mediaType: String = "image/png") throws {
        guard !data.isEmpty, data.count <= 5 * 1_024 * 1_024,
            ["image/png", "image/jpeg"].contains(mediaType)
        else { throw ModelError.invalid("Context image must be a PNG or JPEG up to 5 MB") }
        self.data = data
        self.mediaType = mediaType
    }

    var dataURL: String {
        "data:\(mediaType);base64," + data.base64EncodedString()
    }
}

public protocol ModelTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct URLModelTransport: ModelTransport {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(
            configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelError.invalid("Invalid API response")
        }
        return (data, http.statusCode)
    }
}

public struct ModelClient: Sendable {
    private let transport: any ModelTransport
    public init(transport: any ModelTransport = URLModelTransport()) { self.transport = transport }

    public func generate(
        configuration: ModelConfiguration, key: String, system: String, prompt: String,
        image: ModelImage? = nil
    ) async throws -> String {
        let request = try Self.request(
            configuration: configuration, key: key, system: system, prompt: prompt, image: image)
        let (data, status) = try await transport.send(request)
        guard (200..<300).contains(status) else { throw ModelError.http(status) }
        guard data.count <= 8 * 1024 * 1024 else {
            throw ModelError.invalid("API response is too large")
        }
        let json = try JSONDecoder().decode(JSONValue.self, from: data).object
        let text = try ModelAdapters.adapter(configuration.kind).text(from: json)
        guard !text.isEmpty else {
            throw ModelError.invalid(
                "Model returned no text; inspect model compatibility or output limits")
        }
        return text
    }

    public static func request(
        configuration: ModelConfiguration, key: String, system: String, prompt: String,
        image: ModelImage? = nil
    ) throws -> URLRequest {
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            (1...128_000).contains(configuration.maxOutputTokens)
        else {
            throw ModelError.invalid("Enter a model ID and a valid output token limit")
        }
        let adapter = try ModelAdapters.adapter(configuration.kind)
        var request = URLRequest(url: try configuration.endpoint())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in adapter.headers { request.setValue(value, forHTTPHeaderField: name) }
        if !key.isEmpty { adapter.authorize(&request, key: key) }
        let body = adapter.body(ModelRequest(
            model: configuration.model, system: system, prompt: prompt, image: image,
            maxOutputTokens: configuration.maxOutputTokens))
        request.httpBody = try JSONEncoder().encode(JSONValue.object(body))
        return request
    }
}
