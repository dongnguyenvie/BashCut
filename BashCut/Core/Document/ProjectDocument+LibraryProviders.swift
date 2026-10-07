import BashCutAutomation
import BashCutDocument
import BashCutPlugin
import BashCutPlugins
import BashCutProject
import Foundation

/// What `library search` and `library generate` ask a plugin for (#81).
struct LibraryProviderRequest {
    /// `library.search` or `library.generate`.
    var capability: String
    var kind: LibraryKind
    /// The search text or prompt.
    var text: String
    var provider: String?
    var limit: Int
    var page = 1
    var hints: [String: JSONValue] = [:]
    /// A candidate to save when the job finishes, and where.
    var save: Int?
    var scope: LibraryScope = .project
    /// The caller's stable request ID (P2-G4).
    var requestID: String?

    var method: String { capability == PluginAPI.libraryGenerate ? "library.generate" : "library.search" }
}

/// Library items from plugins that search or generate them (#81): the job, saving a candidate, and the panels'
/// Search… and Generate… sheet. Plugin packs (`contributes.library`) need nothing here: `libraryCatalog` lists them.
extension ProjectDocument {
    // MARK: Jobs

    /// Starts a `library.search` or `library.generate` job and returns its ID. `finished` runs when it ends.
    @discardableResult
    func startLibraryProviderJob(
        _ request: LibraryProviderRequest, author: Author,
        finished: @escaping @MainActor (Result<JSONValue, any Error>) -> Void = { _ in }
    ) throws -> String {
        guard !plugins.calling.contains(request.capability) else {
            throw RPCFailure(-32003, "\(request.capability) is already running; retry later", category: .busyRunning)
        }
        if request.save != nil, request.scope == .project, fileURL == nil {
            throw RPCFailure(-32602, "Open a saved project to save into its library, or pass --scope user")
        }
        let job = jobs.start(
            request.method, author: author, detail: request.text, requestID: request.requestID, work: { [weak self] _ in
            guard let self else { throw CancellationError() }
            return try await runLibraryProvider(request, author: author)
        }, finished: { [weak self] outcome in
            if case .failure(let error) = outcome, !JobCenter.isCancellation(error) {
                self?.message = request.method + ": " + error.localizedDescription
            }
            finished(outcome)
        })
        return job
    }

    func runLibraryProvider(_ request: LibraryProviderRequest, author: Author) async throws -> JSONValue {
        let root = fileURL?.deletingLastPathComponent()
        let service = plugins.service
        let language = contentLanguage
        let found = try await plugins.running(request.capability) {
            if request.capability == PluginAPI.libraryGenerate {
                return try await service.generateLibrary(
                    kind: request.kind, prompt: request.text, limit: request.limit, hints: request.hints,
                    language: language, provider: request.provider, projectRoot: root)
            }
            return try await service.searchLibrary(
                kind: request.kind, query: request.text, limit: request.limit, page: request.page, language: language,
                provider: request.provider, projectRoot: root)
        }
        var result = found.json.object
        guard let index = request.save else { return .object(result) }
        do {
            guard found.candidates.indices.contains(index) else {
                throw RPCFailure(-32602, "No candidate \(index) to save; the provider returned \(found.candidates.count)")
            }
            result["saved"] = try await saveLibraryCandidate(
                found.candidates[index], provider: result["provider"], scope: request.scope, author: author)
        } catch {
            // The candidates stay usable with library add --from-result.
            result["saveError"] = .string(error.localizedDescription)
        }
        return .object(result)
    }

    // MARK: Saving

    /// Saves a candidate as a new item in `scope` (`library add --from-result`): its fields with `changes` over them, its
    /// file and preview copied in, the provider as `provenance` and the plugin in `createdBy`.
    func saveLibraryCandidate(
        _ candidate: LibraryCandidate, provider: JSONValue?, scope: LibraryScope, author: Author,
        changes overrides: [String: JSONValue] = [:], name: String? = nil, id: String? = nil
    ) async throws -> JSONValue {
        guard let kind = candidate.item.kind else { throw RPCFailure(-32602, "The candidate has no kind") }
        var changes = candidate.changes
        if let provider { changes["provenance"] = provider }
        changes.merge(overrides) { $1 }
        let name = name ?? candidate.item.name
        return try await addLibraryItem(
            kind: kind, name: name, id: id ?? (try freeLibraryID(for: name, fallback: candidate.item.id)), scope: scope,
            changes: changes, file: candidate.fileURL, preview: candidate.previewURL, author: author,
            plugin: provider?.object["plugin"]?.string)
    }

    /// `library add --from-result <job>:<index>`.
    func saveLibraryCandidate(
        _ reference: String, arguments: CommandArguments, changes: [String: JSONValue], author: Author
    ) async throws -> JSONValue {
        guard let colon = reference.lastIndex(of: ":"), let index = Int(reference[reference.index(after: colon)...]) else {
            throw RPCFailure(-32602, "fromResult is <job>:<index>, such as 6F1C…:0")
        }
        let jobID = String(reference[..<colon])
        guard let job = jobs.job(jobID) else {
            throw RPCFailure(-32602, "No job \(jobID); jobs status lists the recent ones")
        }
        guard ["library.search", "library.generate"].contains(job.method), job.state == .completed else {
            throw RPCFailure(-32602, "\(jobID) is not a finished library search or generate job")
        }
        let candidate: LibraryCandidate
        do { candidate = try LibraryCandidate(jobResult: job.result, index: index) } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
        if let kind = arguments.optionalString("kind"), kind != candidate.item.kind?.rawValue {
            throw RPCFailure(-32602, "Candidate \(index) is \(candidate.item.kind?.rawValue ?? "unknown"), not \(kind)")
        }
        var overrides = changes
        overrides["name"] = nil
        return try await saveLibraryCandidate(
            candidate, provider: job.result.object["provider"],
            scope: LibraryScope(rawValue: arguments.optionalString("scope") ?? "project") ?? .project, author: author,
            changes: overrides, name: arguments.optionalString("name"), id: arguments.optionalString("id"))
    }

    /// An ID from `name` (or `fallback`) that no library item has yet.
    private func freeLibraryID(for name: String, fallback: String) throws -> String {
        let taken = Set(try libraryCatalog.items().map(\.id))
        let slug = Self.libraryID(from: name)
        let base = String((slug.isEmpty ? fallback : slug).prefix(60))
        var id = base
        var number = 2
        while taken.contains(id) {
            id = "\(base)-\(number)"
            number += 1
        }
        return id
    }

    // MARK: Panel sheet

    /// Library providers for `capability` that serve one of `kinds` in plugins that may run now.
    func libraryProviders(_ capability: String, kinds: [LibraryKind]) -> [PluginProviderChoice] {
        plugins.libraryProviders(capability, kinds: kinds)
    }

    /// Search… or Generate… in a library panel.
    func beginLibrarySearch(_ capability: String, kinds: [LibraryKind]) {
        var request = LibrarySearchRequest(capability: capability, kinds: kinds, scope: defaultLibraryScope)
        let served = kinds.filter { kind in
            !plugins.libraryProviders(capability, kinds: [kind]).isEmpty
        }
        request.kind = served.first ?? request.kind
        ui.librarySearch = request
    }

    /// The sheet's Search or Generate: runs the same job as the command, as the user, and shows its candidates.
    func runLibrarySearchSheet() {
        guard var request = ui.librarySearch else { return }
        let text = request.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            message = String(localized: request.isGenerate ? "Describe what to make" : "Type what to look for")
            return
        }
        let started = StartedJob()
        let job: String
        do {
            job = try startLibraryProviderJob(
                LibraryProviderRequest(
                    capability: request.capability, kind: request.kind, text: text, provider: request.provider,
                    limit: request.isGenerate ? 4 : 12),
                author: .user
            ) { [weak self] outcome in
                guard let self, var current = ui.librarySearch, current.jobID == started.id else { return }
                current.running = false
                switch outcome {
                case .success(let result):
                    current.candidates = (0..<(result.object["candidates"]?.array.count ?? 0)).compactMap {
                        try? LibraryCandidate(jobResult: result, index: $0)
                    }
                    current.error = current.candidates.isEmpty ? String(localized: "Nothing found.") : nil
                case .failure(let error):
                    current.error = error.localizedDescription
                }
                ui.librarySearch = current
            }
        } catch {
            request.error = error.localizedDescription
            ui.librarySearch = request
            return
        }
        started.id = job
        request.jobID = job
        request.running = true
        request.candidates = []
        request.saved = []
        request.error = nil
        ui.librarySearch = request
    }

    /// The sheet's Save on candidate `index`: `library add --from-result <job>:<index>` as the user.
    func saveLibrarySearchCandidate(_ index: Int) {
        guard let request = ui.librarySearch, request.candidates.indices.contains(index), let jobID = request.jobID else {
            return
        }
        let candidate = request.candidates[index]
        let provider = jobs.job(jobID)?.result.object["provider"]
        Task {
            do {
                _ = try await saveLibraryCandidate(candidate, provider: provider, scope: request.scope, author: .user)
                ui.librarySearch?.saved.insert(index)
                message = String(localized: "Saved “\(candidate.item.name)” in the library")
            } catch {
                message = error.localizedDescription
            }
        }
    }

    /// The sheet as automation sees it: run, save a candidate by index, or close.
    func librarySearchSheet() -> ModalSheet? {
        guard let request = ui.librarySearch else { return nil }
        let verb = request.isGenerate ? "generate" : "search"
        let found = request.candidates.enumerated().map { "\($0.offset): \($0.element.item.name)" }.joined(separator: ", ")
        let state = request.running ? "running" : request.error ?? (found.isEmpty ? "no candidates yet" : found)
        var options = [
            ModalOption("run", request.isGenerate ? String(localized: "Generate") : String(localized: "Search")),
        ]
        options += request.candidates.indices.map { ModalOption("save-\($0)", String(localized: "Save \($0)")) }
        options.append(ModalOption("close", String(localized: "Close")))
        return ModalSheet(
            name: "library-search", title: request.isGenerate ? "Generate library items" : "Search library items",
            message: "\(request.kind.rawValue) · “\(request.text)” · \(state); library \(verb) and library add "
                + "--from-result do the same.",
            options: options
        ) { [weak self] option in
            guard let self else { return }
            if option == "run" {
                runLibrarySearchSheet()
            } else if option.hasPrefix("save-"), let index = Int(option.dropFirst(5)) {
                saveLibrarySearchCandidate(index)
            } else {
                ui.librarySearch = nil
            }
        }
    }

    // MARK: Automation

    func registerLibraryProviderCommands() {
        for (method, capability) in [("library.search", PluginAPI.librarySearch), ("library.generate", PluginAPI.libraryGenerate)] {
            handleAuthored(method) { document, arguments, author in
                let kind = try LibraryKind(rawValue: arguments.string("kind")).orThrow("Unknown kind")
                var request = LibraryProviderRequest(
                    capability: capability, kind: kind,
                    text: try arguments.string(capability == PluginAPI.libraryGenerate ? "prompt" : "query"),
                    provider: arguments.optionalString("provider"),
                    limit: arguments.optionalInt("limit") ?? (capability == PluginAPI.libraryGenerate ? 4 : 12))
                request.page = arguments.optionalInt("page") ?? 1
                request.hints = arguments["params"]?.object ?? [:]
                request.save = arguments.optionalInt("save")
                request.scope = LibraryScope(rawValue: arguments.optionalString("scope") ?? "project") ?? .project
                request.requestID = arguments.optionalString("requestId")
                if arguments.bool("dryRun") {
                    return try await document.capabilityDryRun { document in
                        try await document.runLibraryProvider(request, author: author)
                    }
                }
                if let reused = document.reusedJob(request.method, requestID: request.requestID) { return reused }
                let job = try document.startLibraryProviderJob(request, author: author)
                return .object(["job": .string(job), "state": .string("running")])
            }
        }
    }
}

/// The ID of a job its `finished` callback needs, set once `start` returns it.
@MainActor
private final class StartedJob {
    var id: String?
}

private extension Optional {
    func orThrow(_ message: String) throws -> Wrapped {
        guard let self else { throw RPCFailure(-32602, message) }
        return self
    }
}
