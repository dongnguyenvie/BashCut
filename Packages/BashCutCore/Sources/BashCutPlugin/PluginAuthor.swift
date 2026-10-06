import BashCutProject
import Foundation

/// The person or team who wrote a plugin: `{"name": "…", "url": "https://…"}`, the url optional.
public struct PluginAuthor: Codable, Sendable, Equatable {
    public static let maximumName = 80
    public static let maximumURL = 512

    public let name: String
    /// A web page about the author (a GitHub profile, a site); http or https.
    public let url: String?

    public init(name: String, url: String? = nil) {
        self.name = name
        self.url = url
    }

    /// The url when it is a web link the app can open.
    public var link: URL? {
        guard let url, let link = URL(string: url), ["http", "https"].contains(link.scheme?.lowercased() ?? ""),
            link.host()?.isEmpty == false
        else { return nil }
        return link
    }

    public func validate() throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed == name, name.count <= Self.maximumName, !name.contains(where: \.isNewline) else {
            throw PluginError.invalid("author.name must be 1–\(Self.maximumName) characters on one line")
        }
        if let url, url.count > Self.maximumURL || link == nil {
            throw PluginError.invalid("author.url must be an http or https link of at most \(Self.maximumURL) characters")
        }
    }

    public var json: JSONValue { .object(["name": .string(name), "url": url.map(JSONValue.string) ?? .null]) }
}
