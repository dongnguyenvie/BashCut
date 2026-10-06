import Foundation

extension JSONValue {
    /// Parses JSON text into the same value `JSONDecoder().decode(JSONValue.self, from:)` gives, many times faster:
    /// the `Decodable` path tries Bool, Int, Double and String (each failure throws) for every value, which takes
    /// ~80 ms for a 200 KB plugin answer; `JSONSerialization` reads it in a few. Numbers follow the decoder: integral
    /// values that fit in `Int` (`1`, `1.0`, `1e3`) are `.integer`, others `.number`.
    public init(parsing data: Data) throws {
        self = Self.converting(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    private static func converting(_ value: Any) -> JSONValue {
        switch value {
        case let string as String: return .string(string)
        case let number as NSNumber: return converting(number)
        case let array as [Any]: return .array(array.map(converting))
        case let object as [String: Any]: return .object(object.mapValues(converting))
        default: return .null
        }
    }

    private static func converting(_ number: NSNumber) -> JSONValue {
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
        switch UInt8(bitPattern: number.objCType.pointee) {
        case UInt8(ascii: "d"), UInt8(ascii: "f"):
            let value = number.doubleValue
            if value.rounded() == value, value >= -9_223_372_036_854_775_808, value < 9_223_372_036_854_775_808 {
                return .integer(Int(value))
            }
            return .number(value)
        case UInt8(ascii: "Q"), UInt8(ascii: "L"), UInt8(ascii: "I"):
            let value = number.uint64Value
            return value <= UInt64(Int.max) ? .integer(Int(value)) : .number(number.doubleValue)
        default:
            return .integer(number.intValue)
        }
    }
}
