import BashCutAutomation
import BashCutDocument
import BashCutProject
import Foundation

/// How applying an effect preset ended: committed, or waiting for a reversed copy to render in a job.
enum EffectApplyOutcome {
    case applied(revision: Int, itemID: String)
    case rendering(job: String)

    var json: JSONValue {
        switch self {
        case .applied(let revision, let itemID): .object(["rev": .integer(revision), "item": .string(itemID)])
        case .rendering(let job): .object(["job": .string(job), "state": .string("running")])
        }
    }
}

/// Effect presets as recipes (#76): `library apply` with parameter overrides and a range, the Effects panel's Apply
/// with… sheet, and the sound and preview Save selection as… keeps.
extension ProjectDocument {
    /// Applies an effect recipe to the clip `itemID` (or the frames `range` of it, split off in the same edit) as one
    /// undo step. Sounds are copied into the project first; a `reverse` step whose copy is not rendered yet runs as a
    /// job that renders it and then commits the whole recipe.
    func applyEffectPreset(
        _ item: LibraryItem, to itemID: String, values: [String: Double] = [:], range: Range<Int>? = nil,
        author: Author = .user, baseRevision: Int? = nil
    ) async throws -> EffectApplyOutcome {
        let recipe: EffectRecipe
        let steps: [EffectRecipe.Step]
        do {
            recipe = try EffectRecipe(params: item.params, label: item.reference)
            steps = try recipe.resolvedSteps(values, label: item.reference)
        } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
        var application = EffectApplication(values: values, range: range)
        application.sounds = try await effectSounds(item, steps: steps)
        do {
            let plan = try effectPlan(recipe, to: itemID, &application)
            let revision = try commitPlan(plan.planner, label: item.name, author: author, baseRevision: baseRevision)
            recordLibraryUse(item)
            selectedID = plan.itemID
            return .applied(revision: revision, itemID: plan.itemID)
        } catch is EffectReverseNeeded {
            return .rendering(job: startEffectRender(item, recipe: recipe, to: itemID, application, author: author))
        }
    }

    /// `library apply` for an effect preset: `set` overrides and the range `from`/`to` (timeline frames; the clip's
    /// start and end by default).
    func applyEffect(
        _ item: LibraryItem, to target: String, arguments: CommandArguments, author: Author
    ) async throws -> JSONValue {
        let values: [String: Double]
        do { values = try arguments.optionalString("set").map(EffectRecipe.overrides) ?? [:] } catch {
            throw RPCFailure.from(error, fallbackCode: -32602)
        }
        var range: Range<Int>?
        let from = arguments.optionalInt("from"), to = arguments.optionalInt("to")
        if from != nil || to != nil {
            guard let clip = project.tracks.flatMap(\.items).first(where: { $0.id == target }) else {
                throw RPCFailure(-32602, "Unknown item \(target)")
            }
            let lower = from ?? clip.at, upper = to ?? clip.end
            guard lower < upper else { throw RPCFailure(-32602, "from must be before to") }
            range = lower..<upper
        }
        let outcome = try await applyEffectPreset(
            item, to: target, values: values, range: range, author: author, baseRevision: try arguments.int("baseRev"))
        guard case .object(var result) = outcome.json else { return outcome.json }
        result["library"] = .string(item.reference)
        return .object(result)
    }

    /// The plan, with reversed copies already in the project (and on disk) filled in. Throws `EffectReverseNeeded`
    /// for a copy that still has to be rendered.
    private func effectPlan(
        _ recipe: EffectRecipe, to itemID: String, _ application: inout EffectApplication
    ) throws -> (planner: LayerPlanner, itemID: String) {
        let root = fileURL?.deletingLastPathComponent()
        while true {
            do {
                return try project.effectRecipePlan(recipe, to: itemID, application)
            } catch let need as EffectReverseNeeded {
                guard application.reversed[need.path] == nil, let root,
                    let existing = project.media.first(where: { $0.path == need.path }),
                    FileManager.default.fileExists(atPath: root.appendingPathComponent(need.path).path)
                else { throw need }
                application.reversed[need.path] = existing
            } catch let error as ProjectError {
                throw RPCFailure.invalid(error)
            }
        }
    }

    private func startEffectRender(
        _ item: LibraryItem, recipe: EffectRecipe, to itemID: String, _ application: EffectApplication, author: Author
    ) -> String {
        let session = sessionID
        return jobs.start("library.apply", author: author, detail: item.name, work: { [weak self] reporter in
            guard let self else { throw CancellationError() }
            var application = application
            while true {
                do {
                    let plan = try self.effectPlan(recipe, to: itemID, &application)
                    let revision = try self.commitPlan(plan.planner, label: item.name, author: author, baseRevision: nil)
                    self.recordLibraryUse(item)
                    return .object([
                        "rev": .integer(revision), "item": .string(plan.itemID), "library": .string(item.reference),
                    ])
                } catch let need as EffectReverseNeeded {
                    guard application.reversed[need.path] == nil else { throw need }
                    application.reversed[need.path] = try await self.renderReversedCopy(need, reporter: reporter)
                    try self.ensureSession(session)
                }
            }
        }, finished: { [weak self] outcome in
            guard case .failure(let error) = outcome, !JobCenter.isCancellation(error) else { return }
            self?.message = error.localizedDescription
        })
    }

    /// The project media for each `sfx` step's sound: an audio library item, or the preset's own file.
    private func effectSounds(_ item: LibraryItem, steps: [EffectRecipe.Step]) async throws -> [String: Media] {
        var sounds: [String: Media] = [:]
        for step in steps {
            guard case .sfx(let reference, _, _) = step else { continue }
            let key = reference ?? EffectRecipe.ownSound
            guard sounds[key] == nil else { continue }
            let source: LibraryItem
            if let reference {
                do { source = try libraryCatalog.item(reference) } catch { throw RPCFailure.from(error, fallbackCode: -32602) }
                guard source.kind == .audio else { throw RPCFailure(-32602, "\(reference) is not an audio library item") }
            } else {
                guard item.file != nil else {
                    throw RPCFailure(-32602, "\(item.reference) has an sfx step without sfx and no sound file of its own")
                }
                source = item
            }
            sounds[key] = try await librarySoundMedia(source)
        }
        return sounds
    }

    /// The sound effect Save selection as… keeps with a clip: one a recipe placed for it, or else a sound on an SFX
    /// layer that starts with it.
    func effectSound(of item: Item) -> (item: Item, media: Media)? {
        let audio = project.tracks.filter { $0.kind == TrackKind.audio }
        let tagged = audio.flatMap(\.items).first { $0[EffectRecipe.soundField]?.string == item.id }
        let sound = tagged ?? audio.filter { $0.role == TrackRole.sfx }.flatMap(\.items).first { $0.at == item.at }
        guard let sound, let media = project.media.first(where: { $0.id == sound.mediaID }) else { return nil }
        return (sound, media)
    }

    /// A small still of the clip's middle as an effect preset's preview, when the viewer can render one; nil
    /// otherwise (the preset is saved without one).
    func effectPreview(itemID: String?) async -> URL? {
        guard let id = itemID ?? selectedID, let item = project.tracks.flatMap(\.items).first(where: { $0.id == id }),
            project.tracks.first(where: { $0.items.contains { $0.id == id } })?.kind == TrackKind.video
        else { return nil }
        return try? await captureAgentFrame(at: item.at + item.duration / 2, maximumDimension: 320).url
    }

    // MARK: Apply with…

    /// Opens Apply with… for an effect preset on the selected clip.
    func beginEffectApply(_ item: LibraryItem) {
        guard let selected else { return }
        do {
            let recipe = try EffectRecipe(params: item.params, label: item.reference)
            ui.effectApply = EffectApplyRequest(
                item: item, itemID: selected.id, parameters: recipe.parameters, clip: selected.at..<selected.end,
                playhead: playhead)
        } catch { message = error.localizedDescription }
    }

    /// Applies what Apply with… shows (`library apply --set … --from … --to …` does the same) and closes it.
    func commitEffectApply() {
        guard let request = ui.effectApply else { return }
        ui.effectApply = nil
        Task {
            do {
                if case .rendering = try await applyEffectPreset(
                    request.item, to: request.itemID, values: request.overrides, range: request.range)
                {
                    message = String(localized: "Rendering the reversed clip…")
                }
            } catch { message = error.localizedDescription }
        }
    }

    /// Apply with… as automation sees it.
    func effectApplySheet() -> ModalSheet? {
        guard let request = ui.effectApply else { return nil }
        let values = request.parameters.map { "\($0.name)=\(request.values[$0.name] ?? $0.value)" }.joined(separator: ",")
        let range = request.range.map { " · frames \($0.lowerBound)–\($0.upperBound)" } ?? ""
        return ModalSheet(
            name: "effect-apply", title: "Apply with",
            message: "\(request.item.reference) on \(request.itemID)\(values.isEmpty ? "" : " · " + values)\(range); "
                + "library apply --set name=value --from --to does the same with every value.",
            options: [ModalOption("apply", String(localized: "Apply")), ModalOption("cancel", String(localized: "Cancel"))]
        ) { [weak self] option in
            if option == "apply" { self?.commitEffectApply() } else { self?.ui.effectApply = nil }
        }
    }
}
