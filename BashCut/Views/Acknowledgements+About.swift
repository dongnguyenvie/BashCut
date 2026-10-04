import AppKit

extension Acknowledgements {
    /// The About panel's acknowledgements: one line per linked package (linking to its repository) and a link that
    /// opens the verbatim license texts. The texts go to a file because the credits area is narrow and their hard
    /// line breaks read badly there.
    static func aboutPanelText() -> NSAttributedString {
        let text = NSMutableAttributedString()
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        let small = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        func append(_ string: String, _ attributes: [NSAttributedString.Key: Any]) {
            var attributes = attributes
            attributes[.paragraphStyle] = centered
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        append("\n\n" + String(localized: "Acknowledgements") + "\n", [
            .font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor,
        ])
        for package in packages {
            var name: [NSAttributedString.Key: Any] = [.font: small]
            if let url = URL(string: package.url) { name[.link] = url }
            append(package.name, name)
            append(" \(package.version) · \(package.license)\n", [.font: small, .foregroundColor: NSColor.secondaryLabelColor])
        }
        if let file = try? writeLicenseFile() {
            append(String(localized: "Show license texts…"), [.font: small, .link: file])
        }
        return text
    }

    /// Writes every package's license text to one file in the app's temporary folder and returns its URL.
    static func writeLicenseFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BashCut Acknowledgements.txt")
        let body = packages.map { package in
            "\(package.name) \(package.version) — \(package.license)\n\(package.url)\n\n\(package.text)"
        }.joined(separator: "\n\n" + String(repeating: "-", count: 72) + "\n\n")
        try (String(localized: "Acknowledgements") + "\n\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
