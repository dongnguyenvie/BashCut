import BashCutProject
import Darwin
import Foundation

public struct PluginDependencyStatus: Sendable, Equatable, Identifiable {
    public enum State: String, Sendable { case available, missing, failed }

    public let id: String
    public let name: String
    public let state: State
    public let detail: String
}

public struct PluginHealth: Sendable, Equatable {
    public enum State: String, Sendable { case ready, degraded }

    public let pluginID: String
    public let state: State
    public let dependencies: [PluginDependencyStatus]

    public init(pluginID: String, state: State, dependencies: [PluginDependencyStatus]) {
        self.pluginID = pluginID
        self.state = state
        self.dependencies = dependencies
    }
}

public struct PluginProcessRunner: Sendable {
    struct Execution: Sendable {
        let executable: URL
        let arguments: [String]
        let directory: URL
        let environment: [String: String]
        let input: Data
        let outputLimit: Int
    }

    public let timeout: TimeInterval
    public let maximumOutputBytes: Int

    public init(timeout: TimeInterval = 120, maximumOutputBytes: Int = 8 * 1024 * 1024) {
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
    }

    /// Starts one isolated plugin process for one request. The entrypoint receives `rpc` and one
    /// JSON request on stdin, then must emit exactly one JSON response on stdout and exit.
    public func call(
        plugin: InstalledPlugin, method: String, provider: String? = nil,
        params: JSONValue = .object([:])
    ) async throws -> JSONValue {
        guard method.range(of: "^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$", options: .regularExpression) != nil
        else { throw PluginError.invalid("Invalid plugin method") }
        let request = PluginRPCRequest(
            apiVersion: min(plugin.manifest.apiVersion, PluginAPI.current), method: method, provider: provider,
            params: params)
        let data = try JSONEncoder().encode(request)
        guard data.count <= 1024 * 1024 else {
            throw PluginError.invalid("Plugin request is too large")
        }
        let responseData = try await execute(
            plugin: plugin, arguments: ["rpc"], input: data + Data([0x0A]))
        let response: PluginRPCResponse
        do {
            response = try JSONDecoder().decode(PluginRPCResponse.self, from: responseData)
        } catch {
            throw PluginError.invalid("Plugin returned an invalid JSON response")
        }
        guard response.id == request.id else {
            throw PluginError.invalid("Plugin response id did not match the request")
        }
        if let failure = response.error {
            throw PluginError.invalid("Plugin error \(failure.code): \(failure.message)")
        }
        guard let result = response.result else {
            throw PluginError.invalid("Plugin returned neither a result nor an error")
        }
        return result
    }

    public func health(plugin: InstalledPlugin) async -> PluginHealth {
        var statuses: [PluginDependencyStatus] = []
        for dependency in plugin.manifest.dependencies {
            do {
                _ = try await execute(
                    plugin: plugin, command: dependency.probe, input: Data(),
                    outputLimit: 256 * 1024)
                statuses.append(
                    PluginDependencyStatus(
                        id: dependency.id, name: dependency.name, state: .available,
                        detail: "Available"))
            } catch {
                statuses.append(
                    PluginDependencyStatus(
                        id: dependency.id, name: dependency.name,
                        state: dependency.install == nil ? .failed : .missing,
                        detail: error.localizedDescription))
            }
        }
        return PluginHealth(
            pluginID: plugin.id,
            state: statuses.allSatisfy { $0.state == .available } ? .ready : .degraded,
            dependencies: statuses)
    }

    private func execute(
        plugin: InstalledPlugin, arguments: [String], input: Data
    ) async throws -> Data {
        let executable = try plugin.entrypointURL()
        return try await execute(
            Execution(
                executable: executable, arguments: arguments, directory: plugin.directory,
                environment: Self.environment(for: plugin), input: input,
                outputLimit: maximumOutputBytes))
    }

    private func execute(
        plugin: InstalledPlugin, command: PluginCommand, input: Data, outputLimit: Int
    ) async throws -> Data {
        try plugin.manifest.validate()
        let executable: URL
        let arguments: [String]
        if command.executable.contains("/") {
            executable = plugin.directory.appendingPathComponent(command.executable).standardizedFileURL
            guard executable.path.hasPrefix(plugin.directory.standardizedFileURL.path + "/"),
                FileManager.default.isExecutableFile(atPath: executable.path)
            else { throw PluginError.invalid("Dependency probe executable is unavailable") }
            arguments = command.arguments
        } else {
            executable = URL(fileURLWithPath: "/usr/bin/env")
            arguments = [command.executable] + command.arguments
        }
        return try await execute(
            Execution(
                executable: executable, arguments: arguments, directory: plugin.directory,
                environment: Self.environment(for: plugin), input: input, outputLimit: outputLimit))
    }

    /// Runs the child in its own process group and waits without blocking a cooperative thread.
    /// Cancellation, timeout and oversized output terminate the whole group, including grandchildren.
    private func execute(_ execution: Execution) async throws -> Data {
        let manager = FileManager.default
        let runDirectory = manager.temporaryDirectory.appendingPathComponent(
            "BashCutPluginRuns/" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(
            at: runDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: runDirectory) }
        let inputURL = runDirectory.appendingPathComponent("input.json")
        let outputURL = runDirectory.appendingPathComponent("output.json")
        let errorURL = runDirectory.appendingPathComponent("stderr.log")
        try execution.input.write(to: inputURL, options: .atomic)

        let child = try ChildProcess.spawn(
            execution, input: inputURL.path, output: outputURL.path, error: errorURL.path)
        let deadline = Date().addingTimeInterval(timeout)
        var failure: PluginError?
        var status: Int32?
        while status == nil {
            if let exited = child.reap() {
                status = exited
                break
            }
            if Task.isCancelled {
                failure = .invalid("Plugin request was cancelled")
            } else if Date() >= deadline {
                failure = .invalid("Plugin request timed out")
            } else if Self.fileSize(outputURL) > execution.outputLimit {
                failure = .invalid("Plugin response is too large")
            }
            if failure != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        // The leader may be gone while helpers it started still run; one request owns the whole group.
        if let failure {
            await child.terminateGroup()
            throw failure
        }
        child.signalGroup(SIGKILL)
        guard status == 0 else {
            let data = (try? Data(contentsOf: errorURL)) ?? Data()
            let detail = (String(bytes: data.suffix(4_000), encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PluginError.invalid(
                detail.isEmpty ? "Plugin exited with status \(status ?? -1)" : "Plugin failed: \(detail)")
        }
        guard Self.fileSize(outputURL) <= execution.outputLimit else {
            throw PluginError.invalid("Plugin response is too large")
        }
        return (try? Data(contentsOf: outputURL)) ?? Data()
    }

    private static func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
    }

    static func environment(for plugin: InstalledPlugin) -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]
        for key in ["HOME", "PATH", "TMPDIR", "LANG", "LC_ALL"] {
            if let value = source[key] { environment[key] = value }
        }
        environment["BASHCUT_PLUGIN_ID"] = plugin.id
        environment["BASHCUT_PLUGIN_DIR"] = plugin.directory.path
        environment["BASHCUT_PLUGIN_API_VERSION"] = String(plugin.manifest.apiVersion)
        return environment
    }
}

/// A spawned plugin process that leads its own process group.
private struct ChildProcess: Sendable {
    let pid: pid_t

    static func spawn(
        _ execution: PluginProcessRunner.Execution, input: String, output: String, error: String
    ) throws -> ChildProcess {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, input, O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, output, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_addopen(&actions, 2, error, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_addchdir_np(&actions, execution.directory.path)
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(
            &attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF))
        posix_spawnattr_setpgroup(&attributes, 0)
        var defaults = sigset_t()
        sigemptyset(&defaults)
        sigaddset(&defaults, SIGPIPE)
        posix_spawnattr_setsigdefault(&attributes, &defaults)

        let arguments = [execution.executable.path] + execution.arguments
        let environment = execution.environment.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let result = withCStrings(arguments) { argv in
            withCStrings(environment) { envp in
                posix_spawn(&pid, execution.executable.path, &actions, &attributes, argv, envp)
            }
        }
        guard result == 0 else {
            throw PluginError.invalid("Cannot start plugin: \(String(cString: strerror(result)))")
        }
        return ChildProcess(pid: pid)
    }

    /// Returns the exit status once the leader has exited, or nil while it is still running.
    func reap() -> Int32? {
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        guard result == pid else { return result < 0 ? -1 : nil }
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : 128 + signal
    }

    func signalGroup(_ signal: Int32) { _ = Darwin.kill(-pid, signal) }

    /// SIGTERM to the group, a short grace period, then SIGKILL and reap the leader.
    func terminateGroup() async {
        signalGroup(SIGTERM)
        for _ in 0..<25 where reap() == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        signalGroup(SIGKILL)
        var status: Int32 = 0
        _ = waitpid(pid, &status, 0)
    }
}

func withCStrings<R>(_ strings: [String], _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R) -> R {
    var pointers = strings.map { strdup($0) }
    pointers.append(nil)
    defer { pointers.forEach { free($0) } }
    return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
}
