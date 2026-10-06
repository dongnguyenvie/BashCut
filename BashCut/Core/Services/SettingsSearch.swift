import Foundation

/// Matching for the Settings search box: every word of the query must appear in the setting's terms (its English
/// title, the shown translation, description and keywords), ignoring case and accents.
public enum SettingsSearch {
    public static func matches(_ query: String, _ terms: [String]) -> Bool {
        let words = fold(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = fold(terms.joined(separator: " "))
        return words.allSatisfy { text.contains($0) }
    }

    /// Lowercased without accents; Vietnamese đ is a letter of its own, so it becomes d by hand ("da gui" finds
    /// "đã gửi").
    public static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "d")
    }
}
