import Foundation
import Logging
import MCP

/// stdio transport for `bashcut-mcp` without polling. The SDK's `StdioTransport` puts stdin and stdout in
/// non-blocking mode and sleeps 10 ms whenever no data is ready, which added about 10 ms to every request and
/// 30–40 ms to large results. Here a dedicated thread blocks on `read(2)` and hands complete lines to the server at
/// once; writes block until the client has taken the bytes. `intercept` may answer a line itself (the reply is
/// written directly and the server never sees the request).
actor BlockingStdioTransport: Transport {
    nonisolated let logger = Logger(label: "app.bashcut.mcp.stdio")
    private let messages: AsyncThrowingStream<Data, Swift.Error>
    private let continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private let intercept: (@Sendable (Data) -> Data?)?
    private var started = false
    /// Replies from `intercept` and from the server come from different threads; one line at a time.
    private static let writeLock = NSLock()

    init(intercept: (@Sendable (Data) -> Data?)? = nil) {
        (messages, continuation) = AsyncThrowingStream.makeStream()
        self.intercept = intercept
    }

    func connect() async throws {
        guard !started else { return }
        started = true
        let continuation = self.continuation
        let intercept = self.intercept
        let reader = Thread {
            var pending = Data()
            var awaitingInitialize = true
            var buffer = [UInt8](repeating: 0, count: 64 * 1024)
            while true {
                let count = buffer.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, $0.count) }
                if count < 0 {
                    if errno == EINTR { continue }
                    continuation.finish(throwing: MCPError.transportError(POSIXError(.init(rawValue: errno) ?? .EIO)))
                    return
                }
                if count == 0 { break }
                pending.append(contentsOf: buffer[..<count])
                for var line in Self.takeLines(&pending) {
                    if awaitingInitialize, let initialize = Self.compatibleInitialize(line) {
                        line = initialize
                        awaitingInitialize = false
                    }
                    if let reply = intercept?(line) {
                        try? Self.writeLine(reply)
                    } else {
                        continuation.yield(line)
                    }
                }
            }
            continuation.finish()
        }
        reader.name = "bashcut-mcp stdin"
        reader.start()
    }

    func disconnect() async {
        continuation.finish()
    }

    func send(_ data: Data) async throws {
        try Self.writeLine(data)
    }

    private static func writeLine(_ data: Data) throws {
        var message = data
        message.append(UInt8(ascii: "\n"))
        writeLock.lock()
        defer { writeLock.unlock() }
        try message.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = write(STDOUT_FILENO, base + offset, bytes.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw MCPError.transportError(POSIXError(.init(rawValue: errno) ?? .EIO))
                }
                offset += written
            }
        }
    }

    nonisolated func receive() -> AsyncThrowingStream<Data, Swift.Error> { messages }

    /// For an `initialize` request, the request without `params.capabilities.experimental`; nil for any other
    /// line. Workaround for swift-sdk 0.12.1, which decodes that field as `[String: String]` although the MCP schema
    /// allows objects: Codex 0.160 sends `{"codex/auth-change": {}}` and the handshake failed with -32603. BashCut
    /// never reads client capabilities. Remove this once the SDK decodes the field as JSON values.
    /// Lines are parsed only until `initialize` arrives, so every spelling of the key is handled at no later cost.
    static func compatibleInitialize(_ line: Data) -> Data? {
        guard var message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              message["method"] as? String == "initialize"
        else { return nil }
        guard var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              capabilities.removeValue(forKey: "experimental") != nil
        else { return line }
        params["capabilities"] = capabilities
        message["params"] = params
        return (try? JSONSerialization.data(withJSONObject: message)) ?? line
    }

    /// Removes every complete newline-terminated line from `pending` (empty lines are skipped).
    static func takeLines(_ pending: inout Data) -> [Data] {
        var lines: [Data] = []
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: UInt8(ascii: "\n")) {
            if newline > start { lines.append(Data(pending[start..<newline])) }
            start = pending.index(after: newline)
        }
        pending = Data(pending[start...])
        return lines
    }
}
