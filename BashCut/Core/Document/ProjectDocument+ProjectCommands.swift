import BashCutAutomation
import BashCutProject
import BashCutStorage
import Foundation

/// Project lifecycle shared by the UI and automation, plus the token file for agents outside the app.
extension ProjectDocument {
    /// Creates a project folder like the New Project wizard and shows it.
    func createProject(_ setup: ProjectSetup, in parent: URL, footage: URL? = nil) async throws -> URL {
        let previousURL = fileURL
        // The default folder is made on first use; any other parent must already exist, so a mistyped path fails.
        if parent.standardizedFileURL == settings.defaultProjectsFolder.standardizedFileURL {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }
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

    /// Whether clips fill the frame (cropping) or fit inside it by default (format menu, `project format --clips`).
    @discardableResult
    func setClipFill(_ fill: Bool, author: Author = .user, baseRevision: Int? = nil) throws -> Int {
        guard project.clipsFill != fill else { return project.revision }
        return try commit(
            .setProjectProperties(patch: ["clipFill": .bool(fill)]),
            label: fill ? "Clips fill the frame" : "Clips fit inside the frame", author: author,
            baseRevision: baseRevision)
    }

    func projectResult() -> JSONValue {
        .object(["project": fileURL.map { .string($0.path) } ?? .null, "rev": .integer(project.revision)])
    }

    func registerProjectCommands() {
        handleAuthored("project.format") { document, arguments, author in
            let canvas = arguments.optionalString("canvas")
            let clips = arguments.optionalString("clips")
            guard canvas != nil || clips != nil else { throw RPCFailure(-32602, "Give canvas, clips or both") }
            var baseRevision: Int? = try arguments.int("baseRev")
            if let canvas {
                guard let value = ProjectSetup.Canvas(rawValue: canvas) else { throw RPCFailure(-32602, "Unknown canvas") }
                try document.setCanvas(
                    value, shortSide: arguments.optionalString("resolution").flatMap(Int.init), author: author,
                    baseRevision: baseRevision)
                baseRevision = nil
            }
            if let clips { try document.setClipFill(clips == "fill", author: author, baseRevision: baseRevision) }
            return .object([
                "rev": .integer(document.project.revision), "width": .integer(document.project.width),
                "height": .integer(document.project.height), "clips": .string(document.project.clipsFill ? "fill" : "fit"),
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
            let parent = arguments.optionalString("directory")
                .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
                ?? document.settings.defaultProjectsFolder
            let footage = arguments.optionalString("footage").map { URL(fileURLWithPath: $0, isDirectory: true) }
            try await document.leaveCurrentProject(arguments)
            document.busy = true
            defer { document.busy = false }
            _ = try await document.createProject(setup, in: parent, footage: footage)
            return document.projectResult()
        }
        handleAuthored("project.folder") { document, arguments, _ in
            let path = arguments.optionalString("path")
            if arguments.bool("reset") {
                guard path == nil else { throw RPCFailure(-32602, "Give a path or --reset, not both") }
                document.settings.projectsFolder = nil
            } else if let path {
                let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
                var isDirectory: ObjCBool = false
                guard url.path.hasPrefix("/"), FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                    isDirectory.boolValue
                else { throw RPCFailure(-32602, "No folder at \(path)") }
                document.settings.rememberProjectsFolder(url)
            }
            return .object([
                "folder": .string(document.settings.defaultProjectsFolder.path),
                "standard": .bool(document.settings.projectsFolder == nil),
            ])
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
