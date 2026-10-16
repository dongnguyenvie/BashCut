import BashCutProject
import Foundation

/// The batch's own messages in the user's language. The pipeline checks and the runner word them in English
/// (`BatchMessages`), which agents read in CLI and MCP results; the batch window and its queue show them through here.
/// Each key's `%@` are the parts that vary (themselves translated when they are batch messages too, as the failure
/// inside "Step 2 (export): …").
public enum BatchMessage {
    /// Most specific first, then the parameter check every step command runs first.
    public static let patterns: [String] = BatchMessages.all + ["Missing %@"]

    private static let expressions: [(key: String, regex: NSRegularExpression)] = patterns.map { key in
        let parts = key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:))
        let pattern = "^" + parts.joined(separator: "(.+?)") + "$"
        // swiftlint:disable:next force_try
        return (key, try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]))
    }

    /// The pattern `message` fits and its varying parts; nil for a message the batch does not word itself.
    public static func match(_ message: String) -> (key: String, arguments: [String])? {
        let range = NSRange(message.startIndex..., in: message)
        for (key, regex) in expressions {
            guard let found = regex.firstMatch(in: message, range: range) else { continue }
            let arguments = (1..<found.numberOfRanges).compactMap { Range(found.range(at: $0), in: message) }
                .map { String(message[$0]) }
            return (key, arguments)
        }
        return nil
    }

    /// `message` in the app's language; unchanged when it is not a batch message or has no translation.
    public static func localized(_ message: String, bundle: Bundle = .main) -> String {
        guard let (key, arguments) = match(message) else { return message }
        let format = bundle.localizedString(forKey: key, value: key, table: nil)
        let translated: [any CVarArg] = arguments.map { localized($0, bundle: bundle) as NSString }
        return String(format: format, arguments: translated)
    }
}
