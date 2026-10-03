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
        fileSync.accept(created.diskData)
        message = String(localized: "Project created")
        DebugLog.write("project", "created \(created.url.path) layers: \(layoutSummary())")
        emitPluginEvent(.projectCreated, ["path": .string(created.url.path), "name": .string(created.project.name)])
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

    /// The project's canvas from its size (square when equal sides).
    var canvas: ProjectSetup.Canvas {
        project.width == project.height ? .square : (project.width > project.height ? .landscape : .portrait)
    }

    /// Changes the canvas (toolbar format menu, `project format`) as one undoable edit, keeping the short side
    /// unless `shortSide` is given.
    @discardableResult
    func setCanvas(
        _ canvas: ProjectSetup.Canvas, shortSide: Int? = nil, author: Author = .user, baseRevision: Int? = nil
    ) throws -> Int {
        let side = shortSide ?? min(project.width, project.height)
        let size = canvas.dimensions(shortSide: side)
        guard size.width != project.width || size.height != project.height else { return project.revision }
        let name = switch canvas {
        case .portrait: "Portrait 9:16"
        case .landscape: "Landscape 16:9"
        case .square: "Square 1:1"
        }
        return try commit(
            .setFormat(width: size.width, height: size.height), label: "Canvas: \(name)", author: author,
            baseRevision: baseRevision)
    }

    func projectResult() -> JSONValue {
        .object(["project": fileURL.map { .string($0.path) } ?? .null, "rev": .integer(project.revision)])
    }

    func registerProjectCommands() {
        handleAuthored("project.format") { document, arguments, author in
            guard let canvas = ProjectSetup.Canvas(rawValue: try arguments.string("canvas")) else {
                throw RPCFailure(-32602, "Unknown canvas")
            }
            let revision = try document.setCanvas(
                canvas, shortSide: arguments.optionalString("resolution").flatMap(Int.init), author: author,
                baseRevision: try arguments.int("baseRev"))
            return .object([
                "rev": .integer(revision), "width": .integer(document.project.width),
                "height": .integer(document.project.height),
            ])
        }
        handleAuthored("project.open") { document, arguments, _ in
            let path = try arguments.string("path")
            guard path.hasPrefix("/"), let url = ProjectStorage.projectFile(for: URL(fileURLWithPath: path)) else {
                throw RPCFailure(-32602, "No project at \(path)")
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
    func applyExternalAgentAccess(enabled: Bool) { automation.setExternalAgentAccess(enabled) }

    func removeExternalAgentToken() { automation.removeExternalAgentToken() }
}
