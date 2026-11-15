#if DEBUG
  import AppKit
  import ComposableArchitecture
  import GRDB
  import SwiftUI
  import VortexCore
  import VortexPlatform

  extension ClipboardModule {
    private static var isRegistered = false
    /// The last `seed`: how many items it wrote and how long that took, for the state dump.
    private static var lastSeed: String?
    /// The `clipboard-settings` window, made at its first snapshot.
    private static var settingsWindow: NSWindow?

    /// QA mode's `clipboard` command:
    /// - `press=turnOn|restart` presses the Paste from Other Apps row in the settings;
    /// - `press=clear|undo` presses Clear or Undo, refused while it doesn't show (nothing unpinned, no Undo);
    /// - `keep=week|month|threeMonths|year|forever` chooses Keep history;
    /// - `search text=<query>` types the query (empty: no search);
    /// - `card n=<1-based place among the cards shown> do=click|hover|unhover|pin|unpin|delete` acts on a card as the
    ///   pointer does: `click` copies it again, `hover` reads a long text's whole text, `unhover` sends nothing (the card
    ///   only hides its buttons), `pin` and `unpin` press the pin button that shows, `delete` its ×;
    /// - `seed count=<n> [images=<n>]` adds generated items spread over the last year, through the real writes, and
    ///   reads the history again; Keep history removes the older ones as usual, so choose `keep=forever` first.
    /// The state section `clipboard` has the counts, the choice, the search, a pending Undo, the whole text the hover
    /// read holds (`wholeTextID`, `wholeTextBytes`) and the images waiting to be read for search (`imagesToRead`,
    /// `isReadingImage`). `snapshot window=clipboard-settings` draws the settings section with the live store, whole,
    /// at the Settings window's width, off every display.
    static func registerQACommands() {
      guard QA.isActive, !isRegistered else { return }
      isRegistered = true
      QA.registerState(section: "clipboard") { QAState(store.state, lastSeed: lastSeed) }
      QA.registerWindow(id: "clipboard-settings") { qaSettingsWindow() }
      QA.register(command: "clipboard") { arguments in
        let pressedRow = try QAPermissions.pressRow(
          arguments,
          needs: permissionNeeds,
          statuses: store.permissionStatuses,
          turnOn: { store.send(.turnOnTapped($0)) },
          restart: { store.send(.restartTapped) }
        )
        if pressedRow { return }
        if arguments["seed"] != nil {
          guard let count = Int(arguments["count"] ?? ""), count > 0 else { throw QAError("seed takes count=<n>") }
          try await seed(count: count, images: Int(arguments["images"] ?? "") ?? count / 20)
        } else if let keep = arguments["keep"] {
          guard let lifetime = HistoryLifetime(rawValue: keep) else {
            throw QAError("keep= takes \(HistoryLifetime.allCases.map(\.rawValue).joined(separator: ", "))")
          }
          store.send(.lifetimeChanged(lifetime))
        } else if arguments["search"] != nil {
          store.send(.queryChanged(arguments["text"] ?? ""))
        } else if arguments["card"] != nil {
          if let action = try cardAction(arguments, shown: store.shownItems) {
            store.send(action)
          }
        } else {
          switch arguments["press"] {
          case "clear":
            guard store.items.contains(where: { !$0.isPinned }) else { throw QAError("Clear doesn't show: nothing is unpinned") }
            store.send(.clearTapped)
          case "undo":
            guard store.pendingRemoval != nil else { throw QAError("no Undo shows") }
            store.send(.undoTapped)
          default:
            throw QAError("""
              clipboard takes seed count= [images=], keep=, search text=, card n= do=, press=clear|undo|turnOn|restart
              """)
          }
        }
      }
    }

    /// What `card n= do=` sends: the action the card's views send for that pointer action, or nil when they send
    /// none (`unhover`, `hover` on anything but a long text).
    static func cardAction(_ arguments: [String: String], shown: [ClipboardItem]) throws -> ClipboardFeature.Action? {
      guard let place = Int(arguments["n"] ?? ""), shown.indices.contains(place - 1) else {
        throw QAError("card takes n=<1…\(shown.count)>, a place among the cards shown")
      }
      let item = shown[place - 1]
      switch arguments["do"] {
      case "click":
        return .itemTapped(item.id)
      case "hover":
        // The card reads the whole text of a long one only (ClipboardCard's DragSourceArea).
        return item.isTruncated ? .itemHovered(item.id) : nil
      case "unhover":
        return nil
      case "pin":
        guard !item.isPinned else { throw QAError("card \(place) is pinned: its button is Unpin") }
        return .pinTapped(item.id)
      case "unpin":
        guard item.isPinned else { throw QAError("card \(place) isn't pinned: its button is Pin") }
        return .pinTapped(item.id)
      case "delete":
        return .deleteTapped(item.id)
      default:
        throw QAError("card takes do=click|hover|unhover|pin|unpin|delete")
      }
    }

    /// The settings section as Settings › Features shows it, with the live store, at the content width of the
    /// Settings window and as tall as the section is now. Never on a display: off every one, and never ordered in.
    private static func qaSettingsWindow() -> NSWindow {
      let window = settingsWindow ?? {
        // The window's width less the sidebar and the paddings of the settings' scroll view (SettingsView).
        let width = VortexMetrics.windowSize.width - VortexMetrics.sidebarWidth - 10 - 18
        let content = ClipboardSettingsView(store: store)
          .frame(width: width)
          .padding(.vertical, 6)
          .font(.system(size: 13))
          .foregroundStyle(VortexColor.primaryText)
          .toggleStyle(.vortex)
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

    /// Writes generated items as copies do (`HistoryWrite.insert`, 500 to a transaction, image files first), then
    /// reads the history again as the launch does.
    private static func seed(count: Int, images: Int) async throws {
      @Dependency(\.database) var database
      @Dependency(\.fileClient) var files
      @Dependency(\.date.now) var now
      let started = ContinuousClock.now
      let seed = ClipboardSeed(count: count, images: images, now: now)
      for file in seed.referencedFiles {
        try await files.write(Data("Seeded by QA mode.\n".utf8), file)
      }
      for item in seed.items {
        if let url = item.imageURL {
          try await files.write(ClipboardSeed.png, url)
        }
      }
      for start in stride(from: 0, to: seed.items.count, by: 500) {
        let batch = seed.items[start..<min(start + 500, seed.items.count)].map(HistoryWrite.insert)
        _ = try await database.write { db in try HistoryWrite.apply(batch, db) }
      }
      let (items, _) = try await ClipboardFeature.loadHistory(database: database, files: files)
      store.send(.loaded(items))
      lastSeed = "\(count) items (\(images) images) in \(ContinuousClock.now - started)"
    }

    struct QAState: Encodable {
      var isLoaded: Bool
      var savesToDisk: Bool
      var items: Int
      var pinned: Int
      var truncated: Int
      var bytes: Int
      var lifetime: String
      var query: String
      /// nil while nothing is searched.
      var results: Int?
      var shown: Int
      /// Home's rows, and how many of them are pinned.
      var homeRows: Int
      var homePinnedRows: Int
      var pendingUndo: String?
      var isWriting: Bool
      var queuedWrites: Int
      /// Failed attempts in a row; while above 0 the queue waits to be written again.
      var failedWrites: Int
      var unavailable: Int
      /// The item whose whole text the hover read holds, and its size in UTF-8.
      var wholeTextID: String?
      var wholeTextBytes: Int?
      /// New images waiting to be read for search, and whether one is being read: reading is over at 0 and false.
      var imagesToRead: Int
      var isReadingImage: Bool
      var lastSeed: String?

      @MainActor
      init(_ state: ClipboardFeature.State, lastSeed: String?) {
        isLoaded = state.isLoaded
        savesToDisk = state.savesToDisk
        items = state.items.count
        pinned = state.items.filter(\.isPinned).count
        truncated = state.items.filter(\.isTruncated).count
        bytes = state.historySize.bytes
        lifetime = state.settings.historyLifetime.rawValue
        query = state.query
        results = state.searchResults?.count
        shown = state.shownItems.count
        let home = state.homeItems
        homeRows = home.count
        homePinnedRows = home.filter(\.isPinned).count
        pendingUndo = state.pendingRemoval.map { pending in
          switch pending.reason {
          case .cleared: "cleared \(pending.items.count)"
          case let .lifetime(previous): "older removed \(pending.items.count), was \(previous.rawValue)"
          }
        }
        isWriting = state.writing > 0
        queuedWrites = state.queuedWrites.count
        failedWrites = state.failedWrites
        unavailable = state.unavailable.count
        wholeTextID = state.wholeText?.id.uuidString
        wholeTextBytes = state.wholeText?.text.utf8.count
        imagesToRead = state.imagesToRead.count
        isReadingImage = state.readingImage != nil
        self.lastSeed = lastSeed
      }
    }
  }

  /// Generated history for QA and the scale tests: texts from 20 B to 200 KB, links, file references and images, from a
  /// handful of apps, copied over the last year. The same count always gives the same items.
  struct ClipboardSeed {
    var items: [ClipboardItem] = []
    /// Files the file items point at, in the data folder; every seventh item points at one that isn't there.
    var referencedFiles: [URL] = []

    static let apps = [
      AppInfo(bundleID: "com.apple.Terminal", name: "Terminal"),
      AppInfo(bundleID: "com.apple.Safari", name: "Safari"),
      AppInfo(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
      AppInfo(bundleID: "com.apple.Notes", name: "Notes"),
      AppInfo(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
      AppInfo(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
    ]
    static let words = [
      "release", "build", "invoice", "deploy", "notch", "swift", "query", "token", "branch", "review",
      "привіт", "звіт", "рахунок", "Київ", "реліз", "збірка", "тест", "чернетка", "ґанок", "їжак",
    ]
    /// What a text goes on with after its first words, about 1.6 KB of them.
    static let filler = (0..<230).map { words[($0 * 7) % words.count] }.joined(separator: " ") + "\n"

    init(count: Int, images: Int, now: Date) {
      var random = SplitMix64(seed: UInt64(count))
      let folder = DataFolder.url.appending(path: "QA seed files", directoryHint: .isDirectory)
      referencedFiles = (0..<20).map { folder.appending(path: "\(Self.words[$0]) \($0).txt") }
      for index in 0..<count {
        let word = Self.words[Int(random.next() % UInt64(Self.words.count))]
        let copiedAt = now.addingTimeInterval(-Double(random.next() % 31_536_000))
        let content: PasteboardContent
        let isImage = index < images
        if isImage {
          content = .image(Data("seed \(index)".utf8))
        } else {
          switch random.next() % 20 {
          case 0..<13:
            // 20 B to 200 KB, evenly over the orders of magnitude.
            let size = Int(20 * pow(10_000, Double(random.next() % 1_000) / 1_000))
            let start = "#\(index) \(word) "
            let text = start + String(repeating: Self.filler, count: size / Self.filler.utf8.count + 1)
            content = .text(String(text.prefix(utf8Bytes: max(size, start.utf8.count))))
          case 13..<17:
            let path = word.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? word
            content = .link(URL(string: "https://example.com/\(path)/\(index)?q=\(index)")!)
          default:
            let file = index % 7 == 0
              ? folder.appending(path: "missing \(index).txt")
              : referencedFiles[index % referencedFiles.count]
            content = .files([file])
          }
        }
        var item = ClipboardItem(
          id: UUID(),
          content: .text(""),
          source: Self.apps[Int(random.next() % UInt64(Self.apps.count))],
          copiedAt: copiedAt,
          isPinned: index % 500 == 499,
          fingerprint: ClipboardCopy.fingerprint(of: content),
          byteSize: ClipboardCopy.byteSize(of: content)
        )
        switch content {
        case let .text(text): item.content = .text(text)
        case let .link(url): item.content = .link(url)
        case let .files(urls): item.content = .files(urls)
        case .image:
          item.content = .image(fileName: ClipboardFeature.imageFileName(copiedAt: copiedAt))
          item.byteSize = Self.png.count
        }
        items.append(item)
      }
    }

    /// The picture of every seeded image: a small grey PNG.
    static let png: Data = {
      let image = NSImage(size: CGSize(width: 64, height: 40), flipped: false) { rect in
        NSColor(white: 0.55, alpha: 1).setFill()
        rect.fill()
        return true
      }
      guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
      else { return Data() }
      return png
    }()
  }

  /// A small seeded random generator, so a seed gives the same items every time.
  struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
      state = seed
    }

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }
#endif
