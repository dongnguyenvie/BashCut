import BashCutPlugin
import BashCutProject
import Foundation

/// Update Now for a Homebrew copy of BashCut: Homebrew updates its taps and downloads the new release while BashCut
/// still runs (`prepare`), then a helper that outlives the app waits for it to quit, runs
/// `brew upgrade --cask bashcut` from the download and opens the new version (`launchHelper`). Nothing is replaced
/// while BashCut runs, and a failed download leaves it running as it was.
public struct AppUpdateInstaller: Sendable {
    public struct Output: Sendable {
        public let status: Int32
        public let text: String
        public init(status: Int32, text: String) {
            self.status = status
            self.text = text
        }
    }

    /// Runs `brew` with arguments and returns its exit status and output; tests answer without Homebrew.
    public typealias Runner = @Sendable (_ brew: String, _ arguments: [String]) async -> Output

    /// Apple silicon, then Intel. An app opened from Finder has no shell PATH, so `brew` is found by its full path.
    public static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    static let cask = "bashcut"
    /// Set by the helper when `brew upgrade` failed: the log's path, read on the next launch.
    static let failedKey = "appUpdateInstallFailed"

    public let brew: String
    /// The app to open again after the upgrade (Homebrew puts the new version at the same path).
    public let app: URL
    /// The helper's output: `~/Library/Logs/BashCut/update.log`.
    public let log: URL
    let run: Runner

    public init(brew: String, app: URL, log: URL = AppUpdateInstaller.defaultLog, run: @escaping Runner = AppUpdateInstaller.brew) {
        self.brew = brew
        self.app = app
        self.log = log
        self.run = run
    }

    /// Nil when Homebrew is not installed where BashCut looks.
    public init?(app: URL, fileManager: FileManager = .default) {
        guard let brew = Self.brewPaths.first(where: fileManager.isExecutableFile(atPath:)) else { return nil }
        self.init(brew: brew, app: app)
    }

    public static let defaultLog = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/BashCut/update.log")

    /// Updates Homebrew's taps, checks that the cask offers a version newer than `current`, and downloads it.
    /// `progress` gets a short line for each step. Returns the version Homebrew will install.
    public func prepare(current: String, progress: @escaping @MainActor @Sendable (String) -> Void) async throws -> String {
        await progress(String(localized: "Updating Homebrew…"))
        try check(await run(brew, ["update", "--quiet"]), String(localized: "Homebrew could not update"))
        let info = await run(brew, ["info", "--cask", "--json=v2", Self.cask])
        try check(info, String(localized: "Homebrew does not know BashCut"))
        let version = try Self.caskVersion(from: Data(info.text.utf8))
        guard AppRelease(version: version, url: app).isNewer(than: current) else {
            throw AppUpdateError(String(format: String(
                localized: "Homebrew does not offer the new BashCut yet (it has %@); try again later"), version))
        }
        await progress(String(format: String(localized: "Downloading BashCut %@…"), version))
        try check(await run(brew, ["fetch", "--cask", Self.cask]), String(localized: "The download failed"))
        return version
    }

    /// The version in `brew info --cask --json=v2`.
    static func caskVersion(from data: Data) throws -> String {
        struct Info: Decodable { let casks: [[String: JSONValue]] }
        guard case .string(let version)? = (try? JSONDecoder().decode(Info.self, from: data))?.casks.first?["version"],
              SemanticVersion(version) != nil
        else { throw AppUpdateError(String(localized: "Homebrew's answer about BashCut is not valid")) }
        return version
    }

    private func check(_ output: Output, _ message: String) throws {
        guard output.status != 0 else { return }
        let detail = output.text.split(separator: "\n").last { $0.contains("Error") } ?? output.text.split(separator: "\n").last
        throw AppUpdateError(detail.map { "\(message): \($0.prefix(300))" } ?? message)
    }

    /// Starts the helper for the app with process id `pid`. It waits up to five minutes for the app to quit
    /// (nothing changes if it does not), upgrades without another tap update, records a failure in `defaults`
    /// for the next launch, and opens the app again either way, as a new instance on the same `socket` when BashCut
    /// runs on its own (`BASHCUT_SOCKET`). The returned process can be stopped to cancel.
    public func launchHelper(
        pid: Int32, defaultsDomain: String, socket: String? = ProcessInfo.processInfo.environment["BASHCUT_SOCKET"]
    ) throws -> Process {
        try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", Self.script, "bashcut-update", String(pid), brew, app.path, log.path,
                             defaultsDomain, Self.failedKey, socket ?? ""]
        process.environment = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "\(URL(fileURLWithPath: brew).deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin",
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// $1 pid, $2 brew, $3 app, $4 log, $5 defaults domain, $6 failure key, $7 socket or empty.
    static let script = #"""
        exec >>"$4" 2>&1
        print "== $(date '+%Y-%m-%d %H:%M:%S') BashCut update: waiting for BashCut ($1) to quit"
        for i in {1..300}; do kill -0 "$1" 2>/dev/null || break; sleep 1; done
        if kill -0 "$1" 2>/dev/null; then print "BashCut did not quit; nothing was updated"; exit 1; fi
        if HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 "$2" upgrade --cask bashcut; then
          print "Updated"
        else
          print "brew upgrade failed"
          /usr/bin/defaults write "$5" "$6" -string "$4"
        fi
        if [[ -n "$7" ]]; then /usr/bin/open -n --env "BASHCUT_SOCKET=$7" "$3"; else /usr/bin/open "$3"; fi
        """#

    /// Runs `brew` with no input (it can never wait on a prompt) for at most ten minutes.
    public static let brew: Runner = { brew, arguments in
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = arguments
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = "\(URL(fileURLWithPath: brew).deletingLastPathComponent().path):/usr/bin:/bin:/usr/sbin:/sbin"
            environment["HOMEBREW_NO_ENV_HINTS"] = "1"
            if arguments.first != "update" { environment["HOMEBREW_NO_AUTO_UPDATE"] = "1" }
            process.environment = environment
            process.standardInput = FileHandle.nullDevice
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            do { try process.run() } catch { return Output(status: -1, text: error.localizedDescription) }
            let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 600, execute: timeout)
            // Read before waiting, so a large output cannot fill the pipe and block the process.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            timeout.cancel()
            return Output(status: process.terminationStatus, text: String(bytes: data, encoding: .utf8) ?? "")
        }.value
    }
}
