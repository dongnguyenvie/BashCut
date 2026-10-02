import BashCutAutomation
import BashCutProject
import BashCutStorage
import Foundation

/// Project lifecycle shared by the UI and automation, plus the token file for agents outside the app.
extension ProjectDocument {
    /// Creates a project folder like the New Project wizard and shows it.
    func createProject(_ setup: ProjectSetup, in parent: URL, footage: URL? = nil) async throws -> URL {
        let previousURL = fileURL
        let created = try await storage.create(setup, in: parent, footage: footage)
        if let previousURL { try? await storage.discardRecovery(at: previousURL) }
        reset(created.project, url: created.url)
        diskData = created.diskData
        message = String(localized: "Project created")
        DebugLog.write("project", "created \(created.url.path) layers: \(layoutSummary())")
        return created.url
    }

    /// Automation never shows the discard dialog: unsaved changes need an explicit save or discard.
    func leaveCurrentProject(_ arguments: CommandArguments) async throws {
        guard !busy, !saving else { throw AutomationBusy() }
        guard dirty else { return }
        if arguments.bool("saveCurrent") {
            try await saveNow()
        } else if arguments.bool("discardCurrent") {
            if let fileURL { try await storage.discardRecovery(at: fileURL) }
            DebugLog.write("project", "discarded unsaved changes of \(fileURL?.path ?? "unsaved project")")
        } else {
            throw RPCFailure(-32602, "The open project has unsaved changes; pass saveCurrent or discardCurrent")
        }
    }

    func projectResult() -> JSONValue {
        .object(["project": fileURL.map { .string($0.path) } ?? .null, "rev": .integer(project.revision)])
    }

    func registerProjectCommands() {
        handleAuthored("project.open") { document, arguments, _ in
            var url = URL(fileURLWithPath: try arguments.string("path")).standardizedFileURL
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                url = url.appendingPathComponent("project.bashcut.json")
            }
            guard url.path.hasPrefix("/"), FileManager.default.fileExists(atPath: url.path) else {
                throw RPCFailure(-32602, "No project at \(url.path)")
            }
            try await document.leaveCurrentProject(arguments)
            document.busy = true
            defer { document.busy = false }
            try await document.loadProject(at: url, offerRecovery: false)
            return document.projectResult()
        }
        handleAuthored("project.create") { document, arguments, _ in
            var setup = ProjectSetup()
            setup.name = try arguments.string("name")
            setup.canvas = ProjectSetup.Canvas(rawValue: try arguments.string("canvas")) ?? .portrait
            setup.resolution = Int(try arguments.string("resolution")).flatMap(ProjectSetup.Resolution.init) ?? .fullHD
            setup.rate = ProjectSetup.Rate(rawValue: try arguments.string("fps")) ?? .ntsc
            setup.contentLanguage = try arguments.string("language")
            setup.style = ProjectSetup.Style(rawValue: try arguments.string("style")) ?? .foodReview
            let parent = URL(fileURLWithPath: try arguments.string("directory"), isDirectory: true).standardizedFileURL
            let footage = arguments.optionalString("footage").map { URL(fileURLWithPath: $0, isDirectory: true) }
            try await document.leaveCurrentProject(arguments)
            document.busy = true
            defer { document.busy = false }
            _ = try await document.createProject(setup, in: parent, footage: footage)
            return document.projectResult()
        }
        handleAuthored("project.save") { document, _, _ in
            try await document.saveNow()
            return document.projectResult()
        }
    }

    // MARK: External agents

    /// Issues a fresh external-agent token and writes it to the 0600 token file, or removes both when the
    /// Settings switch is off. Called at launch and from Settings; the token survives project switches.
    func applyExternalAgentAccess(enabled: Bool) {
        if let token = externalAgentToken { registry.revoke(token) }
        externalAgentToken = nil
        let file = AutomationPaths.tokenFile
        try? FileManager.default.removeItem(at: file)
        guard enabled else {
            DebugLog.write("access", "external agent access off; token file removed")
            return
        }
        let token = registry.issueToken(author: .agent)
        do {
            let manager = FileManager.default
            try manager.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let staging = file.deletingLastPathComponent().appendingPathComponent(".automation-token-" + UUID().uuidString)
            guard manager.createFile(atPath: staging.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
            else { throw CocoaError(.fileWriteUnknown) }
            _ = try manager.replaceItemAt(file, withItemAt: staging)
            externalAgentToken = token
            DebugLog.write("access", "external agent token written to \(file.path)")
        } catch {
            registry.revoke(token)
            DebugLog.write("access", "external agent token FAILED: \(error.localizedDescription)")
        }
    }

    func removeExternalAgentToken() {
        if let token = externalAgentToken { registry.revoke(token) }
        externalAgentToken = nil
        try? FileManager.default.removeItem(at: AutomationPaths.tokenFile)
    }
}
