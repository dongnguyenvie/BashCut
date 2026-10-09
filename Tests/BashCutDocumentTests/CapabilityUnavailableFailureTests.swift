import BashCutAutomation
import BashCutDocument
import BashCutProject
import Testing

@testable import BashCutPlugins

@MainActor
struct CapabilityUnavailableFailureTests {
    private let report = CapabilityReport(
        capability: "voice.synthesize", kind: nil,
        providers: [CapabilityProviderStatus(
            plugin: "acme.tts", provider: "acme", name: "Acme", priority: 0, paid: true, state: .notConfigured,
            detail: "Turned off")],
        healthChecked: false)

    @Test("No provider is category capability_missing with the reason, every provider and capabilities get as next step")
    func typed() {
        let failure = RPCFailure.from(CapabilityUnavailable(report)).typed
        #expect(failure.category == .capabilityMissing && failure.code == -32000)
        #expect(failure.message == "No enabled provider for voice.synthesize. Acme: Turned off")
        let data = failure.data?.object ?? [:]
        #expect(data["reason"] == .string("not_configured") && data["retryable"] == .bool(false))
        #expect(data["providers"]?.array.first?.object["paid"] == .bool(true))
        #expect(data["remediation"]?.object["command"] == .string("capabilities.get"))
    }

    @Test("A job that fails on a typed error keeps its category; other failures have none")
    func jobCategory() async throws {
        let center = JobCenter()
        let unavailable = CapabilityUnavailable(report)
        let typed = center.start("voice.speak", author: .claude, work: { _ in throw unavailable })
        let plain = center.start("voice.speak", author: .claude, work: { _ in throw ProjectError.invalid("bad") })
        let first = try #require(try await center.wait(typed, for: .seconds(5), interval: .milliseconds(5)))
        let second = try #require(try await center.wait(plain, for: .seconds(5), interval: .milliseconds(5)))
        #expect(first.job.json.object["errorCategory"] == .string("capability_missing"))
        #expect(second.job.state == .failed && second.job.json.object["errorCategory"] == .null)
    }
}
