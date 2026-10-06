import BashCutProject

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
                from: cut.from.id, to: cut.to.id, duration: duration),
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
                to: transition.toItemID, duration: duration),
            label: "Change transition duration")
    }

    private func selectedVideoCut() -> (from: Item, to: Item)? { selectedID.flatMap(videoCut(at:)) }

    /// The cut beside the video clip `itemID`: before it, or else after it.
    func videoCut(at itemID: String) -> (from: Item, to: Item)? {
        for track in project.tracks where track.kind == "video" {
            let items = track.items.sorted { ($0.at, $0.id) < ($1.at, $1.id) }
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { continue }
            if index > 0, items[index - 1].end == items[index].at {
                return (items[index - 1], items[index])
            }
            if index + 1 < items.count, items[index].end == items[index + 1].at {
                return (items[index], items[index + 1])
            }
        }
        return nil
    }

    private func transitionCut(_ transition: TimelineTransition) -> (from: Item, to: Item)? {
        let items = project.tracks.flatMap(\.items)
        guard let from = items.first(where: { $0.id == transition.fromItemID }),
            let to = items.first(where: { $0.id == transition.toItemID })
        else { return nil }
        return (from, to)
    }
}
