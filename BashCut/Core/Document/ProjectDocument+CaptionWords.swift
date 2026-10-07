import BashCutAutomation
import BashCutProject
import Foundation

/// Word-by-word captions (Inspector › Text › Word by word, Auto Captions, `captions words`): one undoable edit sets
/// `wordStyle` (and optionally the highlight colour) on one text item or on every caption.
extension ProjectDocument {
    /// Text items on caption layers, in timeline order.
    var captionItems: [Item] {
        project.tracks.filter { $0.kind == TrackKind.text && $0.role == TrackRole.captions }.flatMap(\.items)
            .sorted { $0.at < $1.at }
    }

    /// Sets the word style — a style name, or `{spoken, upcoming, past}` states; nil: words shown all at once — on
    /// `ids`, or on every caption when `ids` is nil.
    @discardableResult
    func setWordStyle(
        _ style: JSONValue?, items ids: [String]? = nil, highlight: String? = nil, author: Author = .user,
        baseRevision: Int? = nil
    ) throws -> (revision: Int, items: [String]) {
        if let name = style?.string, !CaptionWords.styles.contains(name) {
            throw ProjectError.invalid("Word style must be one of \(CaptionWords.styles.joined(separator: ", ")) or none")
        }
        if let highlight, highlight.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) == nil {
            throw ProjectError.invalid("Highlight colour must look like #FFD400")
        }
        let textItems = project.tracks.filter { $0.kind == TrackKind.text }.flatMap(\.items)
        let targets = try ids.map { ids in
            try ids.map { id in
                guard let item = textItems.first(where: { $0.id == id }) else {
                    throw ProjectError.invalid("\(id) is not a text item")
                }
                return item
            }
        } ?? captionItems
        guard !targets.isEmpty else { throw ProjectError.invalid("There are no captions to change") }
        let operations = targets.map { item -> EditOperation in
            var patch: [String: JSONValue] = ["wordStyle": style ?? .null]
            if let highlight {
                var textStyle = item["textStyle"]?.object ?? [:]
                textStyle["highlight"] = .string(highlight.uppercased())
                patch["textStyle"] = .object(textStyle)
            }
            return .setProperties(item: item.id, patch: patch)
        }
        let label = style == nil ? "Words all at once" : "Word by word"
        let revision = try commit(
            .group(label: label, author: author, ops: operations), label: label, author: author,
            baseRevision: baseRevision)
        return (revision, targets.map(\.id))
    }

    func registerCaptionWordCommands() {
        handleAuthored("captions.words") { document, arguments, author in
            let style = try arguments.string("style")
            let ids: [String]?
            if arguments.bool("all") {
                ids = nil
            } else if let id = arguments.optionalString("item") ?? document.selectedID {
                ids = [id]
            } else {
                throw RPCFailure(-32602, "Give an item, select a caption, or pass all")
            }
            let result = try document.setWordStyle(
                style == "none" ? nil : .string(style), items: ids, highlight: arguments.optionalString("color"), author: author,
                baseRevision: try arguments.int("baseRev"))
            return .object(["rev": .integer(result.revision), "items": .array(result.items.map(JSONValue.string))])
        }
    }
}
