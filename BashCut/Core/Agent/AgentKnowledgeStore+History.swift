import Foundation

/// Knowledge history (#70): every change to lessons, preferences, facts, memos and project skills is one line of the
/// scope's `history.jsonl`, with who made it and the entry before and after. `revert` puts an entry back to how it
/// was before a change and records that as a change of its own, so a revert can be reverted too.
extension AgentKnowledgeStore {
    /// Changes, newest first, of one scope or both; only those of `kind` and `target` when given.
    public func history(
        _ scope: KnowledgeScope? = nil, kind: KnowledgeChange.Kind? = nil, target: String? = nil, limit: Int = 50
    ) -> [KnowledgeChange] {
        let changes = (scope.map { [$0] } ?? scopes).flatMap { scope -> [(change: KnowledgeChange, line: Int)] in
            guard let url = entriesFolder(scope)?.appendingPathComponent("history.jsonl"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").enumerated().compactMap { line, text in
                guard var change = try? Self.decoder.decode(KnowledgeChange.self, from: Data(text.utf8)),
                      kind == nil || change.kind == kind, target == nil || change.target == target else {
                    return nil
                }
                change.scope = scope
                return (change, line)
            }
        }
        // Dates have whole seconds, so later lines of the same file win ties.
        return Array(changes.sorted {
            $0.change.source.date != $1.change.source.date
                ? $0.change.source.date > $1.change.source.date : $0.line > $1.line
        }.prefix(limit).map(\.change))
    }

    public func change(_ id: String) throws -> KnowledgeChange {
        guard let change = history(limit: .max).first(where: { $0.id == id }) else {
            throw KnowledgeError("No change \(id) in knowledge history")
        }
        return change
    }

    func record(_ change: KnowledgeChange, scope: KnowledgeScope) throws {
        let url = try folder(scope).appendingPathComponent("history.jsonl")
        let encoder = Self.encoder
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(change)
        line.append(UInt8(ascii: "\n"))
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
    }

    // MARK: Revert

    /// Puts the changed entry back to how it was before change `id`: a removed lesson, value or skill comes back, an
    /// added one goes, an edited one gets its earlier fields or text. Later changes to the same entry are undone
    /// with it. Returns the change the revert recorded.
    @discardableResult
    public func revert(_ id: String, source: KnowledgeSource) throws -> KnowledgeChange {
        let change = try change(id)
        guard change.isRevertible else {
            throw KnowledgeError("Rejecting a preference proposal changed no value, so there is nothing to revert")
        }
        guard !isCurrent(change.before, of: change) else {
            throw KnowledgeError("\(change.target) is already as it was before this change")
        }
        switch change.kind {
        case .lesson: try restoreLesson(change, source: source)
        case .prefs, .facts: try restoreValue(change, source: source)
        case .memo:
            try writeMemo(change.before?.text ?? "", scope: change.scope, source: source, action: .revert)
        case .skill:
            if let text = change.before?.text {
                try writeSkill(named: change.target, text: text, source: source, action: .revert)
            } else {
                try removeSkill(named: change.target, source: source, action: .revert)
            }
        }
        guard let reverted = history(change.scope, limit: 1).first, reverted.action == .revert else {
            throw KnowledgeError("The revert was not recorded")
        }
        return reverted
    }

    /// Whether the entry `change` touched is already `entry` now (nil: it does not exist).
    private func isCurrent(_ entry: KnowledgeEntry?, of change: KnowledgeChange) -> Bool {
        switch change.kind {
        case .lesson:
            let current = (try? readLessons(change.scope))?.first { $0.id == change.target }
            guard case .lesson(let lesson)? = entry else { return current == nil }
            return current.map(KnowledgeEntry.lesson)?.diffText == KnowledgeEntry.lesson(lesson).diffText
        case .prefs, .facts:
            let current = (try? readValues(change.kind == .prefs ? .prefs : .facts, change.scope))?
                .first { $0.key == change.target }
            guard case .value(let value)? = entry else { return current == nil }
            return current?.value == value.value
        case .memo: return memo(change.scope) == entry?.text ?? ""
        case .skill: return skillText(change.target) == entry?.text
        }
    }

    private func restoreLesson(_ change: KnowledgeChange, source: KnowledgeSource) throws {
        var all = try readLessons(change.scope, writable: true)
        let index = all.firstIndex { $0.id == change.target }
        let current = index.map { all[$0] }
        var restored: KnowledgeLesson?
        if case .lesson(var lesson)? = change.before {
            lesson.updated = source.date
            lesson.scope = change.scope
            if let index { all[index] = lesson } else { all.append(lesson) }
            restored = lesson
        } else if let index {
            all.remove(at: index)
        }
        try writeLessons(all, scope: change.scope)
        try record(KnowledgeChange(
            action: .revert, kind: .lesson, target: change.target, source: source,
            before: current.map(KnowledgeEntry.lesson), after: restored.map(KnowledgeEntry.lesson)), scope: change.scope)
    }

    /// The restored value keeps the source it had before the change; history credits the revert to `source`.
    private func restoreValue(_ change: KnowledgeChange, source: KnowledgeSource) throws {
        let kind: KnowledgeValueKind = change.kind == .prefs ? .prefs : .facts
        var all = try readValues(kind, change.scope, writable: true)
        let index = all.firstIndex { $0.key == change.target }
        let current = index.map { all[$0] }
        var restored: KnowledgeValue?
        if case .value(var value)? = change.before {
            value.scope = change.scope
            if let index { all[index] = value } else { all.append(value) }
            restored = value
        } else if let index {
            all.remove(at: index)
        }
        try writeValues(all, kind: kind, scope: change.scope)
        try record(KnowledgeChange(
            action: .revert, kind: change.kind, target: change.target, source: source,
            before: current.map(KnowledgeEntry.value), after: restored.map(KnowledgeEntry.value)), scope: change.scope)
    }
}

extension KnowledgeEntry {
    /// A memo's or skill's text; nil for lessons and values.
    public var text: String? {
        if case .text(let text) = self { return text }
        return nil
    }
}

extension KnowledgeChange {
    /// The change as a unified diff of `before` and `after` (see `KnowledgeEntry.diffText`).
    public var diff: String {
        KnowledgeDiff.unified(before?.diffText ?? "", after?.diffText ?? "")
    }
}

/// Line diffs for knowledge history.
public enum KnowledgeDiff {
    /// Lines of `after` that are new start with `+`, lines of `before` that are gone with `-`, unchanged lines with
    /// a space. Unchanged runs farther than `context` lines from a change are folded into one `@@ … @@` line.
    public static func unified(_ before: String, _ after: String, context: Int = 3) -> String {
        let old = lines(before)
        let new = lines(after)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for step in new.difference(from: old) {
            switch step {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var output: [String] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if oldIndex < old.count, removed.contains(oldIndex) {
                output.append("-" + old[oldIndex])
                oldIndex += 1
            } else if newIndex < new.count, inserted.contains(newIndex) {
                output.append("+" + new[newIndex])
                newIndex += 1
            } else {
                output.append(" " + old[oldIndex])
                oldIndex += 1
                newIndex += 1
            }
        }
        return fold(output, context: context).joined(separator: "\n")
    }

    /// A final newline ends the last line rather than starting an empty one.
    private static func lines(_ text: String) -> [String] {
        var lines = text.isEmpty ? [] : text.components(separatedBy: "\n")
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    /// Keeps changed lines and `context` lines around them; each longer unchanged run becomes one `@@` line.
    private static func fold(_ lines: [String], context: Int) -> [String] {
        let changed = lines.indices.filter { !lines[$0].hasPrefix(" ") }
        guard !changed.isEmpty else { return lines }
        let kept = Set(changed.flatMap { max(0, $0 - context)...min(lines.count - 1, $0 + context) })
        var output: [String] = []
        var skipped = 0
        for index in lines.indices {
            if kept.contains(index) {
                if skipped > 0 { output.append("@@ \(skipped) unchanged lines @@") }
                skipped = 0
                output.append(lines[index])
            } else {
                skipped += 1
            }
        }
        if skipped > 0 { output.append("@@ \(skipped) unchanged lines @@") }
        return output
    }
}
