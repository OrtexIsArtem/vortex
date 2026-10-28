#if DEBUG
  import ComposableArchitecture
  import Foundation

  /// Something a simulated system service was asked to do, or a QA rule that was broken.
  struct QAEvent: Encodable, Equatable, Sendable {
    /// Seconds since the run started.
    var time: Double
    var client: String
    var event: String
    var detail: [String: String]
  }

  /// The system events log of a QA run and its violations, both in the state dump. Secrets never land here: every
  /// value in the simulated keychain is taken out of what is logged.
  enum QALog {
    static let started = Date()
    /// The newest events; older ones drop off.
    static let limit = 1_000
    static let events = LockIsolated<[QAEvent]>([])
    /// Things QA mode must never let happen: a window on a display, Vortex in front, a file outside the QA folder.
    static let violations = LockIsolated<[QAEvent]>([])
    /// Values to take out of everything logged: whatever is in the simulated keychain.
    static let secrets = LockIsolated<Set<String>>([])

    static func record(_ client: String, _ event: String, _ detail: [String: String] = [:]) {
      let entry = makeEvent(client, event, detail)
      events.withValue { events in
        events.append(entry)
        if events.count > limit { events.removeFirst(events.count - limit) }
      }
    }

    static func violation(_ client: String, _ event: String, _ detail: [String: String] = [:]) {
      let entry = makeEvent(client, event, detail)
      violations.withValue { $0.append(entry) }
      record(client, "violation: " + event, detail)
    }

    private static func makeEvent(_ client: String, _ event: String, _ detail: [String: String]) -> QAEvent {
      QAEvent(
        time: (Date.now.timeIntervalSince(started) * 1_000).rounded() / 1_000,
        client: client,
        event: redact(event),
        detail: detail.mapValues(redact)
      )
    }

    /// The text with every secret replaced by dots. Values shorter than 4 characters are left alone: they would blot
    /// out ordinary words.
    static func redact(_ text: String) -> String {
      redact(text, secrets: secrets.value)
    }

    static func redact(_ text: String, secrets: Set<String>) -> String {
      secrets
        .filter { $0.count >= 4 }
        .sorted { $0.count > $1.count }
        .reduce(text) { $0.replacingOccurrences(of: $1, with: "••••") }
    }
  }
#endif
