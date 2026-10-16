import BashCutAutomation
import BashCutDocument
import BashCutEngine
import BashCutProject
import Foundation

/// The document as a batch host: commands go through the registry with a token of the batch's own, issued for the
/// author who started it and revoked when the run ends.
@MainActor
final class DocumentBatchHost: BatchHost {
    private let document: ProjectDocument
    private let author: Author
    private let token: String

    init(document: ProjectDocument, author: Author) {
        self.document = document
        self.author = author
        token = document.registry.issueToken(author: author)
    }

    var jobs: JobCenter { document.jobs }
    var openProjectFile: URL? { document.fileURL }
    var projectRevision: Int? { document.fileURL == nil ? nil : document.project.revision }
    var firstMediaID: String? { document.project.media.first?.id }
    var defaultProjectsFolder: URL { document.settings.defaultProjectsFolder }

    func invoke(_ method: String, _ params: [String: JSONValue]) async throws -> JSONValue {
        let response = await document.registry.handle(
            RPCRequest(id: .string(UUID().uuidString), method: method, params: params, token: token))
        if let error = response.error { throw error }
        return response.result ?? .null
    }

    func isPluginAction(_ id: String) -> Bool { document.plugins.action(id) != nil }

    func startBatchExport(preset: String, name: String, options: [String: JSONValue]) throws -> (job: String, file: URL) {
        try document.startBatchExport(preset: preset, fileName: name, options: options, author: author)
    }

    func runFinished(_ run: BatchRunStatus) {
        document.registry.revoke(token)
        let done = run.count(.completed), total = run.items.count
        switch run.state {
        case .cancelled: document.message = String(localized: "Batch cancelled")
        case .failed: document.message = String(localized: "Batch stopped: \(done) of \(total) items done")
        default: document.message = String(localized: "Batch finished: \(done) of \(total) items done")
        }
        DebugLog.write("batch", "\(run.id) \(run.state.rawValue): \(run.count(.completed))/\(run.items.count) done, "
                       + "\(run.count(.failed)) failed")
    }
}
