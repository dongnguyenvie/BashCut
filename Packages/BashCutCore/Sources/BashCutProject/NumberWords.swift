import Foundation

/// Numbers as they are said, so a script that spells a number out ("năm trăm hai mươi tám") matches a transcript
/// that writes it in digits ("528"), as speech recognizers do. Vietnamese and English; other languages keep digits.
public enum NumberWords {
    /// The language a script is in, as far as spelling numbers goes: Vietnamese when it has a letter only Vietnamese
    /// uses, else English.
    public static func language(of text: String) -> String {
        let vietnamese = Set("ăâđêôơưàảãáạằẳẵắặầẩẫấậèẻẽéẹềểễếệìỉĩíịòỏõóọồổỗốộờởỡớợùủũúụừửữứựỳỷỹýỵ")
        return text.lowercased().contains(where: { vietnamese.contains($0) }) ? "vi" : "en"
    }

    /// Spoken variants written as one form, so either spelling of a Vietnamese number matches
    /// (hai mươi mốt / một, bốn mươi tư / bốn, mười lăm / năm, lẻ / linh, nghìn / ngàn).
    public static let variants: [String: String] = ["mốt": "một", "tư": "bốn", "lăm": "năm", "linh": "lẻ", "ngàn": "nghìn"]

    /// A numeral token ("528", "1.000", "7,5", "50%") as words, or nil when it is not a number.
    public static func spelled(_ token: String, language: String) -> [String]? {
        var text = token.trimmingCharacters(in: .punctuationCharacters.union(.symbols).union(.whitespaces))
        let percent = token.hasSuffix("%")
        guard !text.isEmpty, text.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }), text.first?.isNumber == true
        else { return nil }
        var fraction: String?
        // 1.000 / 1,000 group thousands; 7,5 (vi) or 7.5 (en) has a fraction.
        let groups = text.split(whereSeparator: { $0 == "." || $0 == "," }).map(String.init)
        if groups.count > 1, groups.dropFirst().allSatisfy({ $0.count == 3 }) {
            text = groups.joined()
        } else if groups.count == 2 {
            text = groups[0]
            fraction = groups[1]
        } else if groups.count > 2 {
            return nil
        }
        guard let whole = Int(text), whole < 1_000_000_000_000 else { return nil }
        var words = language == "vi" ? vietnamese(whole) : english(whole)
        if let fraction {
            words += [language == "vi" ? "phẩy" : "point"]
            words += fraction.compactMap { Int(String($0)) }.flatMap { language == "vi" ? vietnamese($0) : english($0) }
        }
        if percent { words += language == "vi" ? ["phần", "trăm"] : ["percent"] }
        return words
    }

    static let vietnameseDigits = ["không", "một", "hai", "ba", "bốn", "năm", "sáu", "bảy", "tám", "chín"]

    static func vietnamese(_ number: Int) -> [String] {
        guard number > 0 else { return ["không"] }
        let scales: [(Int, String)] = [(1_000_000_000, "tỷ"), (1_000_000, "triệu"), (1_000, "nghìn")]
        var words: [String] = []
        var rest = number
        var started = false
        for (scale, name) in scales where rest >= scale {
            words += vietnameseHundreds(rest / scale, full: started) + [name]
            rest %= scale
            started = true
        }
        if rest > 0 { words += vietnameseHundreds(rest, full: started) }
        return words
    }

    /// 1–999; `full`: inside a larger number, so 5 reads "không trăm lẻ năm".
    static func vietnameseHundreds(_ number: Int, full: Bool) -> [String] {
        let hundreds = number / 100, tens = number / 10 % 10, units = number % 10
        var words: [String] = []
        if hundreds > 0 || full { words += [vietnameseDigits[hundreds], "trăm"] }
        if tens == 0 {
            if units > 0 { words += (words.isEmpty ? [] : ["lẻ"]) + [vietnameseDigits[units]] }
        } else {
            words += tens == 1 ? ["mười"] : [vietnameseDigits[tens], "mươi"]
            if units > 0 { words.append(vietnameseDigits[units]) }
        }
        return words
    }

    static let englishSmall = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
    ]
    static let englishTens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]

    static func english(_ number: Int) -> [String] {
        guard number > 0 else { return ["zero"] }
        var words: [String] = []
        var rest = number
        for (scale, name) in [(1_000_000_000, "billion"), (1_000_000, "million"), (1_000, "thousand")] where rest >= scale {
            words += englishHundreds(rest / scale) + [name]
            rest %= scale
        }
        if rest > 0 { words += englishHundreds(rest) }
        return words
    }

    static func englishHundreds(_ number: Int) -> [String] {
        var words: [String] = []
        if number >= 100 { words += [englishSmall[number / 100], "hundred"] }
        let rest = number % 100
        if rest >= 20 {
            words.append(englishTens[rest / 10])
            if rest % 10 > 0 { words.append(englishSmall[rest % 10]) }
        } else if rest > 0 {
            words.append(englishSmall[rest])
        }
        return words
    }
}
