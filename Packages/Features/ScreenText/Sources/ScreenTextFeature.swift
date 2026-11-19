import ComposableArchitecture
import Foundation
import os
import VortexCore
import VortexPlatform

extension Hotkey {
  /// Freezes the screen to copy the text in a frame. None by default; the user records it on the feature's settings
  /// page. The shell listens for it through the utility action, which closes the window first.
  static let copyScreenText = Hotkey("copyScreenText")
}

extension ScreenTextFeature {
  /// What was read in the frame.
  public enum Reading: Equatable, Sendable {
    /// What a QR code holds, as it spells it.
    case qrCode(String)
    /// The lines of text, top to bottom, none blank; none when there is no text.
    case lines([String])
  }

  /// What the notch says once the frame is read, for about 1.5 s.
  public enum Message: Equatable, Sendable {
    /// "Copied · N lines".
    case copiedLines(Int)
    /// "Link copied · host": a QR code's web address.
    case copiedLink(host: String)
    /// "Copied · QR code": anything else a QR code holds.
    case copiedCode
    /// "No text found": nothing was copied.
    case nothingFound
  }

  /// A message the notch showed, with when it came and went (nil while it shows).
  public struct ShownMessage: Equatable, Sendable {
    public var message: Message
    public var shownAt: Date
    public var hiddenAt: Date?
  }

  /// A capture, from the frozen screen to the read of its frame.
  public struct Capture: Equatable, Identifiable, Sendable {
    public let id: UUID
    let screenshot: Screenshot
    /// The app in front when the screen froze: where the text comes from, which the copy names.
    let frontApp: String?
    /// The frame being drawn, or drawn, in points from the screen's top left corner.
    var frame: CGRect?
  }
}

/// Text off the screen: the screen freezes, the user frames an area, and what's in it goes to the pasteboard as a copy
/// of the user's own: a QR code's text first, otherwise the lines of text. The notch says what was copied for about
/// 1.5 s. Esc cancels at every step. Nothing opens, nothing is kept.
@Reducer
public struct ScreenTextFeature: Sendable {
  public static let id: FeatureID = "screentext"
  /// A smaller frame, as a click makes, ends the capture quietly.
  static let smallestFrame: CGFloat = 8
  /// How long the notch says what was copied.
  static let messageTime: Duration = .milliseconds(1_500)
  /// Over Timer's ear (10) and the shelf's (0), under Keys' waiting approval (20).
  static let messagePriority = 15

  public enum Phase: Equatable, Sendable {
    case idle
    /// The shortcut was pressed: the screen is being taken, or waits for the shell's first read of the permissions.
    case starting
    /// The frozen screen shows; the user frames an area.
    case framing(Capture)
    /// The frame is drawn and read; the frozen screen stays, so Esc still reaches it.
    case reading(Capture)

    var isReading: Bool {
      if case .reading = self { true } else { false }
    }
  }

  @ObservableState
  public struct State: Equatable {
    var isEnabled = false
    var phase = Phase.idle
    /// What the notch says now; nil while it says nothing.
    var message: Message?
    /// The last message, with when it showed and went.
    var lastMessage: ShownMessage?
    /// What macOS says about Screen Recording, read by the shell; the status decides whether a capture starts.
    @SharedReader(.permissionStatuses) var permissionStatuses
    /// A required permission is off: a press opens the shell's blocking page instead.
    @SharedReader(.appBlocked) var appBlocked
    @Shared(.notchIndicators) var indicators

    public init() {}

    /// The capture whose frozen screen shows: while framing and while reading.
    var capture: Capture? {
      switch phase {
      case let .framing(capture), let .reading(capture): capture
      case .idle, .starting: nil
      }
    }
  }

  public enum Action: Equatable, Sendable {
    case start
    case stop
    /// The utility action, from its shortcut or its button: freeze the screen.
    case captureRequested
    case captureTaken(Screenshot, frontApp: String?)
    /// The screen couldn't be taken, as while another capture's frozen screen shows.
    case captureFailed
    case frameChanged(CGRect)
    /// The mouse let go: the frame is read, or, smaller than a few points, the capture ends.
    case frameEnded(CGRect)
    case read(Reading)
    /// Esc, or another app coming to the front.
    case cancelTapped
    case messageExpired
    /// The settings page appeared: the statuses are read again.
    case settingsShown
    /// "Turn on" in the settings row of a permission that is off: the shell's page.
    case turnOnTapped(Permission)
    /// "Restart Vortex" in the row of a permission that works after a relaunch.
    case restartTapped
  }

  @Dependency(\.activeAppClient) var activeApp
  @Dependency(\.continuousClock) var clock
  @Dependency(\.date.now) var now
  @Dependency(\.pasteboardClient) var pasteboard
  @Dependency(\.permissionPage) var permissionPage
  @Dependency(\.permissionsClient) var permissions
  @Dependency(\.screenCaptureClient) var screenCapture
  @Dependency(\.systemClient) var system
  @Dependency(\.textRecognitionClient) var recognition
  @Dependency(\.uuid) var uuid

  private enum CancelID {
    case startCapture
    case reading
    case message
  }

  public init() {}

  public var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .start:
        state.isEnabled = true
        return .none

      case .stop:
        state.isEnabled = false
        state.phase = .idle
        // A message showing goes with the feature, so none comes back when it runs again.
        return .merge(
          .cancel(id: CancelID.startCapture),
          .cancel(id: CancelID.reading),
          show(nil, &state)
        )

      case .captureRequested:
        guard state.isEnabled, state.phase == .idle else { return .none }
        // While Vortex is blocked, the shell shows its blocking page whatever is asked for.
        guard !state.appBlocked else { return openPage(.screenRecording) }
        guard let status = state.permissionStatuses[.screenRecording] else {
          // Before the shell's first read: wait for it, then decide again, blocked mode included.
          return .run { [statuses = state.$permissionStatuses] send in
            for await value in statuses.publisher.values where !value.isEmpty {
              await send(.captureRequested)
              return
            }
          }
          .cancellable(id: CancelID.startCapture, cancelInFlight: true)
        }
        // Off, or granted only from the next launch: the shell's page, and nothing is taken. Vortex never asks macOS.
        guard status == .granted || status == .notNeeded else { return openPage(.screenRecording) }
        state.phase = .starting
        return .run { send in
          // The app in front first, before the frozen screen takes the front: the text comes from it.
          let front = await activeApp.frontmost()
          let screenshot = try await screenCapture.captureScreenUnderPointer()
          await send(.captureTaken(screenshot, frontApp: front))
        } catch: { error, send in
          logger.error("Taking the screen failed: \(error, privacy: .public)")
          await send(.captureFailed)
        }
        .cancellable(id: CancelID.startCapture, cancelInFlight: true)

      case let .captureTaken(screenshot, front):
        guard state.isEnabled, state.phase == .starting else { return .none }
        state.phase = .framing(Capture(id: uuid(), screenshot: screenshot, frontApp: front))
        return .none

      case .captureFailed:
        if state.phase == .starting { state.phase = .idle }
        return .none

      case let .frameChanged(frame):
        guard case var .framing(capture) = state.phase else { return .none }
        capture.frame = frame
        state.phase = .framing(capture)
        return .none

      case let .frameEnded(frame):
        guard case var .framing(capture) = state.phase else { return .none }
        let bounds = CGRect(origin: .zero, size: capture.screenshot.image.size)
        let frame = frame.standardized.intersection(bounds)
        guard !frame.isNull, frame.width >= Self.smallestFrame, frame.height >= Self.smallestFrame,
              let part = capture.screenshot.image.cropped(to: frame)
        else {
          // A click, a few points or nothing of the screen: nothing to read, and nothing is said.
          state.phase = .idle
          return .none
        }
        capture.frame = frame
        state.phase = .reading(capture)
        return .run { send in
          // A QR code first: what it holds is what the frame is about.
          do {
            if let code = try await recognition.readQRCode(part) {
              await send(.read(.qrCode(code)))
              return
            }
          } catch is CancellationError {
            return
          } catch {
            logger.error("Reading a QR code failed: \(error, privacy: .public)")
          }
          let text: String
          do {
            text = try await recognition.recognize(part)
          } catch is CancellationError {
            return
          } catch {
            logger.error("Reading the text failed: \(error, privacy: .public)")
            text = ""
          }
          await send(.read(.lines(Self.lines(of: text))))
        }
        .cancellable(id: CancelID.reading, cancelInFlight: true)

      case let .read(reading):
        guard case let .reading(capture) = state.phase else { return .none }
        state.phase = .idle
        switch reading {
        case let .qrCode(payload):
          // A Wi-Fi password or a one-time code's secret stays hidden in clipboard histories and off the notch.
          let isSecret = Self.isSecret(payload)
          let host = isSecret ? nil : Self.webHost(payload)
          return .merge(
            copy(.text(payload), isConcealed: isSecret, from: capture.frontApp),
            show(host.map { .copiedLink(host: Self.shownHost($0)) } ?? .copiedCode, &state)
          )
        case let .lines(lines) where !lines.isEmpty:
          return .merge(
            copy(.text(lines.joined(separator: "\n")), isConcealed: false, from: capture.frontApp),
            show(.copiedLines(lines.count), &state)
          )
        case .lines:
          // Nothing to copy: the pasteboard stays as it was.
          return show(.nothingFound, &state)
        }

      case .cancelTapped:
        guard state.phase != .idle else { return .none }
        state.phase = .idle
        return .merge(.cancel(id: CancelID.startCapture), .cancel(id: CancelID.reading))

      case .messageExpired:
        return show(nil, &state)

      case .settingsShown:
        return .run { _ in await permissions.refresh() }

      case let .turnOnTapped(permission):
        return openPage(permission)

      case .restartTapped:
        return .run { _ in await system.relaunch() }
      }
    }
  }

  /// The shell's page for a permission, instead of asking macOS.
  private func openPage(_ permission: Permission) -> Effect<Action> {
    .run { _ in await permissionPage.open(permission) }
  }

  /// A copy of the user's own, which Clipboard's history keeps by its rules, named after the app the text came from.
  private func copy(_ content: PasteboardContent, isConcealed: Bool, from app: String?) -> Effect<Action> {
    .run { _ in await pasteboard.copy(content, isConcealed, app) }
  }

  /// Shows a message in the notch, in place of the one showing, for `messageTime`; nil takes it away.
  private func show(_ message: Message?, _ state: inout State) -> Effect<Action> {
    if state.message != nil, state.lastMessage?.hiddenAt == nil {
      state.lastMessage?.hiddenAt = now
    }
    state.message = message
    if let message {
      state.lastMessage = ShownMessage(message: message, shownAt: now, hiddenAt: nil)
    }
    let indicator = message.map(Self.indicator)
    if state.indicators[Self.id] != indicator {
      state.$indicators.withLock { $0[Self.id] = indicator }
    }
    guard message != nil else { return .cancel(id: CancelID.message) }
    return .run { send in
      try await clock.sleep(for: Self.messageTime)
      await send(.messageExpired)
    }
    .cancellable(id: CancelID.message, cancelInFlight: true)
  }

  /// What the notch shows for a message: its words on both sides of the cutout, in the app's language.
  static func indicator(_ message: Message) -> NotchIndicator {
    let leading: String
    var trailing: String?
    switch message {
    case let .copiedLines(count):
      leading = String(localized: "Copied", bundle: .module)
      trailing = String(localized: "\(count) lines", bundle: .module)
    case let .copiedLink(host):
      leading = String(localized: "Link copied", bundle: .module)
      trailing = host
    case .copiedCode:
      leading = String(localized: "Copied", bundle: .module)
      trailing = String(localized: "QR code", bundle: .module)
    case .nothingFound:
      leading = String(localized: "No text found", bundle: .module)
    }
    return NotchIndicator(leading: [.text(leading)], trailing: trailing.map { [.text($0)] } ?? [], priority: messagePriority)
  }

  /// The lines of a reading, top to bottom: spaces around each go, and so do blank ones.
  static func lines(of text: String) -> [String] {
    text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// A Wi-Fi network's password or a one-time code's secret.
  static func isSecret(_ payload: String) -> Bool {
    let code = payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return code.hasPrefix("wifi:") || code.hasPrefix("otpauth://") || code.hasPrefix("otpauth-migration://")
  }

  /// The host of a single http or https address, in lower case and in the letters the code spells it with (never
  /// `xn--…`); nil for anything else.
  static func webHost(_ payload: String) -> String? {
    let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.contains(where: \.isWhitespace), let separator = text.range(of: "://") else { return nil }
    let scheme = text[..<separator.lowerBound].lowercased()
    guard scheme == "http" || scheme == "https" else { return nil }
    var authority = text[separator.upperBound...].prefix { !"/?#".contains($0) }
    if let at = authority.lastIndex(of: "@") {
      authority = authority[authority.index(after: at)...]
    }
    // The port goes; an IPv6 address keeps the colons inside its brackets.
    if authority.hasPrefix("["), let close = authority.firstIndex(of: "]") {
      authority = authority[...close]
    } else if let colon = authority.firstIndex(of: ":") {
      authority = authority[..<colon]
    }
    return authority.isEmpty ? nil : authority.lowercased()
  }

  /// A host short enough for the notch's ears: without "www.", and past 24 characters cut in the middle.
  static func shownHost(_ host: String) -> String {
    var host = host
    if host.hasPrefix("www."), host.count > 4 { host.removeFirst(4) }
    guard host.count > 24 else { return host }
    return host.prefix(11) + "…" + host.suffix(12)
  }
}

private let logger = Logger(subsystem: "io.github.ortexisartem.vortex", category: "screentext")
