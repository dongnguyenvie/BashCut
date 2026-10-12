import Foundation

/// The blocks of a SKILL.md body for the Knowledge › Skills preview: headings, bullet and numbered list items, quotes,
/// rules, code blocks (tables are shown as code) and paragraphs. Inline styling is left to the view.
public enum SkillMarkdown {
    public enum Block: Hashable, Sendable {
        case heading(Int, String), bullet(String), numbered(String, String), quote(String), rule, code(String)
        case paragraph(String)
    }

    public static func blocks(_ body: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) } else { flush() }
                code = code == nil ? [] : nil
            } else if code != nil {
                code?.append(line)
            } else if trimmed.isEmpty {
                flush()
            } else if line.first?.isWhitespace == true, paragraph.isEmpty, let item = continued(blocks.last, with: trimmed) {
                // An indented line continues the list item above it.
                blocks[blocks.count - 1] = item
            } else if let block = lineBlock(trimmed, after: blocks.last) {
                flush()
                if case .code = block, case .code(let table)? = blocks.last, table.hasPrefix("|") { blocks.removeLast() }
                if case .quote = block, case .quote? = blocks.last { blocks.removeLast() }
                blocks.append(block)
            } else {
                paragraph.append(trimmed)
            }
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// The list item `previous` with `line` joined to it; nil when `previous` is not a list item.
    private static func continued(_ previous: Block?, with line: String) -> Block? {
        switch previous {
        case .bullet(let item)?: .bullet(item + " " + line)
        case .numbered(let number, let item)?: .numbered(number, item + " " + line)
        default: nil
        }
    }

    /// A heading, list item, quote, rule or table row; nil for paragraph text. Table rows join the table above them,
    /// quote lines the quote above them.
    private static func lineBlock(_ line: String, after previous: Block?) -> Block? {
        if line.hasPrefix("#"), let hashes = line.firstIndex(where: { $0 != "#" }), line[hashes] == " " {
            return .heading(line.distance(from: line.startIndex, to: hashes),
                            String(line[hashes...]).trimmingCharacters(in: .whitespaces))
        }
        if ["---", "***", "___"].contains(line.replacingOccurrences(of: " ", with: "")) { return .rule }
        if line.hasPrefix("- ") || line.hasPrefix("* ") { return .bullet(String(line.dropFirst(2))) }
        if let dot = line.firstIndex(where: { !$0.isASCII || !$0.isNumber }), dot != line.startIndex,
            line[dot] == ".", line[line.index(after: dot)...].hasPrefix(" "), line.distance(from: line.startIndex, to: dot) <= 3
        {
            return .numbered(String(line[..<dot]), String(line[line.index(dot, offsetBy: 2)...]))
        }
        if line == ">" || line.hasPrefix("> ") {
            let text = String(line.dropFirst(line == ">" ? 1 : 2))
            if case .quote(let above)? = previous { return .quote(above.isEmpty ? text : above + "\n" + text) }
            return .quote(text)
        }
        guard line.hasPrefix("|") else { return nil }
        if case .code(let table)? = previous, table.hasPrefix("|") { return .code(table + "\n" + line) }
        return .code(line)
    }
}

extension AgentKnowledgeStore {
    /// Whether `name` would be taken as a skill name (`skillName`), for checking a field while it is typed.
    public static func isValidSkillName(_ name: String) -> Bool { (try? skillName(name)) != nil }
}
