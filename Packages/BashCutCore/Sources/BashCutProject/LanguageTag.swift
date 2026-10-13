import Foundation

extension Project {
    /// Whether `tag` is shaped like a BCP 47 language tag a project's `contentLanguage` takes: a 2–3 letter language,
    /// then subtags of 1–8 ASCII letters or digits after hyphens (`vi`, `en-US`, `zh-Hant-TW`).
    public static func isLanguageTag(_ tag: String) -> Bool {
        let parts = tag.split(separator: "-", omittingEmptySubsequences: false)
        return parts.enumerated().allSatisfy { index, part in
            guard part.allSatisfy(\.isASCII) else { return false }
            return index == 0
                ? (2...3).contains(part.count) && part.allSatisfy(\.isLetter)
                : (1...8).contains(part.count) && part.allSatisfy { $0.isLetter || $0.isNumber }
        }
    }
}
