import BashCutAutomation
import BashCutProject
import Foundation

extension ProjectDocument {
    var selectedTransition: TimelineTransition? {
        guard let selectedID else { return nil }
        return project.transitions.first {
            $0.fromItemID == selectedID || $0.toItemID == selectedID
        }
    }

    func setSelectedTransition(kind: String) {
        guard let cut = selectedVideoCut() else {
            message = String(localized: "Select a video clip beside a cut")
            return
        }
        let existing = project.transitions.first {
            $0.fromItemID == cut.from.id && $0.toItemID == cut.to.id
        }
        let duration = existing?.duration ?? min(15, max(1, min(cut.from.duration, cut.to.duration) / 3))
        apply(
            .upsertTransition(
                id: existing?.id ?? "transition-\(cut.from.id)-\(cut.to.id)", kind: kind,
                from: cut.from.id, to: cut.to.id, duration: duration, easing: existing?.easing),
            label: "Set \(kind) transition")
    }

    func removeSelectedTransition() {
        guard let transition = selectedTransition else { return }
        apply(.deleteTransition(id: transition.id), label: "Remove transition")
    }

    func adjustSelectedTransitionDuration(by delta: Int) {
        guard let transition = selectedTransition,
            let cut = transitionCut(transition)
        else { return }
        let duration = min(
            min(cut.from.duration, cut.to.duration), max(1, transition.duration + delta))
        apply(
            .upsertTransition(
                id: transition.id, kind: transition.kind, from: transition.fromItemID,
                to: transition.toItemID, duration: duration, easing: transition.easing),
            label: "Change transition duration")
    }

    /// Sets how the selected transition's tween runs (`TimelineTransition.easings`).
    func setSelectedTransitionEasing(_ easing: String) {
        guard let transition = selectedTransition, easing != transition.easing else { return }
        apply(
            .upsertTransition(
                id: transition.id, kind: transition.kind, from: transition.fromItemID,
                to: transition.toItemID, duration: transition.duration, easing: easing),
            label: "Change transition easing")
    }

    private func selectedVideoCut() -> (from: Item, to: Item)? { selectedID.flatMap(videoCut(at:)) }

    /// The cut beside the video clip `itemID`: before it, or else after it.
    func videoCut(at itemID: String) -> (from: Item, to: Item)? { project.videoCut(beside: itemID) }

    private func transitionCut(_ transition: TimelineTransition) -> (from: Item, to: Item)? {
        let items = project.tracks.flatMap(\.items)
        guard let from = items.first(where: { $0.id == transition.fromItemID }),
            let to = items.first(where: { $0.id == transition.toItemID })
        else { return nil }
        return (from, to)
    }

    // MARK: Transition presets

    /// Applies a transition preset (#77) at the cut beside the video clip `itemID` as one undo step: its kind,
    /// duration (at most the shorter clip) and easing, and its sound effect on an SFX layer when it has one.
    func applyTransitionPreset(
        _ item: LibraryItem, at itemID: String, author: Author, baseRevision: Int?
    ) async throws -> Int {
        let preset: TransitionPreset
        do { preset = try TransitionPreset(params: item.params, label: item.reference) } catch {
            throw RPCFailure(-32602, error.localizedDescription)
        }
        let sound = try await transitionSoundMedia(item, preset)
        let planner: LayerPlanner
        do { planner = try project.transitionPresetPlan(preset, at: itemID, sound: sound) } catch {
            throw RPCFailure(-32602, error.localizedDescription)
        }
        return try commitPlan(planner, label: item.name, author: author, baseRevision: baseRevision)
    }

    /// The project media for a transition preset's sound: its `sfx` audio item's file, or its own file.
    private func transitionSoundMedia(_ item: LibraryItem, _ preset: TransitionPreset) async throws -> Media? {
        let catalog = libraryCatalog
        let source: LibraryItem
        if let sfx = preset.sfx {
            do { source = try catalog.item(sfx) } catch { throw RPCFailure(-32602, error.localizedDescription) }
            guard source.kind == .audio else { throw RPCFailure(-32602, "\(sfx) is not an audio library item") }
        } else if item.file != nil {
            source = item
        } else {
            return nil
        }
        return try await librarySoundMedia(source)
    }
}
