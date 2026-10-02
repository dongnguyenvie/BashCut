@preconcurrency import Dispatch
import Darwin
import Foundation

public final class ProjectFileMonitor: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject

    public init(fileURL: URL, onChange: @escaping @Sendable () -> Void) throws {
        let directory = fileURL.deletingLastPathComponent()
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
            queue: DispatchQueue(label: "app.bashcut.project-file-monitor", qos: .utility))
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    public func cancel() { source.cancel() }
    deinit { source.cancel() }
}
