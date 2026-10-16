import Darwin
import Foundation

/// One line of install-recipe output: plain text, or a `::progress <0…1> [message]` report.
public enum PluginRecipeOutput: Sendable, Equatable {
    case line(String)
    case progress(Double, String?)

    public init(parsing text: String) {
        let parts = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        if parts.first == "::progress", parts.count >= 2, let value = Double(parts[1]), value.isFinite {
            self = .progress(min(1, max(0, value)), parts.count > 2 ? String(parts[2]) : nil)
        } else {
            self = .line(text)
        }
    }
}

/// Runs a plugin command: a dependency install recipe the user approved, or a plugin's export step (API 12): the plugin's filtered
/// environment (no app secrets; an export step adds its own short-lived automation token), its own process group,
/// stdout and stderr streamed line by line, and cancellation or `timeout` that stops the whole group (pip, curl and
/// other helpers included). A failure starts with `label` and ends with the last output.
public enum PluginCommandRunner {
    public static func run(
        _ command: PluginCommand, plugin: InstalledPlugin, directory: URL,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        extraEnvironment: [String: String] = [:], label: String, timeout: TimeInterval? = nil,
        output: @escaping @Sendable (PluginRecipeOutput) -> Void
    ) async throws {
        let (executable, arguments) = try resolve(command, directory: directory)
        var environment = PluginProcessRunner.environment(for: plugin, inheriting: inheritedEnvironment)
        environment["BASHCUT_PLUGIN_DIR"] = directory.path
        environment.merge(extraEnvironment) { _, extra in extra }
        let pipe = Pipe()
        let pid = try spawn(
            executable: executable, arguments: arguments, directory: directory, environment: environment,
            output: pipe.fileHandleForWriting.fileDescriptor)
        try? pipe.fileHandleForWriting.close()
        let tail = Tail()
        let reader = Thread {
            var buffer = Data()
            let handle = pipe.fileHandleForReading
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = String(bytes: buffer[buffer.startIndex..<newline], encoding: .utf8) ?? ""
                    buffer.removeSubrange(buffer.startIndex...newline)
                    tail.append(line)
                    output(PluginRecipeOutput(parsing: line))
                }
            }
            if !buffer.isEmpty {
                let line = String(bytes: buffer, encoding: .utf8) ?? ""
                tail.append(line)
                output(PluginRecipeOutput(parsing: line))
            }
            try? handle.close()
        }
        reader.start()

        let status = try await waitForExit(pid, label: label, timeout: timeout)
        // Helpers the recipe left running belong to it.
        _ = kill(-pid, SIGKILL)
        let exited = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        guard exited == 0 else {
            let detail = tail.text.trimmingCharacters(in: .whitespacesAndNewlines)
            throw PluginError.invalid(
                detail.isEmpty ? "\(label) failed with status \(exited)" : "\(label) failed: \(detail)")
        }
    }

    /// Waits for the recipe's leader to exit and returns its raw status; on cancellation or after `timeout` it stops
    /// the whole group first and throws.
    private static func waitForExit(_ pid: pid_t, label: String, timeout: TimeInterval?) async throws -> Int32 {
        var status: Int32 = 0
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        while true {
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid { break }
            if result < 0 { break }
            let timedOut = deadline.map { Date() >= $0 } ?? false
            if Task.isCancelled || timedOut {
                _ = kill(-pid, SIGTERM)
                for _ in 0..<40 where waitpid(pid, &status, WNOHANG) == 0 {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                _ = kill(-pid, SIGKILL)
                _ = waitpid(pid, &status, 0)
                if timedOut, !Task.isCancelled {
                    throw PluginError.invalid("\(label) timed out after \(Int(timeout ?? 0)) s")
                }
                throw CancellationError()
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return status
    }

    static func resolve(_ command: PluginCommand, directory: URL) throws -> (URL, [String]) {
        guard command.executable.contains("/") else {
            return (URL(fileURLWithPath: "/usr/bin/env"), [command.executable] + command.arguments)
        }
        let executable = directory.appendingPathComponent(command.executable).standardizedFileURL
        guard executable.path.hasPrefix(directory.standardizedFileURL.path + "/"),
            FileManager.default.isExecutableFile(atPath: executable.path)
        else { throw PluginError.invalid("\(command.executable) is missing from the plugin or not executable") }
        return (executable, command.arguments)
    }

    private static func spawn(
        executable: URL, arguments: [String], directory: URL, environment: [String: String], output: Int32
    ) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, output, 1)
        posix_spawn_file_actions_adddup2(&actions, output, 2)
        posix_spawn_file_actions_addchdir_np(&actions, directory.path)
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
        let argv = [executable.path] + arguments
        let envp = environment.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let result = withCStrings(argv) { argv in
            withCStrings(envp) { envp in posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp) }
        }
        guard result == 0 else {
            throw PluginError.invalid("Cannot start the install recipe: \(String(cString: strerror(result)))")
        }
        return pid
    }

    /// The last 4,000 characters of output, for the error message.
    private final class Tail: @unchecked Sendable {
        private let lock = NSLock()
        private var value = ""
        func append(_ line: String) {
            lock.lock()
            value += line + "\n"
            if value.count > 4_000 { value = String(value.suffix(4_000)) }
            lock.unlock()
        }
        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
