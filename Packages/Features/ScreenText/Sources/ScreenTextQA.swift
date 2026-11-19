#if DEBUG
  import AppKit
  import ComposableArchitecture
  import CoreImage
  import CoreImage.CIFilterBuiltins
  import CoreText
  import ImageIO
  import SwiftUI
  import VortexCore
  import VortexPlatform

  extension ScreenTextModule {
    private static var isRegistered = false
    /// The `screentext-settings` window, made at its first snapshot.
    private static var settingsWindow: NSWindow?
    /// Where `fixture` drew its parts, in points from the screen's top left corner.
    private static var fixtureFrames: [String: [Double]] = [:]

    /// QA mode's `screentext` command, which stands for the user at the frozen screen:
    /// - `capture`: presses the feature's shortcut, which the shell runs as the utility action (`utility press
    ///   id=screentext.copy` presses its button);
    /// - `drag x= y= w= h=`: the frame drawn so far, the mouse still down; `release`: the mouse let go there;
    /// - `frame x= y= w= h=`: a whole drag, let go, which reads the frame; all in points from the screen's top left;
    /// - `cancel`: Esc on the frozen screen, refused while none shows;
    /// - `fixture [background=<png>]`: draws fixtures/screen.png, what a capture sees: lines of text in a chat window and
    ///   three QR codes (a link, some text, a Wi-Fi network), over a dark screen or the picture given; their frames go
    ///   in the state section;
    /// - `press=turnOn|restart`: the Screen Recording row on the settings page.
    /// The state section `screentext` has the phase, the frame, the app in front, the message showing and the last
    /// one with when it showed and went (seconds since the run started), and the fixture's frames. The windows
    /// `screentext` (the frozen screen) and `screentext-settings` (the settings page, off every display) draw them.
    static func registerQACommands(overlay: ScreenTextOverlay?) {
      guard QA.isActive, !isRegistered else { return }
      isRegistered = true
      QA.registerState(section: "screentext") { QAState(store.state, fixture: fixtureFrames) }
      QA.registerWindow(id: "screentext", mode: { "\(store.phase)".components(separatedBy: "(").first }) {
        overlay?.overlay.qaWindow
      }
      QA.registerWindow(id: "screentext-settings") { qaSettingsWindow() }
      QA.register(command: "screentext") { arguments in
        let pressedRow = try QAPermissions.pressRow(
          arguments,
          needs: permissionNeeds,
          statuses: store.permissionStatuses,
          turnOn: { store.send(.turnOnTapped($0)) },
          restart: { store.send(.restartTapped) }
        )
        if pressedRow { return }
        if arguments["capture"] != nil {
          guard QA.pressHotkey(Hotkey.copyScreenText.name) > 0 else {
            throw QAError("nobody listens for the shortcut \(Hotkey.copyScreenText.name): the feature doesn't run")
          }
        } else if arguments["cancel"] != nil {
          guard store.capture != nil else { throw QAError("no frozen screen shows") }
          store.send(.cancelTapped)
        } else if arguments["drag"] != nil {
          let frame = try rect(arguments)
          try requireFraming()
          store.send(.frameChanged(frame))
        } else if arguments["release"] != nil {
          try requireFraming()
          guard let frame = store.capture?.frame else { throw QAError("no frame is drawn: drag first") }
          store.send(.frameEnded(frame))
        } else if arguments["frame"] != nil {
          let frame = try rect(arguments)
          try requireFraming()
          store.send(.frameChanged(frame))
          store.send(.frameEnded(frame))
        } else if arguments["fixture"] != nil {
          try await drawFixture(background: arguments["background"])
        } else {
          throw QAError("screentext takes capture, drag|frame x= y= w= h=, release, cancel, fixture [background=], press=turnOn|restart")
        }
      }
    }

    private static func requireFraming() throws {
      guard case .framing = store.phase else { throw QAError("the frame is drawn on the frozen screen: capture first") }
    }

    /// `x= y= w= h=` in points from the screen's top left corner; a negative width or height drags the other way.
    private static func rect(_ arguments: [String: String]) throws -> CGRect {
      let values = ["x", "y", "w", "h"].map { arguments[$0].flatMap(Double.init) }
      guard values.allSatisfy({ $0?.isFinite == true }) else { throw QAError("a frame takes x= y= w= h=, in points") }
      return CGRect(x: values[0]!, y: values[1]!, width: values[2]!, height: values[3]!)
    }

    /// Screen Text in the state dump, as plain words.
    struct QAState: Encodable {
      /// idle, starting, framing or reading.
      var phase: String
      /// The frame as drawn so far: x, y, width, height in points from the screen's top left; nil before a drag.
      var frame: [Double]?
      /// The app in front when the screen froze, which the copy names.
      var frontApp: String?
      var message: Message?
      var lastMessage: Message?
      /// Where the fixture's parts are: text, linkCode, textCode, wifiCode, empty.
      var fixture: [String: [Double]]

      struct Message: Encodable {
        /// copiedLines, copiedLink, copiedCode or nothingFound.
        var kind: String
        /// The words left and right of the cutout, as the notch shows them.
        var left: [String]
        var right: [String]
        /// Seconds since the run started.
        var shownAt: Double?
        var hiddenAt: Double?
      }

      @MainActor
      init(_ state: ScreenTextFeature.State, fixture: [String: [Double]]) {
        phase = "\(state.phase)".components(separatedBy: "(").first ?? ""
        frame = (state.capture?.frame).map { [$0.minX, $0.minY, $0.width, $0.height] }
        frontApp = state.capture?.frontApp
        message = state.message.map { Self.describe($0, shownAt: nil, hiddenAt: nil) }
        lastMessage = state.lastMessage.map { Self.describe($0.message, shownAt: $0.shownAt, hiddenAt: $0.hiddenAt) }
        self.fixture = fixture
      }

      @MainActor
      static func describe(_ message: ScreenTextFeature.Message, shownAt: Date?, hiddenAt: Date?) -> Self.Message {
        let indicator = ScreenTextFeature.indicator(message)
        func words(_ items: [NotchIndicator.Item]) -> [String] {
          items.compactMap { item in if case let .text(text) = item { text } else { nil } }
        }
        let kind = "\(message)".components(separatedBy: "(").first ?? ""
        return Message(
          kind: kind,
          left: words(indicator.leading),
          right: words(indicator.trailing),
          shownAt: shownAt.map(QA.time(of:)),
          hiddenAt: hiddenAt.map(QA.time(of:))
        )
      }
    }

    /// The settings as Settings › Features shows them, with the live store, at the content width of the window and as
    /// tall as they are now. Never on a display: off every one, and never ordered in.
    private static func qaSettingsWindow() -> NSWindow {
      let window = settingsWindow ?? {
        // The window's width less the sidebar and the paddings of the settings' scroll view (SettingsView).
        let width = VortexMetrics.windowSize.width - VortexMetrics.sidebarWidth - 10 - 18
        let content = ScreenTextSettingsView(store: store)
          .frame(width: width)
          .padding(.vertical, 6)
          .font(.system(size: 13))
          .foregroundStyle(VortexColor.primaryText)
          .background(VortexColor.windowBackground)
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        settingsWindow = window
        return window
      }()
      let size = window.contentView?.fittingSize ?? .zero
      window.setFrame(QA.offscreen(CGRect(origin: .zero, size: size)), display: false)
      return window
    }

    // MARK: - The fixture

    /// Draws what a capture sees: a chat window with lines of text, and three QR codes with their captions, over a dark
    /// screen or the picture at `background`, the main display's size.
    private static func drawFixture(background: String?) async throws {
      let (size, scale) = QA.fixtureDisplay
      var backdrop: CGImage?
      if let background {
        guard QA.isSafe(path: background), let image = NSImage(contentsOfFile: background)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw QAError("background= takes a picture inside the QA folder or a temporary folder") }
        backdrop = image
      }
      let (png, frames) = try Fixture.draw(size: size, scale: scale, background: backdrop)
      @Dependency(\.fileClient) var files
      try await files.write(png, QA.screenFixture)
      fixtureFrames = frames.mapValues { [$0.minX, $0.minY, $0.width, $0.height] }
      QA.log("screentext", "fixture", ["size": "\(Int(size.width))×\(Int(size.height))"])
    }

    enum Fixture {
      static let link = "https://github.com/OrtexIsArtem/vortex"
      static let text = "Table 12 · Order 4815"
      static let wifi = "WIFI:S:Vortex Office;T:WPA;P:notch-2026;;"
      static let lines = [
        "Build 43 failed on main",
        "error: cannot find 'FooBar' in scope",
        "Привіт! Глянь, будь ласка, цю помилку",
      ]

      /// The picture as PNG data, and where each part is, in points from the top left.
      static func draw(size: CGSize, scale: CGFloat, background: CGImage?) throws -> (Data, [String: CGRect]) {
        let width = Int(size.width * scale), height = Int(size.height * scale)
        guard let context = CGContext(
          data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw QAError("the fixture could not be drawn") }
        // Points from the top left, as frames are given.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        if let background {
          context.saveGState()
          context.translateBy(x: 0, y: size.height)
          context.scaleBy(x: 1, y: -1)
          context.draw(background, in: aspectFill(CGSize(width: background.width, height: background.height), in: size))
          context.restoreGState()
        } else {
          context.setFillColor(CGColor(gray: 0.15, alpha: 1))
          context.fill(CGRect(origin: .zero, size: size))
        }
        var frames: [String: CGRect] = [:]
        // Under the notch, where the media rig's takes and the catalog's preview frame the screen: the chat and the link's
        // code side by side in the first row, the other two codes and a bare part in the second.
        let middle = size.width / 2

        // A chat window with three lines.
        let chat = CGRect(x: middle - 400, y: 96, width: 460, height: 172)
        fill(context, chat, gray: 0.97, radius: 14)
        let lineHeight: CGFloat = 36
        for (row, line) in lines.enumerated() {
          drawText(line, in: context, at: CGPoint(x: chat.minX + 24, y: chat.minY + 30 + CGFloat(row) * lineHeight), size: 20)
        }
        frames["text"] = CGRect(x: chat.minX + 12, y: chat.minY + 16, width: chat.width - 24, height: lineHeight * 3 + 20)

        // Three QR codes on cards, with captions.
        let side: CGFloat = 150
        for (name, payload, caption, origin) in [
          ("linkCode", link, "Scan to open", CGPoint(x: middle + 100, y: 96)),
          ("textCode", text, "Your order", CGPoint(x: middle - 400, y: 330)),
          ("wifiCode", wifi, "Office Wi-Fi", CGPoint(x: middle - 160, y: 330)),
        ] {
          let card = CGRect(origin: origin, size: CGSize(width: side + 30, height: side + 64))
          fill(context, card, gray: 1, radius: 12)
          let code = CGRect(x: card.minX + 15, y: card.minY + 15, width: side, height: side)
          drawCode(payload, in: context, at: code)
          drawText(caption, in: context, at: CGPoint(x: card.minX + 15, y: code.maxY + 13), size: 14)
          frames[name] = card
        }

        // A bare part of the screen, with nothing to read.
        frames["empty"] = CGRect(x: middle + 100, y: 340, width: 220, height: 160)

        guard let image = context.makeImage() else { throw QAError("the fixture could not be drawn") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
          throw QAError("the fixture could not be encoded")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw QAError("the fixture could not be encoded") }
        return (data as Data, frames)
      }

      private static func aspectFill(_ image: CGSize, in size: CGSize) -> CGRect {
        let scale = max(size.width / image.width, size.height / image.height)
        let fitted = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
      }

      private static func fill(_ context: CGContext, _ rect: CGRect, gray: CGFloat, radius: CGFloat) {
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
      }

      /// A line of black text whose top is at `origin`.
      private static func drawText(_ text: String, in context: CGContext, at origin: CGPoint, size: CGFloat) {
        let font = CTFontCreateUIFontForLanguage(.system, size, nil)!
        let attributes: [NSAttributedString.Key: Any] = [
          NSAttributedString.Key(kCTFontAttributeName as String): font,
          NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.saveGState()
        // Text draws upwards from its baseline: flip back around the line.
        context.translateBy(x: origin.x, y: origin.y + CTFontGetAscent(font))
        context.scaleBy(x: 1, y: -1)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
      }

      private static func drawCode(_ payload: String, in context: CGContext, at rect: CGRect) {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage, let image = CIContext().createCGImage(code, from: code.extent) else { return }
        context.saveGState()
        context.interpolationQuality = .none
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
      }
    }
  }
#endif
