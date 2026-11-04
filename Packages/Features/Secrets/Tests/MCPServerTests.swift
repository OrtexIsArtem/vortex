import Foundation
import Network
import Testing

@testable import FeatureSecrets

struct MCPServerTests {
  let token = "test-token-1234"

  func makeServer(port: Int = 47823) -> (MCPServer, AsyncStream<MCPEvent>) {
    let (stream, continuation) = AsyncStream.makeStream(of: MCPEvent.self)
    return (MCPServer(port: port, token: token, events: continuation), stream)
  }

  func post(_ message: JSONValue, session: String? = nil, headers: [String: String] = [:]) -> HTTPRequest {
    var all = ["host": "127.0.0.1:47823", "authorization": "Bearer \(token)", "content-type": "application/json"]
    if let session { all["mcp-session-id"] = session }
    all.merge(headers) { $1 }
    return HTTPRequest(method: "POST", path: "/mcp", headers: all, body: message.data)
  }

  func json(_ response: HTTPResponse) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: response.body)
  }

  let initialize: JSONValue = [
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": ["protocolVersion": "2025-06-18", "clientInfo": ["name": "claude-code", "version": "2.0"], "capabilities": [:]],
  ]

  @Test
  func requestsWithoutTheTokenOrFromAWebPageAreRefused() async {
    let (server, _) = makeServer()
    let ping: JSONValue = ["jsonrpc": "2.0", "id": 1, "method": "ping"]
    #expect(await server.handle(post(ping, headers: ["authorization": "Bearer wrong-token-123"])).status == 401)
    #expect(await server.handle(post(ping, headers: ["authorization": ""])).status == 401)
    #expect(await server.handle(post(ping, headers: ["origin": "https://evil.example"])).status == 403)
    // A site that resolves to this Mac still sends its own name.
    #expect(await server.handle(post(ping, headers: ["host": "evil.example:47823"])).status == 403)
    #expect(await server.handle(post(initialize, headers: ["origin": "http://localhost:6274"])).status == 200)
    var get = post(ping)
    get.method = "GET"
    #expect(await server.handle(get).status == 405)
  }

  @Test
  func initializeStartsASessionAndAnUnknownOneIsTakenAsNew() async throws {
    let (server, events) = makeServer()
    let response = await server.handle(post(initialize))
    #expect(response.status == 200)
    let session = try #require(response.headers["Mcp-Session-Id"])
    #expect(try json(response)["result"]?["protocolVersion"] == "2025-06-18")
    #expect(try json(response)["result"]?["capabilities"]?["tools"] == [:])
    var iterator = events.makeAsyncIterator()
    #expect(await iterator.next() == .sessionStarted(MCPSession(id: session, client: "Claude Code")))

    let initialized: JSONValue = ["jsonrpc": "2.0", "method": "notifications/initialized"]
    #expect(await server.handle(post(initialized, session: session)).status == 202)
    let list: JSONValue = ["jsonrpc": "2.0", "id": 2, "method": "tools/list"]
    #expect(await server.handle(post(list)).status == 400)
    // Claude Code keeps using a session Vortex no longer knows, such as after a restart: it goes on as a new one.
    #expect(await server.handle(post(list, session: "from-before")).status == 200)
    #expect(await iterator.next() == .sessionStarted(MCPSession(id: "from-before", client: "Claude Code")))
    let tools = try json(await server.handle(post(list, session: session)))["result"]?["tools"]
    guard case let .array(items)? = tools else {
      Issue.record("No tools")
      return
    }
    #expect(items.compactMap { $0["name"]?.string } == ["keys", "run"])

    var end = post(list, session: session)
    end.method = "DELETE"
    #expect(await server.handle(end).status == 200)
    #expect(await iterator.next() == .sessionEnded(session))
    #expect(await server.handle(end).status == 404)
  }

  @Test
  func aRequestOfRevision20260728GetsWhatAnOlderServerAnswers() async throws {
    // A client of that revision tries it first, with no session, and goes back to `initialize` on a 400 that holds
    // none of the revision's own error codes (-32020 to -32022).
    let (server, _) = makeServer()
    let discover: JSONValue = ["jsonrpc": "2.0", "id": 1, "method": "server/discover", "params": [:]]
    let response = await server.handle(post(discover, headers: ["mcp-protocol-version": "2026-07-28", "mcp-method": "server/discover"]))
    #expect(response.status == 400)
    #expect(try json(response)["error"]?["code"] == -32600)
  }

  @Test
  func sessionsPastTheLimitEndTheLeastRecentlyUsedFirst() async throws {
    let (server, events) = makeServer()
    var first: String?
    for _ in 0...MCPServer.maxSessions {
      let session = await server.handle(post(initialize)).headers["Mcp-Session-Id"]
      if first == nil { first = session }
    }
    var ended: [String] = []
    var iterator = events.makeAsyncIterator()
    for _ in 0..<(MCPServer.maxSessions + 2) {
      if case let .sessionEnded(id)? = await iterator.next() { ended.append(id) }
    }
    #expect(ended == [try #require(first)])
  }

  @Test
  func aCancelledRequestCancelsItsCall() async throws {
    let (server, events) = makeServer()
    let session = try #require(await server.handle(post(initialize)).headers["Mcp-Session-Id"])
    let call: JSONValue = [
      "jsonrpc": "2.0", "id": "req-9", "method": "tools/call",
      "params": ["name": "run", "arguments": ["command": "sleep 100"]],
    ]
    async let answer = server.handle(post(call, session: session))
    var iterator = events.makeAsyncIterator()
    _ = await iterator.next()
    guard case let .call(received)? = await iterator.next() else {
      Issue.record("No call")
      return
    }
    let cancel: JSONValue = ["jsonrpc": "2.0", "method": "notifications/cancelled", "params": ["requestId": "req-9"]]
    #expect(await server.handle(post(cancel, session: session)).status == 202)
    #expect(await iterator.next() == .cancelled(received.id))
    await server.reply(to: received.id, with: MCPToolResult(text: "Cancelled.", isError: true))
    #expect(try json(await answer)["result"]?["isError"] == true)
  }

  @Test
  func aToolCallWaitsForTheFeaturesAnswer() async throws {
    let (server, events) = makeServer()
    let session = try #require(await server.handle(post(initialize)).headers["Mcp-Session-Id"])
    let call: JSONValue = [
      "jsonrpc": "2.0",
      "id": 7,
      "method": "tools/call",
      "params": ["name": "run", "arguments": ["command": "echo {{db}}"]],
    ]
    async let answer = server.handle(post(call, session: session))
    var iterator = events.makeAsyncIterator()
    _ = await iterator.next()
    guard case let .call(received)? = await iterator.next() else {
      Issue.record("No call")
      return
    }
    #expect(received.tool == .run)
    #expect(received.client == "Claude Code")
    #expect(received.arguments["command"] == "echo {{db}}")
    await server.reply(to: received.id, with: MCPToolResult(text: "exit code 0\n{{db}}", isError: false))
    let result = try json(await answer)
    #expect(result["id"] == 7)
    #expect(result["result"]?["isError"] == false)
    #expect(result["result"]?["content"] == [["type": "text", "text": "exit code 0\n{{db}}"]])
  }

  /// A port in use reads as taken; any other error of the system's only as unexpected, its words left to the log.
  @Test
  func aPortInUseIsTakenAndAnyOtherErrorIsUnexpected() {
    #expect(MCPServer.failure(NWError.posix(.EADDRINUSE)) == .portTaken)
    #expect(MCPServer.failure(NWError.posix(.EACCES)) == .other)
    #expect(MCPServer.failure(NWError.posix(.EADDRNOTAVAIL)) == .other)
    #expect(MCPServer.failure(CocoaError(.featureUnsupported)) == .other)
  }

  @Test
  func requestsAreReadWholeAlsoChunked() {
    let plain = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:1\r\nContent-Length: 2\r\n\r\n{}"
    #expect(HTTPRequest.parse(Data(plain.utf8)) == .complete(HTTPRequest(
      method: "POST",
      path: "/mcp",
      headers: ["host": "127.0.0.1:1", "content-length": "2"],
      body: Data("{}".utf8)
    )))
    #expect(HTTPRequest.parse(Data(plain.dropLast().utf8)) == .incomplete)
    let chunked = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n2\r\n{}\r\n0\r\n\r\n"
    guard case let .complete(request) = HTTPRequest.parse(Data(chunked.utf8)) else {
      Issue.record("Not read")
      return
    }
    #expect(request.body == Data("{}".utf8))
    #expect(HTTPRequest.parse(Data("nonsense\r\n\r\n".utf8)) == .invalid)
    // A chunk size made to overflow is refused, not a crash.
    let huge = "POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nA\r\n7fffffffffffffff\r\n"
    #expect(HTTPRequest.parse(Data(huge.utf8)) == .invalid)
    let head = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1:1\r\nContent-Length: 999\r\n\r\npartial"
    guard case let .complete(parsed) = HTTPRequest.head(Data(head.utf8)) else {
      Issue.record("No head")
      return
    }
    #expect(parsed.headers["content-length"] == "999")
    #expect(HTTPRequest.parse(Data(head.utf8)) == .incomplete)
  }

  @Test
  func itAnswersOnThisMacsLoopback() async throws {
    let port = 47_100 + Int.random(in: 0..<800)
    let (server, events) = makeServer(port: port)
    await server.listen()
    var iterator = events.makeAsyncIterator()
    guard case .listening? = await iterator.next() else {
      Issue.record("Not listening")
      return
    }
    var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/mcp")))
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = initialize.data
    let (data, response) = try await URLSession.shared.data(for: request)
    let http = try #require(response as? HTTPURLResponse)
    #expect(http.statusCode == 200)
    #expect(http.value(forHTTPHeaderField: "Mcp-Session-Id") != nil)
    #expect(try JSONDecoder().decode(JSONValue.self, from: data)["result"]?["serverInfo"]?["name"] == "vortex")
    // Without the token it is refused on the headers, before the body it promises has come.
    var stranger = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/mcp")))
    stranger.httpMethod = "POST"
    stranger.httpBody = Data(repeating: 65, count: 300_000)
    let (_, refused) = try await URLSession.shared.data(for: stranger)
    #expect((refused as? HTTPURLResponse)?.statusCode == 401)
    await server.stop()
  }
}
