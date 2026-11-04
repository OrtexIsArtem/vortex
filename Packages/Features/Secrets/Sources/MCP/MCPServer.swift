import ComposableArchitecture
import Foundation
import Network
import os

/// The MCP server: what the feature asks of it.
@DependencyClient
struct MCPServerClient: Sendable {
  /// Serves MCP at http://127.0.0.1:`port`/mcp to clients that send `token`; what happens comes out of the stream, and
  /// ending the stream stops the server.
  var serve: @Sendable (_ port: Int, _ token: String) -> AsyncStream<MCPEvent> = { _, _ in .finished }
  /// The answer to a tool call the stream gave out.
  var reply: @Sendable (_ call: MCPCall.ID, _ result: MCPToolResult) async -> Void
}

extension MCPServerClient: DependencyKey {
  static let liveValue = MCPServerClient(
    serve: { port, token in
      AsyncStream { continuation in
        let server = MCPServer(port: port, token: token, events: continuation)
        Task { @MainActor in
          // One at a time: the one before lets go of the port first.
          await CurrentServer.server?.stop()
          CurrentServer.server = server
          await server.listen()
        }
        continuation.onTermination = { _ in
          Task { @MainActor in
            await server.stop()
            if CurrentServer.server === server { CurrentServer.server = nil }
          }
        }
      }
    },
    reply: { call, result in
      await MainActor.run { CurrentServer.server }?.reply(to: call, with: result)
    }
  )

  static let testValue = MCPServerClient()
}

extension DependencyValues {
  var mcpServer: MCPServerClient {
    get { self[MCPServerClient.self] }
    set { self[MCPServerClient.self] = newValue }
  }
}

@MainActor
private enum CurrentServer {
  static var server: MCPServer?
}

/// MCP over HTTP on this Mac's loopback only (Streamable HTTP, every answer plain JSON). A request needs the bearer
/// token, and one from a web page (an Origin or Host of another site) is refused, so a page in a browser can't reach it;
/// both are checked on the headers, before any body is read. Tool calls are handed to the feature as events and wait for
/// `reply`; a call the client cancels, or gives up on by closing the connection, is reported as cancelled.
///
/// Claude Code does not start a new session when its own is unknown, and never ends one: an unknown session id, such as
/// one from before Vortex restarted, is taken as a new session, and the least recently used sessions are let go past
/// `maxSessions`.
actor MCPServer {
  static let maxSessions = 50
  /// How long a request may take to arrive.
  static let requestTime: Duration = .seconds(15)

  private let port: Int
  private let token: String
  private let events: AsyncStream<MCPEvent>.Continuation
  private var listener: NWListener?
  private var sessions: [String: MCPSession] = [:]
  private var lastSeen: [String: ContinuousClock.Instant] = [:]
  private var calls: [MCPCall.ID: CheckedContinuation<MCPToolResult, Never>] = [:]
  /// Calls by session and the client's request id, for `notifications/cancelled`.
  private var requests: [String: MCPCall.ID] = [:]
  /// Connections whose request has not fully come yet.
  private var arriving: Set<ObjectIdentifier> = []
  private var isStopped = false
  private let queue = DispatchQueue(label: "io.github.ortexisartem.vortex.mcp")

  init(port: Int, token: String, events: AsyncStream<MCPEvent>.Continuation) {
    self.port = port
    self.token = token
    self.events = events
  }

  /// Starts listening; a port still held by the server before is tried again a few times.
  func listen(attempt: Int = 0) {
    guard !isStopped else { return }
    guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: port)), self.port > 0 else {
      // Settings keep the port in 1024–65535, so this never happens.
      logger.error("Port \(self.port, privacy: .public) is not a port")
      events.yield(.failed(.other))
      return
    }
    let parameters = NWParameters.tcp
    parameters.requiredInterfaceType = .loopback
    parameters.allowLocalEndpointReuse = true
    do {
      let listener = try NWListener(using: parameters, on: port)
      listener.stateUpdateHandler = { [weak self] state in
        Task { await self?.listenerChanged(state, attempt: attempt) }
      }
      listener.newConnectionHandler = { [weak self] connection in
        Task { await self?.accept(connection) }
      }
      self.listener = listener
      listener.start(queue: queue)
    } catch {
      events.yield(.failed(Self.failure(error)))
    }
  }

  private func listenerChanged(_ state: NWListener.State, attempt: Int) async {
    switch state {
    case .ready:
      events.yield(.listening(port: port))
    case let .failed(error):
      listener?.cancel()
      listener = nil
      if case .posix(.EADDRINUSE) = error, attempt < 5 {
        try? await Task.sleep(for: .milliseconds(300))
        listen(attempt: attempt + 1)
      } else {
        events.yield(.failed(Self.failure(error)))
      }
    default:
      break
    }
  }

  /// What the feature shows for a listener's error; the error itself goes to the log.
  static func failure(_ error: any Error) -> MCPFailure {
    logger.error("The MCP server could not listen: \(error, privacy: .public)")
    if case .posix(.EADDRINUSE) = error as? NWError { return .portTaken }
    return .other
  }

  /// No more connections; calls still waiting get an error.
  func stop() {
    isStopped = true
    listener?.cancel()
    listener = nil
    for call in calls.values {
      call.resume(returning: MCPToolResult(text: "Vortex stopped serving keys.", isError: true))
    }
    calls.removeAll()
    requests.removeAll()
    sessions.removeAll()
    lastSeen.removeAll()
  }

  func reply(to call: MCPCall.ID, with result: MCPToolResult) {
    calls.removeValue(forKey: call)?.resume(returning: result)
    requests = requests.filter { $0.value != call }
  }

  // MARK: - Connections

  private func accept(_ connection: NWConnection) {
    guard !isStopped, Self.isLoopback(connection.endpoint) else {
      connection.cancel()
      return
    }
    let id = ObjectIdentifier(connection)
    arriving.insert(id)
    connection.start(queue: queue)
    receive(connection, buffer: Data())
    // A request that does not arrive in time, such as one sent a byte at a time, is dropped.
    Task { [weak self] in
      try? await Task.sleep(for: Self.requestTime)
      await self?.dropIfArriving(connection)
    }
  }

  private func dropIfArriving(_ connection: NWConnection) {
    guard arriving.remove(ObjectIdentifier(connection)) != nil else { return }
    connection.cancel()
  }

  private nonisolated func receive(_ connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
      var buffer = buffer
      if let data { buffer.append(data) }
      Task { await self?.received(buffer, on: connection, isComplete: isComplete, failed: error != nil) }
    }
  }

  private func received(_ buffer: Data, on connection: NWConnection, isComplete: Bool, failed: Bool) async {
    guard !failed, arriving.contains(ObjectIdentifier(connection)) else {
      arriving.remove(ObjectIdentifier(connection))
      connection.cancel()
      return
    }
    // Who is asking, before any of the body.
    switch HTTPRequest.head(buffer) {
    case .incomplete:
      if isComplete { finish(connection) } else { receive(connection, buffer: buffer) }
      return
    case .invalid:
      finish(connection, with: HTTPResponse(status: 400))
      return
    case let .complete(head):
      if let refusal = refusal(head.path, head.headers) {
        finish(connection, with: refusal)
        return
      }
    }
    switch HTTPRequest.parse(buffer) {
    case .incomplete:
      if isComplete || buffer.count > HTTPRequest.maxHead + HTTPRequest.maxBody + 64 * 1024 {
        finish(connection, with: isComplete ? nil : HTTPResponse(status: 400))
      } else {
        receive(connection, buffer: buffer)
      }
    case .invalid:
      finish(connection, with: HTTPResponse(status: 400))
    case let .complete(request):
      arriving.remove(ObjectIdentifier(connection))
      send(await handle(request, on: connection), on: connection)
    }
  }

  private func finish(_ connection: NWConnection, with response: HTTPResponse? = nil) {
    arriving.remove(ObjectIdentifier(connection))
    if let response { send(response, on: connection) } else { connection.cancel() }
  }

  private nonisolated func send(_ response: HTTPResponse, on connection: NWConnection) {
    connection.send(content: response.serialized, completion: .contentProcessed { _ in connection.cancel() })
  }

  /// Watches a connection whose call is waiting: the client closing it gives the call up.
  private nonisolated func watchForClose(_ connection: NWConnection, call: MCPCall.ID) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self] data, _, isComplete, error in
      guard data == nil || isComplete || error != nil else { return }
      Task { await self?.cancel(call) }
    }
  }

  /// The client gave a waiting call up: the feature stops it and answers it.
  private func cancel(_ call: MCPCall.ID) {
    guard calls[call] != nil else { return }
    events.yield(.cancelled(call))
  }

  // MARK: - Requests

  /// Why a request is refused, from its path and headers alone; nil lets it in.
  private func refusal(_ path: String, _ headers: [String: String]) -> HTTPResponse? {
    guard path.split(separator: "?").first == "/mcp" else { return HTTPResponse(status: 404) }
    if let origin = headers["origin"], !Self.isLocal(origin: origin) { return HTTPResponse(status: 403) }
    if let host = headers["host"], !Self.isLocal(host: host) { return HTTPResponse(status: 403) }
    guard Self.isAuthorized(headers["authorization"], token: token) else {
      return HTTPResponse(status: 401, headers: ["WWW-Authenticate": "Bearer"])
    }
    return nil
  }

  /// The answer to one request; a tool call waits for the feature.
  func handle(_ request: HTTPRequest, on connection: NWConnection? = nil) async -> HTTPResponse {
    if let refusal = refusal(request.path, request.headers) { return refusal }
    switch request.method {
    case "POST":
      return await post(request, on: connection)
    case "DELETE":
      guard let id = request.headers["mcp-session-id"], sessions[id] != nil else { return HTTPResponse(status: 404) }
      end(id)
      return HTTPResponse(status: 200)
    default:
      // No stream of server messages: everything is answered in the POST it came in.
      return HTTPResponse(status: 405, headers: ["Allow": "POST, DELETE"])
    }
  }

  private func post(_ request: HTTPRequest, on connection: NWConnection?) async -> HTTPResponse {
    guard let message = try? JSONDecoder().decode(JSONValue.self, from: request.body), case .object = message else {
      return .json(MCPProtocol.error(id: nil, code: -32700, message: "Parse error"), status: 400)
    }
    let method = message["method"]?.string
    let params = message["params"]
    let sessionHeader = request.headers["mcp-session-id"]
    // A notification or a response needs no answer; a cancelled request stops its call.
    guard let method, let id = message["id"], id != .null else {
      if method == "notifications/cancelled", let sessionHeader, let requestID = params?["requestId"],
         let call = requests[Self.requestKey(sessionHeader, requestID)] {
        cancel(call)
      }
      return HTTPResponse(status: 202)
    }
    if method == "initialize" {
      let session = start(
        MCPSession(id: UUID().uuidString, client: MCPProtocol.clientTitle(params?["clientInfo"]?["name"]?.string))
      )
      let result = MCPProtocol.initializeResult(requestedVersion: params?["protocolVersion"]?.string)
      return .json(MCPProtocol.response(id: id, result: result), headers: ["Mcp-Session-Id": session.id])
    }
    guard let sessionHeader, Self.isSessionID(sessionHeader) else {
      return .json(MCPProtocol.error(id: id, code: -32600, message: "Missing Mcp-Session-Id"), status: 400)
    }
    // Unknown, such as from before Vortex restarted: a new session, whose keys are asked for again. Its own name went
    // with the old one: it is named after the client the connect command is for.
    let session = sessions[sessionHeader] ?? start(MCPSession(id: sessionHeader, client: MCPProtocol.clientTitle("claude-code")))
    lastSeen[session.id] = .now
    switch method {
    case "ping":
      return .json(MCPProtocol.response(id: id, result: [:]))
    case "tools/list":
      return .json(MCPProtocol.response(id: id, result: MCPProtocol.toolList))
    case "tools/call":
      guard let name = params?["name"]?.string, let tool = MCPProtocol.Tool(rawValue: name) else {
        return .json(MCPProtocol.error(id: id, code: -32602, message: "Unknown tool"))
      }
      let call = MCPCall(
        id: UUID(),
        session: session.id,
        client: session.client,
        tool: tool,
        arguments: params?["arguments"] ?? [:]
      )
      if let connection { watchForClose(connection, call: call.id) }
      let result = await withCheckedContinuation { continuation in
        calls[call.id] = continuation
        requests[Self.requestKey(session.id, id)] = call.id
        events.yield(.call(call))
      }
      return .json(MCPProtocol.response(id: id, result: MCPProtocol.toolResult(result)))
    default:
      return .json(MCPProtocol.error(id: id, code: -32601, message: "Method not found: \(method)"))
    }
  }

  /// A new session; the least recently used one goes past `maxSessions`.
  private func start(_ session: MCPSession) -> MCPSession {
    sessions[session.id] = session
    lastSeen[session.id] = .now
    events.yield(.sessionStarted(session))
    while sessions.count > Self.maxSessions, let oldest = lastSeen.min(by: { $0.value < $1.value })?.key {
      end(oldest)
    }
    return session
  }

  private func end(_ session: String) {
    sessions[session] = nil
    lastSeen[session] = nil
    events.yield(.sessionEnded(session))
  }

  private static func requestKey(_ session: String, _ id: JSONValue) -> String {
    session + " " + String(decoding: id.data, as: UTF8.self)
  }

  // MARK: - Checks

  /// The bearer token, compared in constant time.
  static func isAuthorized(_ header: String?, token: String) -> Bool {
    guard let header, header.hasPrefix("Bearer ") else { return false }
    let given = Array(header.dropFirst("Bearer ".count).utf8)
    let expected = Array(token.utf8)
    guard !expected.isEmpty, given.count == expected.count else { return false }
    return zip(given, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
  }

  /// A session id a client may bring: visible ASCII, at most 128 characters.
  static func isSessionID(_ id: String) -> Bool {
    !id.isEmpty && id.utf8.count <= 128 && id.utf8.allSatisfy { (0x21...0x7E).contains($0) }
  }

  /// 127.0.0.1, localhost or ::1, with any port.
  static func isLocal(host: String) -> Bool {
    let name = host.hasPrefix("[") ? String(host.dropFirst().prefix { $0 != "]" }) : String(host.prefix { $0 != ":" })
    return ["127.0.0.1", "localhost", "::1"].contains(name.lowercased())
  }

  /// A page of this Mac's own, such as a local MCP inspector; any other site is refused.
  static func isLocal(origin: String) -> Bool {
    guard let components = URLComponents(string: origin), let host = components.host else { return false }
    return isLocal(host: host.contains(":") ? "[\(host)]" : host)
  }

  static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
    guard case let .hostPort(host, _) = endpoint else { return false }
    switch host {
    case let .ipv4(address): return address.isLoopback
    case let .ipv6(address): return address.isLoopback
    case let .name(name, _): return isLocal(host: name)
    @unknown default: return false
    }
  }
}

private let logger = Logger(subsystem: "io.github.ortexisartem.vortex", category: "mcp")
