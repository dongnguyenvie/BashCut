import BashCutProject
import Foundation
import Testing

/// `JSONValue(parsing:)` must give exactly what the `Decodable` path gives (#390 bench).
@Suite("JSONValue fast parsing")
struct JSONValueParsingTests {
    @Test("Same values as JSONDecoder", arguments: [
        "1", "1.0", "-0", "1e3", "1.5", "-1.0e2", "2.5e-3", "1E2", "0", "true", "false", "null", "\"text\"",
        "9223372036854775807", "-9223372036854775808", "9223372036854775808", "100000000000000000000",
        "3.0000000000000004", "[]", "{}", "[1, \"a\", null, [true, {\"k\": 2.5}]]",
        "{\"name\": \"Xin chào 🎬\", \"nested\": {\"list\": [1, 2.0, 3.25], \"empty\": \"\"}, \"escaped\": \"a\\\"b\\\\n\"}",
    ])
    func matchesDecoder(_ text: String) throws {
        let data = Data(text.utf8)
        #expect(try JSONValue(parsing: data) == JSONDecoder().decode(JSONValue.self, from: data))
    }

    @Test("Invalid JSON throws")
    func invalid() {
        #expect(throws: (any Error).self) { try JSONValue(parsing: Data("{\"a\": ".utf8)) }
    }
}
