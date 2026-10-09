import Foundation

/// `upsertTransition` and `deleteTransition`: one transition per cut between adjacent clips on a video layer.
extension Project {
    mutating func upsertTransition(_ transition: TimelineTransition) throws {
        try transition.checkKindAndEasing()
        // Replacing a transition keeps the fields this version does not know; a linear easing and a built-in
        // motion are no field.
        var value = transition
        if let existing = transitions.first(where: { $0.id == transition.id }) {
            value.fields = existing.fields.merging(transition.fields) { $1 }
            value.fields["easing"] = transition.fields["easing"]
            value.fields["motion"] = transition.fields["motion"]
        }
        guard transitionIsValid(value) else { throw ProjectError.invalid("Transition requires an adjacent video cut") }
        var values = transitions
        values.removeAll { $0.id == value.id || $0.fromItemID == value.fromItemID || $0.toItemID == value.toItemID }
        values.append(value)
        transitions = values
    }

    mutating func deleteTransition(id: String) throws {
        var values = transitions
        guard let index = values.firstIndex(where: { $0.id == id }) else {
            throw ProjectError.invalid("Unknown transition: \(id)")
        }
        values.remove(at: index)
        transitions = values
    }
}
