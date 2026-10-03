import BashCutProject
import Darwin
import Foundation

/// The long-lived transport for plugins whose manifest says `"transport": "session"`.
///
/// The app starts `entrypoint session` once per plugin and talks newline-delimited JSON over stdin/stdout:
///
/// - handshake: the app sends `{"type":"hello","apiVersion":2}`; the plugin answers `{"type":"hello",…}`.
/// - requests: `{"type":"request","id","apiVersion","method","provider","params"}`; the plugin may send any
///   number of `{"type":"progress","id","progress"?,"message"?}` lines, then `{"id","result"}` or
///   `{"id","error":{"code","message"}}`. Requests may overlap; replies are matched by `id`.
/// - a request times out after `requestTimeout` seconds without a progress line (the provider's
///   `timeoutSeconds` replaces that window), and after `maximumRequestDuration` in any case.
/// - `{"type":"cancel","id"}` when the caller gives up; `{"type":"shutdown"}` before the app stops an idle
///   process, followed by SIGTERM and SIGKILL to its process group.
///
/// A crashed process fails its pending requests and is restarted on the next call; a plugin that crashes
/// repeatedly is refused for a minute.
public actor PluginSessionTransport: PluginTransport {
    public static let shared = PluginSessionTransport()

    /// The longest a request may go without a progress line.
    public let requestTimeout: TimeInterval
    /// The longest a request may run, however often it reports progress.
    public let maximumRequestDuration: TimeInterval
    public let idleTimeout: TimeInterval
    public let handshakeTimeout: TimeInterval
    public let maximumLineBytes: Int
    private let oneShot: PluginProcessRunner
    private var sessions: [String: PluginSession] = [:]
    private var crashes: [String: [Date]] = [:]

    public init(
        requestTimeout: TimeInterval = 120, maximumRequestDuration: TimeInterval = 4 * 3600,
        idleTimeout: TimeInterval = 90, handshakeTimeout: TimeInterval = 10, maximumLineBytes: Int = 8 * 1024 * 1024
    ) {
        self.requestTimeout = requestTimeout
        self.maximumRequestDuration = maximumRequestDuration
        self.idleTimeout = idleTimeout
        self.handshakeTimeout = handshakeTimeout
        self.maximumLineBytes = maximumLineBytes
        oneShot = PluginProcessRunner(timeout: 15, maximumOutputBytes: 256 * 1024)
    }

    public func call(
        plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue
    ) async throws -> JSONValue {
        try await call(plugin: plugin, method: method, provider: provider, params: params, progress: nil)
    }

    public func call(
        plugin: InstalledPlugin, method: String, provider: String?, params: JSONValue,
        progress: PluginProgressHandler?
    ) async throws -> JSONValue {
        guard method.range(of: "^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)*$", options: .regularExpression) != nil
        else { throw PluginError.invalid("Invalid plugin method") }
        let session = try await session(for: plugin)
        let silence = plugin.manifest.providers?.first { $0.id == provider }?.timeoutSeconds
            .map { TimeInterval($0) } ?? requestTimeout
        return try await session.request(
            method: method, provider: provider, params: params,
            limits: (silence: silence, total: max(silence, maximumRequestDuration)), progress: progress)
    }

    public nonisolated func health(plugin: InstalledPlugin) async -> PluginHealth {
        await oneShot.health(plugin: plugin)
    }

    /// Plugin IDs with a running process.
    public func running() async -> [String] {
        var ids: [String] = []
        for (id, session) in sessions where await session.isAlive { ids.append(id) }
        return ids.sorted()
    }

    /// Stops one plugin's process (plugin turned off, changed or the project closed).
    public func stop(pluginID: String) async {
        guard let session = sessions.removeValue(forKey: pluginID) else { return }
        await session.shutdown()
    }

    public func stopAll() async {
        let all = sessions.values
        sessions.removeAll()
        for session in all { await session.shutdown() }
    }

    private func session(for plugin: InstalledPlugin) async throws -> PluginSession {
        if let existing = sessions[plugin.id] {
            if await existing.isAlive, existing.directory == plugin.directory.standardizedFileURL {
                return existing
            }
            sessions[plugin.id] = nil
            await existing.shutdown()
        }
        let recent = (crashes[plugin.id] ?? []).filter { Date().timeIntervalSince($0) < 60 }
        crashes[plugin.id] = recent
        guard recent.count < 3 else {
            throw PluginError.invalid("Plugin \(plugin.id) keeps crashing; try again in a minute")
        }
        let session = PluginSession(
            plugin: plugin, maximumLineBytes: maximumLineBytes, idleTimeout: idleTimeout
        ) { [weak self] id, crashed in
            await self?.ended(id, crashed: crashed)
        }
        do {
            try await session.start(handshakeTimeout: handshakeTimeout)
        } catch {
            crashes[plugin.id, default: []].append(Date())
            await session.shutdown()
            throw error
        }
        sessions[plugin.id] = session
        return session
    }

    private func ended(_ id: ObjectIdentifier, crashed: Bool) {
        guard let entry = sessions.first(where: { ObjectIdentifier($0.value) == id }) else { return }
        sessions[entry.key] = nil
        if crashed { crashes[entry.key, default: []].append(Date()) }
    }
}

/// One running plugin process and its in-flight requests.
actor PluginSession {
    private struct Pending {
        let continuation: CheckedContinuation<JSONValue, any Error>
        let progress: PluginProgressHandler?
        var lastActivity = Date()
    }

    nonisolated let directory: URL
    private let plugin: InstalledPlugin
    private let maximumLineBytes: Int
    private let idleTimeout: TimeInterval
    private let onEnd: @Sendable (ObjectIdentifier, Bool) async -> Void
    private var pid: pid_t = 0
    private var input: FileHandle?
    private var errorLog: URL?
    private var pending: [String: Pending] = [:]
    private var hello: CheckedContinuation<Void, any Error>?
    private var helloReceived = false
    private var alive = false
    private var stopping = false
    private var lastUsed = Date()
    private var idleTask: Task<Void, Never>?

    init(
        plugin: InstalledPlugin, maximumLineBytes: Int, idleTimeout: TimeInterval,
        onEnd: @escaping @Sendable (ObjectIdentifier, Bool) async -> Void
    ) {
        self.plugin = plugin
        directory = plugin.directory.standardizedFileURL
        self.maximumLineBytes = maximumLineBytes
        self.idleTimeout = idleTimeout
        self.onEnd = onEnd
    }

    var isAlive: Bool { alive && !stopping }

    func start(handshakeTimeout: TimeInterval) async throws {
        let executable = try plugin.entrypointURL()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let logDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BashCutPluginSessions")
        try FileManager.default.createDirectory(
            at: logDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let log = logDirectory.appendingPathComponent("\(plugin.id)-\(UUID().uuidString).stderr.log")
        errorLog = log
        pid = try Self.spawn(
            executable: executable, directory: plugin.directory,
            environment: PluginProcessRunner.environment(for: plugin),
            pipes: (stdinPipe.fileHandleForReading.fileDescriptor, stdoutPipe.fileHandleForWriting.fileDescriptor),
            stderr: log.path)
        try? stdinPipe.fileHandleForReading.close()
        try? stdoutPipe.fileHandleForWriting.close()
        let writer = stdinPipe.fileHandleForWriting
        // Writing to a process that died must fail with EPIPE instead of killing the app with SIGPIPE.
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        input = writer
        alive = true
        startReading(stdoutPipe.fileHandleForReading)

        try send(.object([
            "type": .string("hello"), "apiVersion": .integer(PluginAPI.current), "host": .string("BashCut"),
            "pluginId": .string(plugin.id),
        ]))
        let timer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(handshakeTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.resolveHello(PluginError.invalid("Plugin session did not answer the handshake"))
        }
        defer { timer.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            if helloReceived {
                continuation.resume()
            } else if !alive {
                continuation.resume(throwing: PluginError.invalid(exitDetail()))
            } else {
                hello = continuation
            }
        }
    }

    private func resolveHello(_ error: (any Error)?) {
        guard let hello else { return }
        self.hello = nil
        if let error { hello.resume(throwing: error) } else { hello.resume() }
    }

    func request(
        method: String, provider: String?, params: JSONValue, limits: (silence: TimeInterval, total: TimeInterval),
        progress: PluginProgressHandler?
    ) async throws -> JSONValue {
        let id = UUID().uuidString
        var message: [String: JSONValue] = [
            "type": .string("request"), "id": .string(id), "apiVersion": .integer(PluginAPI.current),
            "method": .string(method), "params": params,
        ]
        if let provider { message["provider"] = .string(provider) }
        let data = try JSONEncoder().encode(JSONValue.object(message))
        guard data.count <= 1024 * 1024 else { throw PluginError.invalid("Plugin request is too large") }
        lastUsed = Date()
        idleTask?.cancel()
        let deadline = Date().addingTimeInterval(limits.total)
        let check = UInt64(min(1, limits.silence / 4) * 1_000_000_000)
        let watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: check)
                guard !Task.isCancelled, let self,
                    await self.keepWaiting(id, silence: limits.silence, deadline: deadline)
                else { return }
            }
        }
        defer {
            watchdog.cancel()
            scheduleIdleShutdown()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard alive, !stopping else {
                    continuation.resume(throwing: PluginError.invalid(exitDetail()))
                    return
                }
                pending[id] = Pending(continuation: continuation, progress: progress)
                do {
                    try write(data)
                } catch {
                    pending[id] = nil
                    continuation.resume(throwing: PluginError.invalid("Cannot write to the plugin session"))
                }
            }
        } onCancel: {
            Task { await self.fail(id, PluginError.invalid("Plugin request was cancelled"), notify: true) }
        }
    }

    /// Asks the process to exit, then terminates its whole process group.
    func shutdown() async {
        guard alive, !stopping else { return }
        stopping = true
        idleTask?.cancel()
        try? send(.object(["type": .string("shutdown")]))
        for _ in 0..<50 where alive {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        _ = Darwin.kill(-pid, SIGTERM)
        for _ in 0..<25 where alive {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        _ = Darwin.kill(-pid, SIGKILL)
        try? input?.close()
        input = nil
        failAll(PluginError.invalid("Plugin session stopped"))
    }

    // MARK: Reading

    private nonisolated func startReading(_ handle: FileHandle) {
        let limit = maximumLineBytes
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        let thread = Thread {
            var buffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    continuation.yield(buffer[buffer.startIndex..<newline])
                    buffer.removeSubrange(buffer.startIndex...newline)
                }
                if buffer.count > limit {
                    continuation.yield(Data("{\"type\":\"overflow\"}".utf8))
                    break
                }
            }
            try? handle.close()
            continuation.finish()
        }
        thread.name = "BashCut plugin session reader"
        thread.start()
        Task { [weak self] in
            for await line in stream { await self?.receive(line) }
            await self?.exited()
        }
    }

    private func receive(_ line: Data) {
        guard !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) else { return }
        guard let message = try? JSONDecoder().decode(JSONValue.self, from: line), case .object(let fields) = message
        else {
            failAll(PluginError.invalid("Plugin session sent invalid JSON"))
            return
        }
        switch fields["type"]?.string {
        case "hello":
            helloReceived = true
            resolveHello(nil)
        case "progress":
            guard let id = fields["id"]?.string, let entry = pending[id] else { return }
            pending[id]?.lastActivity = Date()
            let fraction = fields["progress"]?.double.map { min(1, max(0, $0)) }
            entry.progress?(fraction, fields["message"]?.string.map { String($0.prefix(500)) })
        case "overflow":
            failAll(PluginError.invalid("Plugin response is too large"))
            _ = Darwin.kill(-pid, SIGKILL)
        default:
            guard let id = fields["id"]?.string, let entry = pending.removeValue(forKey: id) else { return }
            if let failure = fields["error"]?.object, !failure.isEmpty {
                let code = failure["code"]?.string ?? "error"
                let text = failure["message"]?.string ?? "Plugin failed"
                entry.continuation.resume(throwing: PluginError.invalid("Plugin error \(code): \(text)"))
            } else if let result = fields["result"] {
                entry.continuation.resume(returning: result)
            } else {
                entry.continuation.resume(
                    throwing: PluginError.invalid("Plugin returned neither a result nor an error"))
            }
        }
    }

    private func exited() async {
        let crashed = !stopping
        alive = false
        var status: Int32 = 0
        _ = waitpid(pid, &status, WNOHANG)
        _ = Darwin.kill(-pid, SIGKILL)
        let detail = exitDetail()
        resolveHello(PluginError.invalid(detail))
        failAll(PluginError.invalid(detail))
        idleTask?.cancel()
        await onEnd(ObjectIdentifier(self), crashed)
    }

    // MARK: Helpers

    /// False once the request has finished or timed out (then it is failed and the plugin is told to cancel).
    private func keepWaiting(_ id: String, silence: TimeInterval, deadline: Date) -> Bool {
        guard let entry = pending[id] else { return false }
        let now = Date()
        if now >= deadline {
            fail(id, PluginError.invalid("Plugin request ran past its time limit"), notify: true)
            return false
        }
        if now.timeIntervalSince(entry.lastActivity) >= silence {
            let detail = "Plugin request timed out (no progress for \(Int(silence.rounded(.up))) s)"
            fail(id, PluginError.invalid(detail), notify: true)
            return false
        }
        return true
    }

    private func fail(_ id: String, _ error: PluginError, notify: Bool) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        if notify { try? send(.object(["type": .string("cancel"), "id": .string(id)])) }
        entry.continuation.resume(throwing: error)
    }

    private func failAll(_ error: PluginError) {
        let all = pending.values
        pending.removeAll()
        for entry in all { entry.continuation.resume(throwing: error) }
    }

    private func send(_ message: JSONValue) throws { try write(JSONEncoder().encode(message)) }

    private func write(_ data: Data) throws {
        guard let input else { throw PluginError.invalid("Plugin session is closed") }
        try input.write(contentsOf: data + Data([0x0A]))
    }

    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        let delay = idleTimeout
        idleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await self.shutdownIfIdle()
        }
    }

    private func shutdownIfIdle() async {
        guard pending.isEmpty, Date().timeIntervalSince(lastUsed) >= idleTimeout * 0.9 else { return }
        await shutdown()
        await onEnd(ObjectIdentifier(self), false)
    }

    private func exitDetail() -> String {
        let data = errorLog.flatMap { try? Data(contentsOf: $0) } ?? Data()
        let tail = (String(bytes: data.suffix(4_000), encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? "Plugin session ended" : "Plugin session ended: \(tail)"
    }

    private static func spawn(
        executable: URL, directory: URL, environment: [String: String], pipes: (input: Int32, output: Int32),
        stderr: String
    ) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, pipes.input, 0)
        posix_spawn_file_actions_adddup2(&actions, pipes.output, 1)
        posix_spawn_file_actions_addopen(&actions, 2, stderr, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
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
        let arguments = [executable.path, "session"]
        let variables = environment.map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let result = withCStrings(arguments) { argv in
            withCStrings(variables) { envp in
                posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
            }
        }
        guard result == 0 else {
            throw PluginError.invalid("Cannot start plugin session: \(String(cString: strerror(result)))")
        }
        return pid
    }
}
