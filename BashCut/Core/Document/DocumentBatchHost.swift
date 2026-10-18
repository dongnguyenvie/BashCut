import BashCutAutomation
import BashCutDocument
import BashCutEngine
import AppKit
import BashCutProject
import Foundation
import UserNotifications

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
        BatchNotifier.prepare()
        BatchNotifier.badge(done: 0, total: nil)
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

    func startBatchExport(preset: String, name: String, options: [String: JSONValue], replacing: Bool) throws
        -> (job: String, file: URL)
    {
        try document.startBatchExport(preset: preset, fileName: name, options: options, author: author, replacing: replacing)
    }

    func itemFinished(_ run: BatchRunStatus) {
        BatchNotifier.badge(done: run.items.filter(\.state.isFinished).count, total: run.items.count)
    }

    func runFinished(_ run: BatchRunStatus) {
        document.registry.revoke(token)
        BatchNotifier.badge(done: 0, total: nil)
        if run.state != .interrupted { BatchNotifier.finished(run) }
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

/// What a long batch shows outside its window: the items done on the Dock icon while it runs, and a notification
/// when it ends (the Dock icon bounces once when notifications are off).
@MainActor
enum BatchNotifier {
    /// Notifications need a bundled app; `swift test` hosts have none.
    private static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    /// Asks for permission once, when the first batch starts.
    static func prepare() {
        guard available else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// `done/total` on the Dock icon; nil total clears it.
    static func badge(done: Int, total: Int?) {
        NSApp.dockTile.badgeLabel = total.map { "\(done)/\($0)" }
    }

    static func finished(_ run: BatchRunStatus) {
        let done = run.count(.completed), total = run.items.count, failed = run.count(.failed)
        let title = run.state == .cancelled ? String(localized: "Batch cancelled")
            : failed > 0 || run.state == .failed ? String(localized: "Batch finished with failures")
            : String(localized: "Batch finished")
        var body = String(format: String(localized: "%lld of %lld items done"), done, total)
        if failed > 0 { body += " · " + String(format: String(localized: "%lld failed"), failed) }
        if let name = run.pipeline.name { body = name + " · " + body }
        if !NSApp.isActive { NSApp.requestUserAttention(.informationalRequest) }
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "batch-" + run.id, content: content, trigger: nil)) { _ in }
    }
}
