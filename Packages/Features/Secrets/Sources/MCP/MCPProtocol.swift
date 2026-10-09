import ComposableArchitecture
import Foundation

/// A client that started an MCP session, such as Claude Code; allowing keys counts per session.
struct MCPSession: Equatable, Sendable {
  let id: String
  /// As the user reads it: «Claude Code».
  let client: String
}

/// A tool call waiting for the feature's answer.
struct MCPCall: Identifiable, Equatable, Sendable {
  let id: UUID
  let session: String
  let client: String
  let tool: MCPProtocol.Tool
  let arguments: JSONValue
}

struct MCPToolResult: Equatable, Sendable {
  var text: String
  var isError: Bool
}

/// What the server reports to the feature.
@CasePathable
enum MCPEvent: Equatable, Sendable {
  case listening(port: Int)
  /// It could not listen, such as when another app has the port.
  case failed(String)
  case sessionStarted(MCPSession)
  case sessionEnded(String)
  case call(MCPCall)
  /// The client gave the call up: by `notifications/cancelled`, or by closing its connection.
  case cancelled(MCPCall.ID)
}

/// The server's side of MCP apart from the network: what it says to each message. Tool calls are the feature's.
enum MCPProtocol {
  enum Tool: String, Sendable {
    case keys
    case run
  }

  /// The versions it speaks, newest first.
  static let versions = ["2025-11-25", "2025-06-18", "2025-03-26"]
  static let serverName = "vortex"

  static let instructions = """
    Vortex keeps the user's secrets: database URLs, API tokens, passwords. `keys` lists them by name; `run` runs a \
    shell command with {{name}} where a key's value goes. You never see a value: Vortex puts it in and takes it out of \
    the output. Ask the user before changing data, or anything else, with a key.
    """

  /// The answer to `initialize`: the client's version when it is one of these, else the newest.
  static func initializeResult(requestedVersion: String?) -> JSONValue {
    let version = requestedVersion.flatMap { versions.contains($0) ? $0 : nil } ?? versions[0]
    return [
      "protocolVersion": .string(version),
      "capabilities": ["tools": [:]],
      "serverInfo": ["name": .string(serverName), "title": "Vortex", "version": "1.0"],
      "instructions": .string(instructions),
    ]
  }

  static let toolList: JSONValue = [
    "tools": [
      [
        "name": "keys",
        "title": "Keys in Vortex",
        "description": """
          Lists the keys the user stored in Vortex: each one's name, what it is (told by its value) and the user's note. \
          Values are never shown. Use a key in `run` by writing {{name}}.
          """,
        "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
        "annotations": ["readOnlyHint": true],
      ],
      [
        "name": "run",
        "title": "Run a command with keys",
        "description": """
          Runs a shell command in the user's shell, with the environment their terminal has (psql, mysql, mongosh, redis-cli, \
          curl, gh, aws…), with stored keys put in where {{key-name}} is written. A value goes in as a shell variable: \
          write the placeholder inside double quotes, never single ones, e.g. psql "{{prod-db}}" -c 'select count(*) \
          from users' or curl -H "Authorization: Bearer {{github}}" https://api.github.com/user. The output comes back \
          with every value replaced by its {{name}}. The first use of a key in a session waits until the user allows it \
          in Vortex. The command gets no input and is stopped after `timeout` seconds. Ask the user before changing data.
          """,
        "inputSchema": [
          "type": "object",
          "properties": [
            "command": ["type": "string", "description": "The shell command, with {{key-name}} where a key's value goes."],
            "cwd": [
              "type": "string",
              "description": "Absolute path of the folder to run in, usually the project's; the home folder when left out.",
            ],
            "timeout": [
              "type": "integer",
              "minimum": 1,
              "maximum": 180,
              "description": "Seconds before the command is stopped, at most 180; 60 when left out.",
            ],
          ],
          "required": ["command"],
          "additionalProperties": false,
        ],
        "annotations": ["destructiveHint": true, "openWorldHint": true],
      ],
    ],
  ]

  static func toolResult(_ result: MCPToolResult) -> JSONValue {
    ["content": [["type": "text", "text": .string(result.text)]], "isError": .bool(result.isError)]
  }

  static func response(id: JSONValue, result: JSONValue) -> JSONValue {
    ["jsonrpc": "2.0", "id": id, "result": result]
  }

  static func error(id: JSONValue?, code: Int, message: String) -> JSONValue {
    ["jsonrpc": "2.0", "id": id ?? .null, "error": ["code": .number(Double(code)), "message": .string(message)]]
  }

  /// The client's name as the user knows it: Claude Code for `claude-code`.
  static func clientTitle(_ name: String?) -> String {
    switch name {
    case "claude-code": "Claude Code"
    case "claude-ai", "claude-desktop": "Claude"
    case let name? where !name.isEmpty: name
    default: "Claude"
    }
  }
}
