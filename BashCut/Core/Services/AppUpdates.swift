import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation
import Observation

/// A published BashCut release: the repository's latest GitHub release.
public struct AppRelease: Codable, Sendable, Equatable {
    public let version: String
    /// The release page, where the zip and dmg are.
    public let url: URL
    public let publishedAt: Date?
    /// The release notes, cut to `AppUpdateChecker.maximumNotes` characters.
    public let notes: String?

    public init(version: String, url: URL, publishedAt: Date? = nil, notes: String? = nil) {
        self.version = version
        self.url = url
        self.publishedAt = publishedAt
        self.notes = notes
    }

    /// Whether this release is newer than `version`. A version that does not parse counts as 0.0.0.
    public func isNewer(than version: String) -> Bool {
        guard let release = SemanticVersion(self.version) else { return false }
        return release > (SemanticVersion(version) ?? .zero)
    }
}

/// How this copy of BashCut was installed, which decides how it is updated.
public enum AppInstall: String, Sendable {
    /// `brew install --cask`: `brew upgrade --cask bashcut` updates it.
    case homebrew
    /// A zip or dmg from the release page.
    case direct
    /// The Mac App Store or TestFlight, which update it themselves; BashCut never checks.
    case appStore = "app-store"
    /// `scripts/run.sh` or Xcode: its version is not a release, so it is not checked by itself.
    case development

    static let caskrooms = ["/opt/homebrew/Caskroom/bashcut", "/usr/local/Caskroom/bashcut"]

    public static func current(bundle: Bundle = .main, fileManager: FileManager = .default) -> AppInstall {
        if PluginChannel.current == .appStore { return .appStore }
        if bundle.object(forInfoDictionaryKey: "BCDevelopmentBuild") as? Bool == true { return .development }
        let applications = ["/Applications", fileManager.homeDirectoryForCurrentUser.path + "/Applications"]
        let inApplications = applications.contains(bundle.bundleURL.deletingLastPathComponent().path)
        return inApplications && caskrooms.contains(where: fileManager.fileExists(atPath:)) ? .homebrew : .direct
    }

    /// Whether BashCut looks for updates itself; the App Store updates its copies.
    public var checksForUpdates: Bool { self != .appStore }
}

public struct AppUpdateError: LocalizedError, Sendable {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Reads the latest release of BashCut's GitHub repository (`BCRepositoryURL` in Info.plist).
public struct AppUpdateChecker: Sendable {
    static let maximumNotes = 2_000
    /// owner/name on github.com.
    public let repository: String
    let session: URLSession
    /// Development builds only (`BASHCUT_UPDATE_FEED`): a local file shaped like a GitHub release, read instead of
    /// GitHub so every state of Software Update can be tried. A missing file means no release.
    var feed: URL?

    /// Nil unless `repositoryURL` is `https://github.com/<owner>/<name>`.
    public init?(repositoryURL: URL?, session: URLSession = .shared) {
        guard let url = repositoryURL, url.scheme == "https", url.host() == "github.com" else { return nil }
        let parts = url.path().split(separator: "/").map(String.init)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) })
        else { return nil }
        repository = parts.joined(separator: "/")
        self.session = session
    }

    public var latestURL: URL { URL(string: "https://api.github.com/repos/\(repository)/releases/latest")! }

    /// The latest published release; nil when the repository has none yet.
    public func latest() async throws -> AppRelease? {
        if let feed {
            guard let data = try? Data(contentsOf: feed) else { return nil }
            return try Self.release(from: data)
        }
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw AppUpdateError("GitHub answered HTTP \(status)") }
        return try Self.release(from: data)
    }

    /// Decodes a GitHub release. Its tag (`v0.0.3`) must be a version and its page must be on github.com.
    static func release(from data: Data) throws -> AppRelease {
        struct GitHubRelease: Decodable {
            let tag_name: String // swiftlint:disable:this identifier_name
            let html_url: String // swiftlint:disable:this identifier_name
            let published_at: String? // swiftlint:disable:this identifier_name
            let body: String?
        }
        guard data.count <= 1_048_576 else { throw AppUpdateError("The release information is too large") }
        let release: GitHubRelease
        do { release = try JSONDecoder().decode(GitHubRelease.self, from: data) } catch {
            throw AppUpdateError("The release information is not valid: \(error.localizedDescription)")
        }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        guard SemanticVersion(version) != nil else { throw AppUpdateError("The release tag \(release.tag_name) is not a version") }
        guard let url = URL(string: release.html_url), url.scheme == "https", url.host() == "github.com" else {
            throw AppUpdateError("The release page is not on github.com")
        }
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AppRelease(
            version: version, url: url,
            publishedAt: release.published_at.flatMap { ISO8601DateFormatter().date(from: $0) },
            notes: notes.flatMap { $0.isEmpty ? nil : String($0.prefix(maximumNotes)) })
    }
}

/// Whether a newer BashCut has been released: checked once a day when a project opens (Settings › General) and on
/// demand (BashCut › Check for Updates…, `app update-check`). It only tells; updating is up to the user.
@MainActor @Observable
public final class AppUpdateModel {
    public enum Status: Equatable, Sendable {
        case idle, checking, upToDate
        case available(AppRelease)
        case failed(String)
    }

    public static let checkInterval: TimeInterval = 24 * 60 * 60
    public static let homebrewCommand = "brew upgrade --cask bashcut"

    public private(set) var status: Status = .idle
    public private(set) var checkedAt: Date?
    public let version: String
    public let build: String
    public let install: AppInstall

    @ObservationIgnored private let checker: AppUpdateChecker?
    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let checkedAt = "appUpdateCheckedAt"
        static let latest = "appUpdateLatest"
    }

    public init(
        version: String, build: String, install: AppInstall, checker: AppUpdateChecker?, defaults: UserDefaults = .standard
    ) {
        self.version = version
        self.build = build
        self.install = install
        self.checker = checker
        self.defaults = defaults
        checkedAt = defaults.object(forKey: Keys.checkedAt) as? Date
        // The last check's answer, so the notice stays between launches without asking GitHub again.
        if let data = defaults.data(forKey: Keys.latest),
           let latest = try? JSONDecoder().decode(AppRelease.self, from: data), latest.isNewer(than: version) {
            status = .available(latest)
        }
    }

    /// One model for every window, so a check runs once.
    public static let shared = forThisApp()

    /// Development builds read two test settings from the environment: `BASHCUT_UPDATE_FEED` (a local release
    /// file, see `AppUpdateChecker.feed`) and `BASHCUT_UPDATE_INSTALL` (`homebrew` or `direct`, to act like a release).
    public static func forThisApp(
        bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppUpdateModel {
        var install = AppInstall.current(bundle: bundle)
        var checker = AppUpdateChecker(
            repositoryURL: (bundle.object(forInfoDictionaryKey: "BCRepositoryURL") as? String).flatMap(URL.init(string:)))
        if install == .development {
            if let feed = environment["BASHCUT_UPDATE_FEED"], !feed.isEmpty {
                checker = checker ?? AppUpdateChecker(repositoryURL: URL(string: "https://github.com/local/feed"))
                checker?.feed = URL(fileURLWithPath: feed)
            }
            if let acting = environment["BASHCUT_UPDATE_INSTALL"].flatMap(AppInstall.init(rawValue:)),
               acting == .homebrew || acting == .direct {
                install = acting
            }
        }
        return AppUpdateModel(
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            install: install, checker: checker)
    }

    /// The newer release found by the last check.
    public var available: AppRelease? {
        if case .available(let release) = status { release } else { nil }
    }

    /// How to update: the Homebrew command, or nil to download from the release page.
    public var upgradeCommand: String? { install == .homebrew ? Self.homebrewCommand : nil }

    /// Asks GitHub now. The App Store's copies are not checked.
    @discardableResult
    public func check(now: Date = Date()) async -> Status {
        guard install.checksForUpdates else {
            status = .failed(String(localized: "The App Store and TestFlight update this copy of BashCut"))
            return status
        }
        guard let checker else {
            status = .failed(String(localized: "This build does not name its GitHub repository"))
            return status
        }
        status = .checking
        do {
            let latest = try await checker.latest()
            checkedAt = now
            defaults.set(now, forKey: Keys.checkedAt)
            if let latest, latest.isNewer(than: version) {
                defaults.set(try? JSONEncoder().encode(latest), forKey: Keys.latest)
                status = .available(latest)
            } else {
                defaults.removeObject(forKey: Keys.latest)
                status = .upToDate
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
        return status
    }

    /// Checks when the last successful check is a day old. Development builds and App Store copies are skipped.
    /// Returns a release that became available with this check.
    @discardableResult
    public func checkIfDue(now: Date = Date()) async -> AppRelease? {
        guard install == .homebrew || install == .direct else { return nil }
        if let checkedAt, now.timeIntervalSince(checkedAt) < Self.checkInterval { return nil }
        let before = available
        await check(now: now)
        guard let release = available, release != before else { return nil }
        return release
    }

    /// What `app update-check` and `app version` return.
    public var fields: JSONValue {
        var fields: [String: JSONValue] = [
            "version": .string(version), "build": .string(build), "install": .string(install.rawValue),
            "updateAvailable": .bool(available != nil),
            "checkedAt": checkedAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
        ]
        switch status {
        case .failed(let message): fields["error"] = .string(message)
        case .available(let release):
            fields["latest"] = .object([
                "version": .string(release.version), "url": .string(release.url.absoluteString),
                "publishedAt": release.publishedAt.map { .string(ISO8601DateFormatter().string(from: $0)) } ?? .null,
                "notes": release.notes.map(JSONValue.string) ?? .null,
            ])
            fields["update"] = .string(upgradeCommand ?? release.url.absoluteString)
        default: break
        }
        return .object(fields)
    }
}
