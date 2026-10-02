import Darwin
import Foundation

public enum AutomationPaths {
    public static var socket: String {
        ProcessInfo.processInfo.environment["BASHCUT_SOCKET"]
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BashCut/automation.sock").path
    }
}

private enum SocketIO {
    static let maximumBytes = 8 * 1024 * 1024
    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw RPCFailure(-32000, "Socket path is too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        return address
    }
    static func configure(_ descriptor: Int32) {
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC)
    }
    static func readLine(_ descriptor: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count <= maximumBytes {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw RPCFailure(-32000, "Socket closed or timed out") }
            if let newline = buffer[..<count].firstIndex(of: 10) {
                guard data.count + newline <= maximumBytes else {
                    throw RPCFailure(-32600, "Request exceeds the size limit")
                }
                data.append(contentsOf: buffer[..<newline])
                return data
            }
            data.append(contentsOf: buffer[..<count])
        }
        throw RPCFailure(-32600, "Request exceeds the size limit")
    }
    static func writeLine(_ data: Data, _ descriptor: Int32) throws {
        guard data.count <= maximumBytes else {
            throw RPCFailure(-32000, "Response exceeds the size limit")
        }
        var bytes = data
        bytes.append(10)
        try bytes.withUnsafeBytes { raw in
            guard let start = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = Darwin.write(descriptor, start.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw RPCFailure(-32000, "Cannot write socket response") }
                offset += count
            }
        }
    }
}

public enum UnixRPCClient {
    public static func call(_ request: RPCRequest, path: String = AutomationPaths.socket) throws
        -> RPCResponse
    {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw RPCFailure(-32000, "Cannot create socket") }
        defer { Darwin.close(descriptor) }
        SocketIO.configure(descriptor)
        var address = try SocketIO.address(path)
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw RPCFailure(-32000, "Cannot reach BashCut; open the app first")
        }
        try SocketIO.writeLine(JSONEncoder().encode(request), descriptor)
        let response = try JSONDecoder().decode(RPCResponse.self, from: SocketIO.readLine(descriptor))
        if let error = response.error { throw error }
        return response
    }
}

/// Accepts connections on a dedicated thread and serves each client on a concurrent queue, so blocking
/// socket I/O never occupies the Swift cooperative pool and one slow client cannot stall the others.
private final class AcceptLoop: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let finished = DispatchSemaphore(value: 0)
    private let slots = DispatchSemaphore(value: 16)
    private let clients = DispatchQueue(label: "app.bashcut.automation.clients", attributes: .concurrent)

    private var isCancelled: Bool { lock.withLock { cancelled } }

    func start(descriptor: Int32, handler: @escaping @Sendable (RPCRequest) async -> RPCResponse) {
        let thread = Thread { [self] in
            while !isCancelled {
                var pollFD = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                guard Darwin.poll(&pollFD, 1, 100) > 0 else { continue }
                let client = Darwin.accept(descriptor, nil, nil)
                guard client >= 0 else { continue }
                SocketIO.configure(client)
                guard slots.wait(timeout: .now()) == .success else {
                    Self.reply(RPCResponse(id: .null, error: RPCFailure(-32003, "Too many automation clients")), client)
                    Darwin.close(client)
                    continue
                }
                clients.async { [self] in
                    defer {
                        Darwin.close(client)
                        slots.signal()
                    }
                    Self.serve(client, handler: handler)
                }
            }
            finished.signal()
        }
        thread.name = "BashCut automation accept"
        thread.start()
    }

    /// Stops accepting and waits for the accept thread to exit; in-flight clients finish on their own.
    func stop() async {
        lock.withLock { cancelled = true }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { [finished] in
                finished.wait()
                continuation.resume()
            }
        }
    }

    // Bounded, one request per connection; callers reconnect for each command.
    private static func serve(_ client: Int32, handler: @escaping @Sendable (RPCRequest) async -> RPCResponse) {
        let request: RPCRequest
        do {
            request = try JSONDecoder().decode(RPCRequest.self, from: SocketIO.readLine(client))
        } catch {
            reply(RPCResponse(id: .null, error: RPCFailure(-32600, "Invalid JSON-RPC request")), client)
            return
        }
        let box = ResponseBox()
        let done = DispatchSemaphore(value: 0)
        Task {
            box.response = await handler(request)
            done.signal()
        }
        done.wait()
        if let response = box.response { reply(response, client) }
    }

    private static func reply(_ response: RPCResponse, _ client: Int32) {
        guard let encoded = try? JSONEncoder().encode(response) else { return }
        try? SocketIO.writeLine(encoded, client)
    }
}

/// Written once by the handler task before `done` is signalled, then read by the client thread.
private final class ResponseBox: @unchecked Sendable {
    var response: RPCResponse?
}

public actor UnixRPCServer {
    private var loop: AcceptLoop?
    private var descriptor: Int32 = -1
    private var path: String?
    public init() {}

    public func start(path: String, handler: @escaping @Sendable (RPCRequest) async -> RPCResponse)
        throws
    {
        guard loop == nil else { return }
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try clearStaleSocket(path)
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw RPCFailure(-32000, "Cannot create automation socket") }
        SocketIO.configure(descriptor)
        var address = try SocketIO.address(path)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            Darwin.close(descriptor)
            throw RPCFailure(-32000, "Cannot bind automation socket")
        }
        guard chmod(path, 0o600) == 0, Darwin.listen(descriptor, 16) == 0 else {
            Darwin.close(descriptor)
            unlink(path)
            throw RPCFailure(-32000, "Cannot secure automation socket")
        }
        self.descriptor = descriptor
        self.path = path
        let loop = AcceptLoop()
        loop.start(descriptor: descriptor, handler: handler)
        self.loop = loop
    }
    private func clearStaleSocket(_ path: String) throws {
        // A stale socket is only removed after an unsuccessful probe; never evict a live instance.
        if FileManager.default.fileExists(atPath: path) {
            do {
                _ = try UnixRPCClient.call(RPCRequest(method: "context.get"), path: path)
                throw RPCFailure(-32000, "Another BashCut instance owns the automation socket")
            } catch let error as RPCFailure
                where error.message == "Cannot reach BashCut; open the app first"
            {
                guard
                    (try FileManager.default.attributesOfItem(atPath: path)[.type]) as? FileAttributeType
                        == .typeSocket
                else {
                    throw RPCFailure(-32000, "Automation path is not a socket")
                }
                try FileManager.default.removeItem(atPath: path)
            }
        }
    }

    public func stop() async {
        if descriptor >= 0 { Darwin.shutdown(descriptor, SHUT_RDWR) }
        await loop?.stop()
        if descriptor >= 0 { Darwin.close(descriptor) }
        if let path { unlink(path) }
        descriptor = -1
        loop = nil
        path = nil
    }
}
