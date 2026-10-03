import Foundation

/// A lossless JSON tree keeps fields from newer editors, including nested interop metadata.
public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case integer(Int)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var object: [String: JSONValue] {
        if case .object(let v) = self { return v }
        return [:]
    }
    public var array: [JSONValue] {
        if case .array(let v) = self { return v }
        return []
    }
    public var string: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    public var int: Int? {
        if case .integer(let v) = self { return v }
        return nil
    }
    public var bool: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
    public var double: Double? {
        switch self {
        case .integer(let v): return Double(v)
        case .number(let v): return v
        default: return nil
        }
    }
}

public protocol JSONObject: Codable, Sendable, Equatable {
    var fields: [String: JSONValue] { get set }
    init(fields: [String: JSONValue])
}

extension JSONObject {
    public init(from decoder: any Decoder) throws {
        self.init(fields: try decoder.singleValueContainer().decode([String: JSONValue].self))
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }
    public subscript(key: String) -> JSONValue? {
        get { fields[key] }
        set { fields[key] = newValue }
    }
}
