import BashCutAgent
import BashCutProject
import Foundation
import Testing

private struct MockModelTransport: ModelTransport {
    let response: String
    let status: Int
    func send(_ request: URLRequest) async throws -> (Data, Int) { (Data(response.utf8), status) }
}

struct ModelClientTests {
    @Test(
        "Responses, compatible chat and Anthropic requests have the correct authentication and bodies")
    func requestShapes() throws {
        for kind in ModelAdapters.all.map(\.kind) {
            var config = ModelConfiguration()
            config.kind = kind
            config.model = "test-model"
            let request = try ModelClient.request(
                configuration: config, key: "test-secret", system: "Rules", prompt: "Write code")
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody)).object
            #expect(body["model"] == .string("test-model"))
            #expect(request.httpMethod == "POST")
            if kind == .anthropic {
                #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-secret")
                #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
                #expect(body["system"] == .string("Rules"))
            } else {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret")
            }
            if kind == .responses {
                #expect(body["store"] == .bool(false))
                #expect(body["instructions"] == .string("Rules"))
            }
        }
    }
    @Test("All model adapters attach the current frame using their native image shape")
    func imageRequestShapes() throws {
        let image = try ModelImage(data: Data([1, 2, 3]))
        for kind in ModelAdapters.all.map(\.kind) {
            var config = ModelConfiguration()
            config.kind = kind
            config.model = "vision-model"
            let request = try ModelClient.request(
                configuration: config, key: "", system: "Rules", prompt: "Inspect frame",
                image: image)
            let bodyData = try #require(request.httpBody)
            let body = try JSONDecoder().decode(JSONValue.self, from: bodyData).object
            let encoded = String(data: bodyData, encoding: .utf8) ?? ""
            #expect(encoded.contains("AQID"))
            switch kind {
            case .responses:
                let content = body["input"]?.array.first?.object["content"]?.array ?? []
                #expect(content.map { $0.object["type"]?.string } == ["input_text", "input_image"])
            case .chatCompletions:
                let content = body["messages"]?.array.last?.object["content"]?.array ?? []
                #expect(content.map { $0.object["type"]?.string } == ["text", "image_url"])
            case .anthropic:
                let content = body["messages"]?.array.first?.object["content"]?.array ?? []
                #expect(content.map { $0.object["type"]?.string } == ["text", "image"])
                #expect(content.last?.object["source"]?.object["media_type"] == .string("image/png"))
            default:
                Issue.record("No image shape check for \(kind.rawValue)")
            }
        }
    }
    @Test("Each provider extracts only the generated text blocks")
    func responses() async throws {
        let fixtures: [(ModelAPIKind, String)] = [
            (
                .responses,
                #"{"output":[{"type":"message","content":[{"type":"output_text","text":"script"}]}]}"#
            ),
            (.chatCompletions, #"{"choices":[{"message":{"content":"script"}}]}"#),
            (
                .anthropic,
                #"{"content":[{"type":"thinking","thinking":"private"},{"type":"text","text":"script"}]}"#
            ),
        ]
        for (kind, json) in fixtures {
            var config = ModelConfiguration()
            config.kind = kind
            config.model = "fake"
            let client = ModelClient(transport: MockModelTransport(response: json, status: 200))
            #expect(
                try await client.generate(configuration: config, key: "", system: "", prompt: "")
                    == "script")
        }
    }
    @Test("Saved configurations keep their API and an unknown API is rejected")
    func adapterRegistry() throws {
        let saved = #"{"kind":"anthropic","baseURL":"https://api.anthropic.com/v1","model":"m","maxOutputTokens":10}"#
        var config = try JSONDecoder().decode(ModelConfiguration.self, from: Data(saved.utf8))
        #expect(config.kind == .anthropic)
        #expect(try config.endpoint().absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(Set(ModelAdapters.all.map(\.kind)).count == ModelAdapters.all.count)
        config.kind = "unknown"
        #expect(throws: ModelError.self) { try config.endpoint() }
    }
    @Test("Credentials are tied to endpoint and unsafe remote plaintext is rejected")
    func endpointValidation() throws {
        var config = ModelConfiguration()
        let old = config.credentialAccount
        config.baseURL = "https://other.example/v1"
        #expect(config.credentialAccount != old)
        config.baseURL = "http://remote.example/v1"
        #expect(throws: ModelError.self) { try config.endpoint() }
        config.baseURL = "http://localhost:11434/v1"
        #expect(try config.endpoint().absoluteString == "http://localhost:11434/v1/responses")
        config.baseURL = "https://user:password@example.com/v1"
        #expect(throws: ModelError.self) { try config.endpoint() }
    }
    @Test("API errors do not echo raw error bodies or secret credentials")
    func apiErrors() async throws {
        var config = ModelConfiguration()
        config.model = "fake"
        let client = ModelClient(
            transport: MockModelTransport(response: "secret-in-server-error", status: 401))
        do {
            _ = try await client.generate(configuration: config, key: "secret", system: "", prompt: "")
            Issue.record("Expected failure")
        } catch {
            #expect(!error.localizedDescription.contains("secret"))
            #expect(error.localizedDescription.contains("401"))
        }
    }
}
