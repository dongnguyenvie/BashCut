import BashCutPlugin
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutPlugins

/// Usage, request IDs and dry runs on capability calls (P2-G4).
struct PluginCallContextTests {
    @Test("Inside a job's call context the request carries requestId and the provider's usage is recorded")
    func usageAndRequestID() async throws {
        let (sandbox, transport, service) = try echoService(result: .object([
            "text": .string("ok"),
            "usage": .object(["units": .object(["characters": .integer(120), "bad": .integer(-1)]), "costUSD": .number(0.25)]),
        ]))
        defer { sandbox.cleanup() }
        let usage = PluginUsageRecorder()
        let context = PluginCallContext(usage: usage, requestID: "vo-intro-1")
        for _ in 0..<2 {
            _ = try await PluginCallContext.$current.withValue(context) {
                try await service.run(EchoCapability(text: "a"), preferredProvider: nil, projectRoot: sandbox.project)
            }
        }
        #expect(await transport.calls.last?.params.object["requestId"] == .string("vo-intro-1"))
        let json = usage.json
        #expect(json["provider"] == .string("test.echo/test.echo.provider"))
        #expect(json["units"] == .object(["characters": .number(240)]))
        #expect(json["costUSD"] == .number(0.5) && json["costSource"] == .string("provider"))
        // Outside a job nothing is added to the request.
        _ = try await service.run(EchoCapability(text: "b"), preferredProvider: nil, projectRoot: sandbox.project)
        #expect(await transport.calls.last?.params.object["requestId"] == nil)
    }

    @Test("A cost the provider marks charged: false, or no cost at all, is not a charge")
    func uncharged() {
        let usage = PluginUsageRecorder()
        usage.record(provider: "p/a", usage: .object(["costUSD": .number(1), "charged": .bool(false)]))
        usage.record(provider: "p/a", usage: nil)
        let json = usage.json
        #expect(json["costUSD"] == .null && json["costSource"] == .null && json["units"] == .null)
        #expect(json["provider"] == .string("p/a"))
        #expect(PluginUsageRecorder().json["provider"] == .null)
    }

    @Test("A dry run freezes the request without option values; only an estimating provider is asked, with dryRun")
    func dryRun() async throws {
        var paid = PluginProvider(id: "test.echo.provider", capability: "text.echo", name: "Echo")
        paid.paid = true
        let (sandbox, transport, plainService) = try echoService(
            result: .object(["estimate": .object(["units": .object(["characters": .integer(5)]), "costUSD": .number(0.01)])]),
            provider: paid)
        defer { sandbox.cleanup() }
        var service = plainService
        service.optionValues = { _ in ["apiKey": .string("secret")] }
        let context = PluginCallContext(requestID: "r1", dryRun: true)
        let outputRoot = sandbox.project.appendingPathComponent("generated")
        func frozen() async throws -> JSONValue {
            do {
                _ = try await PluginCallContext.$current.withValue(context) {
                    try await service.run(
                        EchoCapability(text: "hello", outputRoot: outputRoot), preferredProvider: nil,
                        projectRoot: sandbox.project)
                }
            } catch let dryRun as PluginDryRun { return dryRun.request }
            Issue.record("No dry run")
            return .null
        }
        let request = try await frozen()
        #expect(await transport.calls.isEmpty)
        #expect(request.object["paid"] == .bool(true) && request.object["estimate"] == .null)
        #expect(request.object["params"]?.object["text"] == .string("hello"))
        #expect(request.object["params"]?.object["requestId"] == .string("r1"))
        #expect(request.object["params"]?.object["options"] == nil && request.object["options"] == .array([.string("apiKey")]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: outputRoot.path).isEmpty)

        paid.estimates = true
        try sandbox.addPlugin("test.echo", providers: [paid], body: "exit 1")
        let estimated = try await frozen()
        let call = try #require(await transport.calls.first)
        #expect(call.params.object["dryRun"] == .bool(true))
        #expect(estimated.object["estimate"] == .object([
            "units": .object(["characters": .number(5)]), "costUSD": .number(0.01),
        ]))
        #expect(estimated.object["estimateSource"] == .string("provider"))
    }

    private func echoService(result: JSONValue, provider: PluginProvider? = nil) throws
        -> (PluginSandbox, RecordingTransport, CapabilityService)
    {
        let sandbox = try PluginSandbox()
        try sandbox.addPlugin(
            "test.echo",
            providers: [provider ?? PluginProvider(id: "test.echo.provider", capability: "text.echo", name: "Echo")],
            body: "exit 1")
        let transport = RecordingTransport(result: result)
        let service = CapabilityService(
            roots: PluginRoots(user: sandbox.root.appendingPathComponent("user"), bundled: nil),
            transport: transport, healthTransport: transport)
        return (sandbox, transport, service)
    }
}
