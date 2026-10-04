import Foundation
import Testing

@testable import BashCutDocument

/// Answers requests from canned responses keyed by URL; no network is used.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [URL: (Int, Data)] = [:]
    static let lock = NSLock()

    static func serve(_ url: URL, status: Int, body: Data) {
        lock.lock()
        responses[url] = (status, body)
        lock.unlock()
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        let (status, body) = Self.responses[url] ?? (500, Data())
        Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite("App updates")
struct AppUpdateTests {
    private func release(tag: String, url: String = "https://github.com/acme/app/releases/tag/v1", body: String? = "Notes")
        -> Data {
        var fields: [String: String] = ["tag_name": tag, "html_url": url, "published_at": "2026-10-04T15:00:00Z"]
        if let body { fields["body"] = body }
        return (try? JSONEncoder().encode(fields)) ?? Data()
    }

    private func checker(_ name: String) -> AppUpdateChecker {
        AppUpdateChecker(repositoryURL: URL(string: "https://github.com/acme/\(name)"), session: StubProtocol.session())!
    }

    private func defaults() -> UserDefaults {
        let name = "app-update-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func readsAGitHubRelease() throws {
        let parsed = try AppUpdateChecker.release(from: release(tag: "v0.0.4", body: "  Fixes Codex MCP.\n"))
        #expect(parsed.version == "0.0.4")
        #expect(parsed.url.absoluteString == "https://github.com/acme/app/releases/tag/v1")
        #expect(parsed.notes == "Fixes Codex MCP.")
        #expect(parsed.publishedAt == ISO8601DateFormatter().date(from: "2026-10-04T15:00:00Z"))
        #expect(try AppUpdateChecker.release(from: release(tag: "1.2.0", body: nil)).version == "1.2.0")
    }

    @Test func refusesReleasesItCannotTrust() {
        #expect(throws: AppUpdateError.self) { try AppUpdateChecker.release(from: release(tag: "nightly")) }
        #expect(throws: AppUpdateError.self) {
            try AppUpdateChecker.release(from: release(tag: "v1.0.0", url: "https://example.com/bashcut.dmg"))
        }
        #expect(throws: AppUpdateError.self) {
            try AppUpdateChecker.release(from: release(tag: "v1.0.0", url: "http://github.com/acme/app"))
        }
        #expect(throws: AppUpdateError.self) { try AppUpdateChecker.release(from: Data("{}".utf8)) }
    }

    @Test func comparesVersions() {
        let url = URL(string: "https://github.com/acme/app")!
        #expect(AppRelease(version: "0.0.4", url: url).isNewer(than: "0.0.3"))
        #expect(AppRelease(version: "0.1.0", url: url).isNewer(than: "0.0.10"))
        #expect(!AppRelease(version: "0.0.3", url: url).isNewer(than: "0.0.3"))
        #expect(!AppRelease(version: "0.0.2", url: url).isNewer(than: "0.0.3"))
        #expect(AppRelease(version: "0.0.1", url: url).isNewer(than: ""))
    }

    @Test func onlyAcceptsGitHubRepositoryURLs() {
        #expect(AppUpdateChecker(repositoryURL: URL(string: "https://github.com/dongnguyenvie/BashCut"))?.repository
            == "dongnguyenvie/BashCut")
        #expect(AppUpdateChecker(repositoryURL: URL(string: "https://github.com/dongnguyenvie/BashCut/"))?.latestURL
            .absoluteString == "https://api.github.com/repos/dongnguyenvie/BashCut/releases/latest")
        for bad in ["http://github.com/a/b", "https://gitlab.com/a/b", "https://github.com/a", "https://github.com/a/b/c",
                    "https://github.com/a/b%3Fx"] {
            #expect(AppUpdateChecker(repositoryURL: URL(string: bad)) == nil, "\(bad)")
        }
        #expect(AppUpdateChecker(repositoryURL: nil) == nil)
    }

    @MainActor @Test func checkFindsANewerReleaseAndRemembersIt() async {
        let checker = checker("newer")
        StubProtocol.serve(checker.latestURL, status: 200, body: release(tag: "v0.0.4"))
        let defaults = defaults()
        let model = AppUpdateModel(version: "0.0.3", build: "6", install: .homebrew, checker: checker, defaults: defaults)
        #expect(await model.check() == .available(model.available!))
        #expect(model.available?.version == "0.0.4")
        #expect(model.upgradeCommand == "brew upgrade --cask bashcut")
        guard case .object(let fields) = model.fields else { Issue.record("fields"); return }
        #expect(fields["updateAvailable"] == .bool(true))
        #expect(fields["update"] == .string("brew upgrade --cask bashcut"))
        // The next launch shows the notice from the remembered answer, without a request.
        let reopened = AppUpdateModel(version: "0.0.3", build: "6", install: .homebrew, checker: nil, defaults: defaults)
        #expect(reopened.available?.version == "0.0.4")
        // After updating, the remembered release is not newer any more.
        let updated = AppUpdateModel(version: "0.0.4", build: "7", install: .homebrew, checker: nil, defaults: defaults)
        #expect(updated.available == nil)
    }

    @MainActor @Test func upToDateAndNoReleases() async {
        let current = checker("current")
        StubProtocol.serve(current.latestURL, status: 200, body: release(tag: "v0.0.3"))
        let model = AppUpdateModel(version: "0.0.3", build: "6", install: .direct, checker: current, defaults: defaults())
        #expect(await model.check() == .upToDate)
        #expect(model.checkedAt != nil)

        let empty = checker("empty")
        StubProtocol.serve(empty.latestURL, status: 404, body: Data())
        let none = AppUpdateModel(version: "0.0.3", build: "6", install: .direct, checker: empty, defaults: defaults())
        #expect(await none.check() == .upToDate)
    }

    @MainActor @Test func failuresAreReportedAndNotRemembered() async {
        let broken = checker("broken")
        StubProtocol.serve(broken.latestURL, status: 503, body: Data())
        let defaults = defaults()
        let model = AppUpdateModel(version: "0.0.3", build: "6", install: .direct, checker: broken, defaults: defaults)
        guard case .failed(let message) = await model.check() else { Issue.record("expected a failure"); return }
        #expect(message.contains("503"))
        #expect(model.checkedAt == nil)
        // A failed check is retried at the next project open rather than waiting a day.
        StubProtocol.serve(broken.latestURL, status: 200, body: release(tag: "v0.0.5"))
        #expect(await model.checkIfDue()?.version == "0.0.5")
    }

    @MainActor @Test func dailyCheckRunsOncePerDayAndOnlyForReleases() async {
        let daily = checker("daily")
        StubProtocol.serve(daily.latestURL, status: 200, body: release(tag: "v0.0.4"))
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AppUpdateModel(version: "0.0.3", build: "6", install: .direct, checker: daily, defaults: defaults())
        #expect(await model.checkIfDue(now: start)?.version == "0.0.4")
        // Already known: not announced again, and not asked again within a day.
        StubProtocol.serve(daily.latestURL, status: 200, body: release(tag: "v0.0.9"))
        #expect(await model.checkIfDue(now: start.addingTimeInterval(3600)) == nil)
        #expect(model.available?.version == "0.0.4")
        #expect(await model.checkIfDue(now: start.addingTimeInterval(AppUpdateModel.checkInterval))?.version == "0.0.9")

        for install in [AppInstall.development, .appStore] {
            let skipped = AppUpdateModel(version: "0.0.1", build: "1", install: install, checker: daily, defaults: defaults())
            #expect(await skipped.checkIfDue(now: start) == nil)
            #expect(skipped.checkedAt == nil)
        }
        let store = AppUpdateModel(version: "0.0.1", build: "1", install: .appStore, checker: daily, defaults: defaults())
        guard case .failed = await store.check() else { Issue.record("App Store copies are not checked"); return }
    }

    @Test func developmentFeedReplacesGitHub() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var checker = checker("feed")
        checker.feed = folder.appendingPathComponent("release.json")
        #expect(try await checker.latest() == nil)
        try release(tag: "v9.9.9").write(to: folder.appendingPathComponent("release.json"))
        #expect(try await checker.latest()?.version == "9.9.9")
    }

    @MainActor @Test func testSettingsOnlyApplyToDevelopmentBuilds() {
        // The test runner is not a development build of BashCut, so the environment is ignored.
        let model = AppUpdateModel.forThisApp(
            bundle: .main, environment: ["BASHCUT_UPDATE_FEED": "/tmp/x.json", "BASHCUT_UPDATE_INSTALL": "homebrew"])
        #expect(model.install != .homebrew || AppInstall.current() == .homebrew)
    }
}
