import Foundation

/// Any JSON: the MCP messages Claude sends and the answers to them.
enum JSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
    } else {
      self = .object(try container.decode([String: JSONValue].self))
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case let .bool(bool):
      try container.encode(bool)
    case let .number(number):
      // Whole numbers as integers, as ids are written.
      if number.rounded() == number, abs(number) < 1e15 {
        try container.encode(Int64(number))
      } else {
        try container.encode(number)
      }
    case let .string(string):
      try container.encode(string)
    case let .array(array):
      try container.encode(array)
    case let .object(object):
      try container.encode(object)
    }
  }

  subscript(key: String) -> JSONValue? {
    if case let .object(object) = self { object[key] } else { nil }
  }

  var string: String? {
    if case let .string(string) = self { string } else { nil }
  }

  var int: Int? {
    if case let .number(number) = self, number.rounded() == number, abs(number) < 1e15 { Int(number) } else { nil }
  }

  /// The compact JSON text.
  var data: Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return (try? encoder.encode(self)) ?? Data("null".utf8)
  }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
  ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
  init(stringLiteral value: String) { self = .string(value) }
  init(booleanLiteral value: Bool) { self = .bool(value) }
  init(integerLiteral value: Int) { self = .number(Double(value)) }
  init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
  init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(elements) { $1 }) }
}
