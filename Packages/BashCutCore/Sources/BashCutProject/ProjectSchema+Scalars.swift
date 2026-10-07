import Foundation

/// Scalar schema builders.
extension ProjectSchema {
    static func integer(_ summary: String, minimum: Int? = nil, maximum: Int? = nil) -> JSONValue {
        var value: [String: JSONValue] = ["type": .string("integer"), "description": .string(summary)]
        if let minimum { value["minimum"] = .integer(minimum) }
        if let maximum { value["maximum"] = .integer(maximum) }
        return .object(value)
    }

    static func number(_ summary: String, _ range: ClosedRange<Double>) -> JSONValue {
        .object([
            "type": .string("number"), "description": .string(summary),
            "minimum": bound(range.lowerBound), "maximum": bound(range.upperBound),
        ])
    }

    private static func bound(_ value: Double) -> JSONValue {
        value.rounded() == value && abs(value) < 1e15 ? .integer(Int(value)) : .number(value)
    }

    static func boolean(_ summary: String) -> JSONValue {
        .object(["type": .string("boolean"), "description": .string(summary)])
    }
}
