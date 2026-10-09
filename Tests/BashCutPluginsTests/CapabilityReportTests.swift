import BashCutPlugin
import BashCutProject
import BashCutTestSupport
import Foundation
import Testing

@testable import BashCutPlugins

/// Health checks that take a minute.
private struct SlowHealthTransport: PluginTransport {
    func call(plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue) async throws -> JSONValue {
        .null
    }

    func health(plugin: InstalledPlugin) async -> PluginHealth {
        try? await Task.sleep(for: .seconds(60))
        return PluginHealth(pluginID: plugin.id, state: .ready, dependencies: [])
    }
}

/// Capability reports and resolution failures (P2-G5).
struct CapabilityReportTests {
    @Test("Capability reports say missing, not_configured or unhealthy, per provider, with the same reason resolve throws")
    func reports() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        let service = sandbox.service
        let none = service.capabilityStatus("audio.beats", projectRoot: sandbox.project)
        #expect(none.reason == .missing && none.providers.isEmpty && !none.available)

        // An API window that excludes this host: installed, but it may not run.
        try sandbox.addPlugin(
            "test.future", providers: [PluginProvider(id: "future", capability: "audio.beats", name: "Future")],
            body: "exit 1", apiVersion: PluginAPI.current + 1)
        let outdated = service.capabilityStatus("audio.beats", projectRoot: sandbox.project)
        #expect(outdated.reason == .notConfigured)
        #expect(outdated.providers.first?.state == .notConfigured && outdated.providers.first?.detail != nil)

        var paid = PluginProvider(id: "sick", capability: "audio.beats", name: "Sick", priority: 3)
        paid.paid = true
        try sandbox.addPlugin("test.sick", providers: [paid], body: "exit 1", healthy: false)
        let unchecked = service.capabilityStatus("audio.beats", projectRoot: sandbox.project)
        #expect(unchecked.available && !unchecked.healthChecked)
        // A long deadline: under a loaded test run a real probe can take seconds.
        let checked = await service.checkedCapabilityStatus("audio.beats", projectRoot: sandbox.project, timeout: .seconds(120))
        #expect(checked.reason == .unhealthy && checked.healthChecked)
        let sick = try #require(checked.providers.first { $0.provider == "sick" })
        #expect(sick.state == .unhealthy && sick.paid && sick.priority == 3)
        #expect(sick.detail?.contains("Missing model") == true)
        let failure = await #expect(throws: CapabilityUnavailable.self) {
            try await service.resolve("audio.beats", preferredProvider: nil, projectRoot: sandbox.project)
        }
        #expect(failure?.report.reason == .unhealthy)
        #expect(failure?.localizedDescription.hasPrefix("No healthy provider is available for audio.beats") == true)

        try sandbox.addPlugin(
            "test.ok", providers: [PluginProvider(id: "ok", capability: "audio.beats", name: "OK")], body: "exit 1")
        let reports = await service.checkedCapabilityStatuses(
            ["audio.beats", "voice.synthesize"], projectRoot: sandbox.project, timeout: .seconds(120))
        #expect(reports.map(\.capability) == ["audio.beats", "voice.synthesize"])
        #expect(reports[0].available && reports[1].reason == .missing)
        #expect(reports[0].json.object["providers"]?.array.count == 3)
    }

    @Test("A health check that runs past the deadline leaves the report unchecked instead of holding it")
    func healthDeadline() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin(
            "test.slow", providers: [PluginProvider(id: "slow", capability: "audio.beats", name: "Slow")], body: "exit 1")
        let transport = SlowHealthTransport()
        let service = CapabilityService(
            roots: PluginRoots(user: sandbox.root.appendingPathComponent("user"), bundled: nil),
            transport: transport, healthTransport: transport)
        let start = ContinuousClock.now
        let report = await service.checkedCapabilityStatus(
            "audio.beats", projectRoot: sandbox.project, timeout: .milliseconds(100))
        #expect(ContinuousClock.now - start < .seconds(30))
        #expect(report.available && !report.healthChecked)
    }
}
