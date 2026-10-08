import Foundation

/// An HTTP/1.1 request, as much of it as the MCP server reads.
struct HTTPRequest: Equatable, Sendable {
  var method: String
  var path: String
  /// Names lowercased.
  var headers: [String: String]
  var body: Data

  /// Bodies past this are refused.
  static let maxBody = 1 << 20
  /// The request line and headers past this are refused.
  static let maxHead = 16 * 1024

  enum Parsed: Equatable {
    case incomplete
    case invalid
    case complete(HTTPRequest)
  }

  /// The request line and headers, once they have all come: what is checked before any of the body is read.
  struct Head: Equatable {
    var method: String
    var path: String
    /// Names lowercased.
    var headers: [String: String]
    /// Where the body starts.
    var end: Int
  }

  enum ParsedHead: Equatable {
    case incomplete
    case invalid
    case complete(Head)
  }

  static func head(_ data: Data) -> ParsedHead {
    let bytes = [UInt8](data.prefix(maxHead + 4))
    guard let end = bytes.firstRange(of: [13, 10, 13, 10]) else {
      return data.count > maxHead ? .invalid : .incomplete
    }
    guard let text = String(bytes: bytes[..<end.lowerBound], encoding: .utf8) else { return .invalid }
    var lines = text.components(separatedBy: "\r\n")
    let start = lines.removeFirst().split(separator: " ")
    guard start.count == 3, start[2].hasPrefix("HTTP/1.") else { return .invalid }
    var headers: [String: String] = [:]
    for line in lines {
      guard let colon = line.firstIndex(of: ":") else { return .invalid }
      headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...]
        .trimmingCharacters(in: .whitespaces)
    }
    return .complete(Head(method: String(start[0]), path: String(start[1]), headers: headers, end: end.upperBound))
  }

  /// The request at the start of `data`, once all of it has come.
  static func parse(_ data: Data) -> Parsed {
    let head: Head
    switch Self.head(data) {
    case .incomplete: return .incomplete
    case .invalid: return .invalid
    case let .complete(complete): head = complete
    }
    let headers = head.headers
    let rest = Array([UInt8](data)[head.end...])
    let body: [UInt8]
    if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
      switch dechunked(rest) {
      case .incomplete: return .incomplete
      case .invalid: return .invalid
      case let .complete(dechunked): body = dechunked
      }
    } else {
      guard let length = Int(headers["content-length"] ?? "0"), length >= 0, length <= maxBody else { return .invalid }
      guard rest.count >= length else { return .incomplete }
      body = Array(rest[..<length])
    }
    return .complete(HTTPRequest(method: head.method, path: head.path, headers: headers, body: Data(body)))
  }

  private enum Dechunked {
    case incomplete
    case invalid
    case complete([UInt8])
  }

  /// A chunked body joined; trailers are skipped.
  private static func dechunked(_ bytes: [UInt8]) -> Dechunked {
    var body: [UInt8] = []
    var index = 0
    while true {
      guard let lineEnd = bytes[index...].firstRange(of: [13, 10]) else { return .incomplete }
      let sizeText = String(decoding: bytes[index..<lineEnd.lowerBound], as: UTF8.self)
        .split(separator: ";").first.map(String.init) ?? ""
      // Bounded before adding: a huge size must not overflow.
      guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16), size >= 0, size <= maxBody,
            body.count + size <= maxBody
      else { return .invalid }
      index = lineEnd.upperBound
      if size == 0 { return .complete(body) }
      guard bytes.count >= index + size + 2 else { return .incomplete }
      body += bytes[index..<index + size]
      index += size + 2
    }
  }
}

/// What the MCP server sends back; the connection closes after it.
struct HTTPResponse: Equatable, Sendable {
  var status: Int
  var headers: [String: String] = [:]
  var body = Data()

  static func json(_ value: JSONValue, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
    HTTPResponse(status: status, headers: headers.merging(["Content-Type": "application/json"]) { $1 }, body: value.data)
  }

  var serialized: Data {
    var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
    for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
      head += "\(name): \(value)\r\n"
    }
    head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
    return Data(head.utf8) + body
  }

  private static func reason(_ status: Int) -> String {
    switch status {
    case 200: "OK"
    case 202: "Accepted"
    case 400: "Bad Request"
    case 401: "Unauthorized"
    case 403: "Forbidden"
    case 404: "Not Found"
    case 405: "Method Not Allowed"
    default: "Error"
    }
  }
}
