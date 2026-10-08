import Foundation
import VortexPlatform

/// A command Claude wrote, with {{name}} wherever a key's value goes.
struct KeyCommand: Equatable, Sendable {
  /// The names written, lowercased, in the order they first appear.
  let names: [String]
  /// What the shell runs: each {{name}} became `${VORTEX_KEY_n}`, so no value is ever part of the command's text.
  let shellCommand: String

  static var placeholder: Regex<(Substring, Substring)> { /\{\{\s*([A-Za-z0-9][A-Za-z0-9._\-]*)\s*\}\}/ }

  init(_ command: String) {
    var names: [String] = []
    var shellCommand = ""
    var rest = command[...]
    while let match = rest.firstMatch(of: Self.placeholder) {
      shellCommand += rest[..<match.range.lowerBound]
      let name = match.output.1.lowercased()
      if !names.contains(name) { names.append(name) }
      shellCommand += "${\(Self.variable(at: names.firstIndex(of: name) ?? 0))}"
      rest = rest[match.range.upperBound...]
    }
    self.names = names
    self.shellCommand = shellCommand + rest
  }

  /// The shell variable holding the value of the `index`-th name.
  static func variable(at index: Int) -> String {
    "VORTEX_KEY_\(index + 1)"
  }

  /// Each name's variable set to its value; `values` by lowercased name.
  func environment(values: [String: String]) -> [String: String] {
    var environment: [String: String] = [:]
    for (index, name) in names.enumerated() {
      environment[Self.variable(at: index)] = values[name]
    }
    return environment
  }

  /// `text` as Claude may see it: each value written as its {{name}}, also as tools print it by accident: URL-encoded
  /// the usual ways, in base64, escaped in JSON, and a connection URL's password, alone or as `user:password` in base64
  /// (an HTTP Basic header). `values` by name; values under 4 characters are left as they are.
  static func masked(_ text: String, values: [String: String]) -> String {
    var forms: [(secret: String, name: String)] = []
    for (name, value) in values {
      var secrets = [value]
      if let components = URLComponents(string: value) {
        secrets += [components.password, components.percentEncodedPassword].compactMap { $0 }
        if let user = components.user, let password = components.password {
          secrets.append("\(user):\(password)")
        }
      }
      for secret in secrets {
        forms += encodings(of: secret).map { (secret: $0, name: name) }
      }
    }
    var masked = text
    // Longer first, so a value holding another is replaced whole.
    for form in forms.sorted(by: { $0.secret.count > $1.secret.count }) where form.secret.count >= 4 {
      masked = masked.replacingOccurrences(of: form.secret, with: "{{\(form.name)}}")
    }
    return masked
  }

  /// `secret` and the ways it gets written: URL-encoded (every sign, RFC 3986, query, password), base64 with and
  /// without padding, escaped in JSON (plainly, with `\/`, and Go's way with `\u0026`, `\u003c`, `\u003e`).
  static func encodings(of secret: String) -> Set<String> {
    var forms: Set<String> = [secret]
    let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    for allowed in [CharacterSet.alphanumerics, unreserved, .urlQueryAllowed, .urlPasswordAllowed] {
      if let encoded = secret.addingPercentEncoding(withAllowedCharacters: allowed) { forms.insert(encoded) }
    }
    let base64 = Data(secret.utf8).base64EncodedString()
    forms.insert(base64)
    forms.insert(base64.trimmingCharacters(in: CharacterSet(charactersIn: "=")))
    let json = secret.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let goJSON = json.replacingOccurrences(of: "&", with: "\\u0026")
      .replacingOccurrences(of: "<", with: "\\u003c")
      .replacingOccurrences(of: ">", with: "\\u003e")
    for escaped in [json, goJSON] {
      forms.insert(escaped)
      forms.insert(escaped.replacingOccurrences(of: "/", with: "\\/"))
    }
    return forms
  }

  /// What Claude gets back: how the command ended, then its output and its errors, the values taken out and each
  /// part cut to `limit` characters.
  static func report(_ output: CommandClient.Output, values: [String: String], timeout: Int, limit: Int = 30_000) -> String {
    // An output cut at the client's limit may end in part of a value, which can't be matched: that much goes too.
    let longest = values.values.map(\.utf8.count).max() ?? 0
    func text(_ data: Data) -> String {
      let kept = data.count >= CommandClient.outputLimit ? data.dropLast(longest * 3) : data
      return String(decoding: kept, as: UTF8.self)
    }
    let stdout = cut(masked(text(output.stdout), values: values), to: limit)
    let stderr = cut(masked(text(output.stderr), values: values), to: limit)
    var parts = [output.timedOut ? "stopped after \(timeout) s, its time limit" : "exit code \(output.exitCode)"]
    if !stdout.isEmpty { parts.append(stdout) }
    if !stderr.isEmpty { parts.append("--- stderr ---\n" + stderr) }
    if stdout.isEmpty, stderr.isEmpty { parts.append("(no output)") }
    return parts.joined(separator: "\n")
  }

  /// The start and the end of `text` when it is longer than `limit`, with how much was left out between them.
  static func cut(_ text: String, to limit: Int) -> String {
    guard text.count > limit else { return text }
    let head = text.prefix(limit * 3 / 4)
    let tail = text.suffix(limit / 4)
    return "\(head)\n… \(text.count - head.count - tail.count) characters left out …\n\(tail)"
  }
}
