import Foundation

extension String {
    /// Lowercased, without accents or width variants, and Vietnamese đ as d ("Đã gửi" → "da gui"), so searches and
    /// slugs match text typed without diacritics. đ is a letter of its own, not d with a diacritic, so it is mapped
    /// by hand.
    public var searchFolded: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "d").lowercased()
    }
}
