import BashCutPlugin
import BashCutProject
import Foundation
import Testing

@testable import BashCutPlugins

/// Plugin review checks (#451): results in the review's shape, marked with their plugin; failures and slow checks
/// are isolated.
struct ReviewCheckTests {
    func provider(_ id: String, timeout: Int? = nil) -> PluginProvider {
        PluginProvider(id: id, capability: PluginAPI.reviewCheck, name: id, timeoutSeconds: timeout)
    }

    /// The request carries a whole project, whose own `id` fields confuse the sandbox's sed; read the request ID
    /// with Perl's core JSON module instead.
    func body(_ script: String) -> String {
        #"id=$(printf '%s' "$input" | perl -MJSON::PP -0777 -ne 'print decode_json($_)->{id}')"# + "\n" + script
    }

    func project() -> Project {
        var project = Project(name: "Checks", fps: FrameRate(30, 1))
        let index = project.tracks.firstIndex { $0.id == "v1" }!
        project.tracks[index].items = [Item(id: "clip", media: "m", at: 0, duration: 300)]
        return project
    }

    @Test("Every enabled check runs; issues keep their shape, get the plugin as source and the provider as ID prefix")
    func collects() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        let issues = #"{"issues":[{"id":"hook","title":"Weak hook","detail":"No face","frame":12,"endFrame":9000,"#
            + #""severity":"error","fix":{"command":"timeline.apply","arguments":{"label":"x"},"hint":"Open on a face"}},"#
            + #"{"id":"brand","title":"Logo missing","frame":-5}]}"#
        try sandbox.addPlugin(
            "test.hook", providers: [provider("test.hook.score")], body: body("""
                case "$input" in *'"revision"'*'"project"'*|*'"project"'*'"revision"'*) ;; *) exit 3 ;; esac
                printf '{"id":"%s","result":%s}\\n' "$id" '\(issues)'
                """), apiVersion: 9)
        try sandbox.addPlugin(
            "test.contrast", providers: [provider("test.contrast.check")], body: body("""
                printf '{"id":"%s","result":{"issues":[]}}\\n' "$id"
                """), apiVersion: 9)
        let service = sandbox.service
        let providers = service.reviewCheckProviders(projectRoot: sandbox.project)
        #expect(Set(providers.map(\.provider.id)) == ["test.hook.score", "test.contrast.check"])
        let found = await service.runReviewChecks(providers, project: project(), projectRoot: sandbox.project)
        #expect(found.map(\.id) == ["test.hook.score:hook", "test.hook.score:brand"])
        let hook = try #require(found.first)
        #expect(hook.severity == .error)
        #expect(hook.source == "test.hook")
        #expect(hook.endFrame == 300)
        #expect(hook.fix?.command == "timeline.apply")
        #expect(hook.json.object["source"] == .string("test.hook"))
        #expect(found.last?.severity == .warning)
        #expect(found.last?.frame == 0)
        // A project turns a check off by provider or plugin ID.
        #expect(service.reviewCheckProviders(projectRoot: sandbox.project, disabled: ["test.hook"]).map(\.provider.id)
            == ["test.contrast.check"])
        #expect(service.reviewCheckProviders(projectRoot: sandbox.project, disabled: ["test.contrast.check"])
            .map(\.provider.id) == ["test.hook.score"])
    }

    @Test("A failing, malformed or slow check becomes an info issue and the others still report")
    func isolation() async throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin("test.crash", providers: [provider("test.crash.check")], body: "exit 2", apiVersion: 9)
        try sandbox.addPlugin(
            "test.bad", providers: [provider("test.bad.check")], body: body("""
                printf '{"id":"%s","result":{"issues":[{"title":"No id"}]}}\\n' "$id"
                """), apiVersion: 9)
        try sandbox.addPlugin(
            "test.slow", providers: [provider("test.slow.check", timeout: 10)], body: "sleep 30", apiVersion: 9)
        try sandbox.addPlugin(
            "test.good", providers: [provider("test.good.check")], body: body("""
                printf '{"id":"%s","result":{"issues":[{"id":"ok","title":"Fine","frame":3,"severity":"info"}]}}\\n' "$id"
                """), apiVersion: 9)
        let service = sandbox.service
        let providers = service.reviewCheckProviders(projectRoot: sandbox.project)
        let start = ContinuousClock.now
        // The slow provider's own timeoutSeconds (10, the least a manifest allows) cuts it short; the others keep 30 s.
        let found = await service.runReviewChecks(providers, project: project(), projectRoot: sandbox.project)
        // The slow plugin sleeps 30 s; stopping it at its 10 s limit ends well before that, even on a busy machine.
        #expect(start.duration(to: .now) < .seconds(25), "the slow check must be stopped at the timeout")
        #expect(found.contains { $0.id == "test.good.check:ok" && $0.source == "test.good" })
        for plugin in ["test.crash", "test.bad", "test.slow"] {
            let failure = found.first { $0.source == plugin }
            #expect(failure?.title == "Plugin check failed", "\(plugin)")
            #expect(failure?.severity == .info, "\(plugin)")
        }
        #expect(found.first { $0.source == "test.slow" }?.detail.contains("within 10 s") == true)
    }

    @Test("Checks declared under an older apiVersion are not offered")
    func apiVersion() throws {
        let sandbox = try PluginSandbox()
        defer { sandbox.cleanup() }
        try sandbox.addPlugin("test.old", providers: [provider("test.old.check")], body: "exit 0", apiVersion: 8)
        #expect(sandbox.service.reviewCheckProviders(projectRoot: sandbox.project).isEmpty)
    }
}
