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
}

public struct PluginProcessRunner: Sendable {
    private struct Execution: Sendable {
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
        let request = PluginRPCRequest(method: method, provider: provider, params: params)
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

    private func execute(_ execution: Execution) async throws -> Data {
        let timeout = timeout
        return try await Task.detached { try Self.executeBlocking(execution, timeout: timeout) }.value
    }

    private static func executeBlocking(_ execution: Execution, timeout: TimeInterval) throws -> Data {
        let manager = FileManager.default
        let runDirectory = manager.temporaryDirectory.appendingPathComponent(
            "BashCutPluginRuns/" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(
            at: runDirectory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: runDirectory) }

        let inputURL = runDirectory.appendingPathComponent("input.json")
        let outputURL = runDirectory.appendingPathComponent("output.json")
        let errorURL = runDirectory.appendingPathComponent("stderr.log")
        try execution.input.write(to: inputURL, options: .atomic)
        manager.createFile(atPath: outputURL.path, contents: nil)
        manager.createFile(atPath: errorURL.path, contents: nil)
        let inputHandle = try FileHandle(forReadingFrom: inputURL)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? inputHandle.close()
            try? outputHandle.close()
            try? errorHandle.close()
        }

        let process = Process()
        process.executableURL = execution.executable
        process.arguments = execution.arguments
        process.currentDirectoryURL = execution.directory
        process.environment = execution.environment
        process.standardInput = inputHandle
        process.standardOutput = outputHandle
        process.standardError = errorHandle
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        var failure: PluginError?
        while process.isRunning {
            if Task.isCancelled {
                failure = .invalid("Plugin request was cancelled")
                break
            }
            if Date() >= deadline {
                failure = .invalid("Plugin request timed out")
                break
            }
            let size = ((try? manager.attributesOfItem(atPath: outputURL.path)[.size]) as? NSNumber)?
                .intValue ?? 0
            if size > execution.outputLimit {
                failure = .invalid("Plugin response is too large")
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        if failure != nil, process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.05)
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        if let failure { throw failure }
        guard process.terminationStatus == 0 else {
            let data = (try? Data(contentsOf: errorURL)) ?? Data()
            let detail = (String(bytes: data.suffix(4_000), encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PluginError.invalid(
                detail.isEmpty ? "Plugin exited with status \(process.terminationStatus)"
                    : "Plugin failed: \(detail)")
        }
        try outputHandle.synchronize()
        let data = try Data(contentsOf: outputURL)
        guard data.count <= execution.outputLimit else {
            throw PluginError.invalid("Plugin response is too large")
        }
        return data
    }

    private static func environment(for plugin: InstalledPlugin) -> [String: String] {
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
