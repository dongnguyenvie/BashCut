import BashCutAutomation
import BashCutEngine
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
            throw RPCFailure(
                -32602, "The open project \(fileURL?.deletingLastPathComponent().lastPathComponent ?? "") has unsaved "
                    + "changes; pass saveCurrent or discardCurrent (CLI --save-current or --discard-current)")
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
        return try commit(
            .setFormat(width: size.width, height: size.height), label: "Canvas: \(Self.canvasName(canvas))",
            author: author, baseRevision: baseRevision)
    }

    static func canvasName(_ canvas: ProjectSetup.Canvas) -> String {
        switch canvas {
        case .portrait: "Portrait 9:16"
        case .landscape: "Landscape 16:9"
        case .square: "Square 1:1"
        }
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

    /// The export presets the project is made for (`output.presets`, #441): format menu › Platform and
    /// `project format --outputs`. Unknown names are refused; an empty list clears them.
    @discardableResult
    func setOutputPresets(_ presets: [String], author: Author = .user, baseRevision: Int? = nil) throws -> Int {
        if let unknown = presets.first(where: { ExportPreset(argument: $0) == nil }) {
            throw RPCFailure(-32602, "Unknown export preset \(unknown); use \(OutputPresetName.all.joined(separator: ", "))")
        }
        let names = presets.compactMap { ExportPreset(argument: $0)?.argument }
        guard names != project.outputPresets else { return project.revision }
        var output = project["output"]?.object ?? [:]
        output["presets"] = .array(names.map(JSONValue.string))
        return try commit(
            .setProjectProperties(patch: ["output": .object(output)]), label: "Change output platform", author: author,
            baseRevision: baseRevision)
    }

    /// The project's content language (`none` clears it), one undoable edit; a tag that is not BCP 47-shaped is refused.
    func setContentLanguage(_ tag: String, author: Author, baseRevision: Int?) throws {
        let value = tag.trimmingCharacters(in: .whitespaces)
        let cleared = value.isEmpty || value == "none"
        guard cleared || Project.isLanguageTag(value) else {
            throw RPCFailure(-32602, "language must be a BCP 47 tag such as vi, en or en-US, or none")
        }
        guard (cleared ? nil : value) != project["contentLanguage"]?.string else { return }
        _ = try commit(
            .setProjectProperties(patch: ["contentLanguage": cleared ? .null : .string(value)]),
            label: "Change content language", author: author, baseRevision: baseRevision)
    }

    func projectResult() -> JSONValue {
        .object(["project": fileURL.map { .string($0.path) } ?? .null, "rev": .integer(project.revision)])
    }

    /// `project format`: canvas, clip fill and output presets, each its own undoable edit.
    func formatCommand(_ arguments: CommandArguments, author: Author) throws -> JSONValue {
        let canvas = arguments.optionalString("canvas")
        let clips = arguments.optionalString("clips")
        let outputs = arguments.optionalString("outputs")
        let language = arguments.optionalString("language")
        guard canvas != nil || clips != nil || outputs != nil || language != nil else {
            throw RPCFailure(-32602, "Give canvas, clips, outputs, language or several")
        }
        var baseRevision: Int? = try arguments.int("baseRev")
        if let canvas {
            guard let value = ProjectSetup.Canvas(rawValue: canvas) else { throw RPCFailure(-32602, "Unknown canvas") }
            try setCanvas(
                value, shortSide: arguments.optionalString("resolution").flatMap(Int.init), author: author,
                baseRevision: baseRevision)
            baseRevision = nil
        }
        if let clips {
            try setClipFill(clips == "fill", author: author, baseRevision: baseRevision)
            baseRevision = nil
        }
        if let outputs {
            let names = outputs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            try setOutputPresets(names, author: author, baseRevision: baseRevision)
            baseRevision = nil
        }
        if let language {
            try setContentLanguage(language, author: author, baseRevision: baseRevision)
        }
        return .object([
            "contentLanguage": project["contentLanguage"] ?? .null,
            "outputs": .array(project.outputPresets.map(JSONValue.string)),
            "rev": .integer(project.revision), "width": .integer(project.width),
            "height": .integer(project.height), "clips": .string(project.clipsFill ? "fill" : "fit"),
        ])
    }

    func registerProjectCommands() {
        handleAuthored("project.format") { document, arguments, author in
            try document.formatCommand(arguments, author: author)
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
        handleAuthored("project.close") { document, arguments, _ in
            guard document.fileURL != nil else { throw RPCFailure(-32602, "No project is open") }
            try await document.leaveCurrentProject(arguments)
            document.closeToWelcome()
            return document.projectResult()
        }
        handleAuthored("project.create") { document, arguments, author in
            var setup = ProjectSetup()
            setup.name = try arguments.string("name")
            let canvas = try arguments.string("canvas")
            setup.canvasFromFirstClip = canvas == "auto"
            setup.canvas = ProjectSetup.Canvas(rawValue: canvas) ?? .portrait
            setup.resolution = Int(try arguments.string("resolution")).flatMap(ProjectSetup.Resolution.init) ?? .fullHD
            setup.rate = ProjectSetup.Rate(rawValue: try arguments.string("fps")) ?? .ntsc
            setup.contentLanguage = arguments.optionalString("language") ?? ""
            let parent = arguments.optionalString("directory")
                .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
                ?? document.settings.defaultProjectsFolder
            // A footage file links its folder; with import, only that file comes in.
            let given = arguments.optionalString("footage").map { URL(fileURLWithPath: $0) }
            let file = given.flatMap { url in (try? Self.isFolder(url)) == false ? url : nil }
            let footage = given.map { file == nil ? URL(fileURLWithPath: $0.path, isDirectory: true) : $0.deletingLastPathComponent() }
            let importing = arguments.bool("importFootage")
            if importing, footage == nil { throw RPCFailure(-32602, "import needs a footage folder") }
            let brand = try arguments.optionalString("brand").map { try document.libraryCatalog.item($0) }
            if let brand, brand.kind != .brand { throw RPCFailure(-32602, "\(brand.reference) is not a brand kit") }
            try await document.leaveCurrentProject(arguments)
            document.busy = true
            do {
                defer { document.busy = false }
                _ = try await document.createProject(setup, in: parent, footage: footage)
            }
            if let brand { try document.applyBrand(brand, author: author) }
            guard importing, let footage else { return document.projectResult() }
            return try await document.importCreatedFootage(footage, only: file.map { [$0] }, author: author)
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

    /// `project create --import`: the footage folder imported as media, then transcription and picture analysis
    /// started for every media, so the survey can begin while they run. A job that cannot start (no transcription
    /// plugin) is reported in its place; the project stays created either way.
    func importCreatedFootage(_ footage: URL, only: [URL]?, author: Author) async throws -> JSONValue {
        guard let root = fileURL?.deletingLastPathComponent() else { return projectResult() }
        let imported = try await importFolder(
            footage, root: root, arguments: CommandArguments(["baseRev": .integer(project.revision)]), author: author,
            only: only)
        var jobs: [String: JSONValue] = [:]
        do {
            jobs["transcribe"] = try await startMediaTranscribe(mediaID: nil, provider: nil, force: false, author: author)
                .object["job"] ?? .null
        } catch { jobs["transcribe"] = .object(["error": .string(error.localizedDescription)]) }
        do {
            jobs["analyze"] = try startMediaAnalyze(mediaID: nil, force: false, rate: nil, author: author).object["job"] ?? .null
        } catch { jobs["analyze"] = .object(["error": .string(error.localizedDescription)]) }
        var result = projectResult().object
        result["import"] = .object(imported.object.filter { $0.key != "rev" })
        result["jobs"] = .object(jobs)
        return .object(result)
    }

    // MARK: External agents

    /// Issues a fresh external-agent token and writes it to the 0600 token file, or removes both when the
    /// Settings switch is off. Called at launch and from Settings; the token survives project switches.
    func applyExternalAgentAccess(enabled: Bool) { automation.setExternalAgentAccess(enabled) }

    func removeExternalAgentToken() { automation.removeExternalAgentToken() }
}
