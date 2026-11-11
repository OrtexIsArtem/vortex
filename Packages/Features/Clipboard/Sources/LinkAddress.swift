import Foundation

/// A link's address as a person reads it, as Safari's address bar shows it: `/привіт`, not `/%D0%BF…`.
enum LinkAddress {
  /// Decodes the percent-escapes that spell letters beyond ASCII (Cyrillic, accents, emoji). Escapes of ASCII
  /// characters stay, as writing them plainly would change what the address says (a space, a slash inside a name, a
  /// percent sign); so do escapes that don't spell a character, and characters that are invisible or turn the text's
  /// direction, which would hide what the address is. Only for showing: the link itself is never changed.
  static func readable(_ address: String) -> String {
    var result = ""
    // Escapes of bytes beyond ASCII next to each other, with their text, waiting to be read as UTF-8.
    var run: [(byte: UInt8, text: Substring)] = []
    var index = address.startIndex
    while index < address.endIndex {
      if let (byte, end) = escapedByte(at: index, in: address), byte >= 0x80 {
        run.append((byte, address[index..<end]))
        index = end
      } else {
        result += decoded(run)
        run = []
        result.append(address[index])
        index = address.index(after: index)
      }
    }
    return result + decoded(run)
  }

  /// The byte `%XX` at `index` stands for, and where it ends; nil when no escape starts there.
  private static func escapedByte(at index: String.Index, in text: String) -> (UInt8, String.Index)? {
    guard text[index] == "%" else { return nil }
    let digits = text[text.index(after: index)...].prefix(2)
    guard digits.count == 2, digits.allSatisfy(\.isHexDigit), let byte = UInt8(digits, radix: 16) else { return nil }
    return (byte, digits.endIndex)
  }

  /// A run of escaped bytes read as UTF-8: each character that reads as itself is shown so; any other byte keeps the
  /// escape it was written with.
  private static func decoded(_ run: [(byte: UInt8, text: Substring)]) -> String {
    var result = ""
    var index = 0
    while index < run.count {
      let length = switch run[index].byte {
      case 0xC2...0xDF: 2
      case 0xE0...0xEF: 3
      case 0xF0...0xF4: 4
      default: 0
      }
      if length > 0, index + length <= run.count,
         let character = String(bytes: run[index..<index + length].map(\.byte), encoding: .utf8),
         character.unicodeScalars.allSatisfy(isShown) {
        result += character
        index += length
      } else {
        result += run[index].text
        index += 1
      }
    }
    return result
  }

  private static func isShown(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .control, .format, .spaceSeparator, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned, .surrogate:
      false
    default:
      true
    }
  }
}
