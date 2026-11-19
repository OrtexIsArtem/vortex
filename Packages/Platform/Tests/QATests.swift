import AppKit
import ComposableArchitecture
import Foundation
import Testing
import VortexCore

@testable import VortexPlatform

/// The pure parts of QA mode: commands as they arrive, other processes' arguments, the run's MCP port, relaunch
/// arguments, the simulation's settings and scripts, redaction.
struct QACommandTests {
  @Test
  func aCommandIsItsNameItsArgumentsAndWhereTheReplyGoes() {
    let command = QACommand(userInfo: ["command": "entry", "reply": "/tmp/r.json", "kind": "hover", "leave": ""])
    #expect(command?.name == "entry")
    #expect(command?.reply == "/tmp/r.json")
    #expect(command?.arguments == ["kind": "hover", "leave": ""])
  }

  @Test
  func withoutANameThereIsNoCommand() {
    #expect(QACommand(userInfo: [:]) == nil)
    #expect(QACommand(userInfo: ["command": " "]) == nil)
    #expect(QACommand(userInfo: ["kind": "hover"]) == nil)
  }

  @Test
  func anEmptyReplyMeansNoReply() {
    #expect(QACommand(userInfo: ["command": "quit", "reply": ""])?.reply == nil)
    #expect(QACommand(userInfo: ["command": "quit"])?.reply == nil)
  }

  @Test
  func onlyStringsOfTheNotificationCount() {
    let info: [AnyHashable: Any] = ["command": "state", "path": "/tmp/s.json", "count": 3, 7: "seven"]
    #expect(QACommand.strings(info) == ["command": "state", "path": "/tmp/s.json"])
    #expect(QACommand.strings(nil) == [:])
  }

  @Test
  func theChannelIsTheRunsOwn() {
    #expect(QA.channel(for: "A") == "io.github.ortexisartem.vortex.qa.A")
  }
}

struct QAProcessesTests {
  func buffer(argumentCount: Int32, _ parts: [String], padding: Int = 3) -> [UInt8] {
    var bytes = withUnsafeBytes(of: argumentCount.littleEndian, Array.init)
    bytes += Array("/Applications/Vortex.app/Contents/MacOS/Vortex".utf8) + [0] + [UInt8](repeating: 0, count: padding)
    for part in parts {
      bytes += Array(part.utf8) + [0]
    }
    return bytes
  }

  @Test
  func readsTheArgumentsAndLeavesTheEnvironmentOut() {
    let bytes = buffer(argumentCount: 3, ["/path/Vortex", "--qa", "A", "HOME=/Users/someone", "PATH=/usr/bin"])
    #expect(QAProcesses.arguments(fromProcessArguments: bytes) == ["/path/Vortex", "--qa", "A"])
  }

  @Test
  func aShortBufferIsNothing() {
    #expect(QAProcesses.arguments(fromProcessArguments: []) == nil)
    #expect(QAProcesses.arguments(fromProcessArguments: [3, 0]) == nil)
    let cut = buffer(argumentCount: 3, ["/path/Vortex", "--qa"])
    #expect(QAProcesses.arguments(fromProcessArguments: cut) == nil)
  }

  @Test
  func readsThisProcess() {
    #expect(QAProcesses.arguments(of: getpid()) == ProcessInfo.processInfo.arguments)
  }

  @Test
  func plainVortexIsTheSameKindAsPlainVortexOutsideQA() {
    // The test runner is plain: so is itself.
    #expect(QA.isSameRun(pid: getpid()))
    #expect(!QA.isActive)
  }

  @Test
  func runsTakeOverOnlyFromTheSameRunWhateverTheCase() {
    let vortex = "/Applications/Vortex.app/Contents/MacOS/Vortex"
    let runA = QALaunch(arguments: [vortex, "--qa", "A"])
    // A QA run and the user's plain Vortex never stop each other.
    #expect(!QA.isSameRun(arguments: [vortex, "--qa", "A"], as: .none))
    #expect(!QA.isSameRun(arguments: [vortex], as: runA))
    // Another name is another run; the same name in another case is the same run, with the same folder.
    #expect(!QA.isSameRun(arguments: [vortex, "--qa", "B"], as: runA))
    #expect(QA.isSameRun(arguments: [vortex, "--qa", "a"], as: runA))
    #expect(QA.isSameRun(arguments: [vortex, "-AppleLanguages", "(uk)", "--qa", "A"], as: runA))
    #expect(QA.isSameRun(arguments: [vortex, "-NSDocumentRevisionsDebugMode", "YES"], as: .none))
  }

  @Test
  func onlyPlainVortexMayHaveAKeyWindow() {
    #expect(QA.allowsKeyWindows(for: .none))
    #expect(!QA.allowsKeyWindows(for: QALaunch(arguments: ["/x/Vortex", "--qa", "A"])))
    #expect(!QA.allowsKeyWindows(for: .invalid("--qa needs a name")))
    // Tests run as plain Vortex.
    #expect(QA.allowsKeyWindows)
  }
}

struct QAIsolationTests {
  let folder = FileManager.default.temporaryDirectory.appending(path: "vortex-qa-port-\(UUID().uuidString)")

  func settings() throws -> [String: Any] {
    let data = try Data(contentsOf: folder.appending(path: "secrets.json"))
    return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
  }

  @Test
  func aNewRunGetsAnEphemeralPortNeverTheUsers() throws {
    let port = try QAIsolation.seedServerPort(in: folder)
    #expect(QAIsolation.ports.contains(port))
    #expect(port != QAIsolation.userPort)
    #expect(try settings()["port"] as? Int == port)
    try FileManager.default.removeItem(at: folder)
  }

  @Test
  func theUsersPortIsReplacedAndTheRestKept() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(#"{"port": 47823, "hasConnected": true}"#.utf8).write(to: folder.appending(path: "secrets.json"))
    let port = try QAIsolation.seedServerPort(in: folder) { 50000 }
    #expect(port == 50000)
    #expect(try settings()["port"] as? Int == 50000)
    #expect(try settings()["hasConnected"] as? Bool == true)
    try FileManager.default.removeItem(at: folder)
  }

  @Test
  func aPortTheRunKeptStays() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data(#"{"port": 51234}"#.utf8).write(to: folder.appending(path: "secrets.json"))
    #expect(try QAIsolation.seedServerPort(in: folder) { 60000 } == 51234)
    try FileManager.default.removeItem(at: folder)
  }

  @Test
  func linksAndHardLinksLeadingOutOfTheRunsFolderAreFound() throws {
    let outside = FileManager.default.temporaryDirectory.appending(path: "vortex-qa-outside-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folder.appending(path: "Timer"), withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: folder.appending(path: "settings.json"))
    try Data().write(to: outside.appending(path: "vortex.sqlite"))
    // A link that stays inside is fine.
    try FileManager.default.createSymbolicLink(
      at: folder.appending(path: "Timer/run.json"),
      withDestinationURL: folder.appending(path: "settings.json")
    )
    #expect(QAIsolation.itemsLeadingOut(of: folder).isEmpty)
    // A link out, one out to a file that isn't there yet (SQLite would make it), and a hard link.
    try FileManager.default.createSymbolicLink(
      at: folder.appending(path: "vortex.sqlite"),
      withDestinationURL: outside.appending(path: "vortex.sqlite")
    )
    try FileManager.default.createSymbolicLink(atPath: folder.appending(path: "vortex.sqlite-wal").path, withDestinationPath: "../\(outside.lastPathComponent)/missing-wal")
    try FileManager.default.linkItem(at: outside.appending(path: "vortex.sqlite"), to: folder.appending(path: "shelf.json"))
    let found = Set(QAIsolation.itemsLeadingOut(of: folder).map { URL(fileURLWithPath: $0).lastPathComponent })
    #expect(found == ["vortex.sqlite", "vortex.sqlite-wal", "shelf.json"])
    try FileManager.default.removeItem(at: folder)
    try FileManager.default.removeItem(at: outside)
  }

  @Test
  func anUnreadableFileOrAPortOutsideTheRangeGetsANewOne() throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("not json".utf8).write(to: folder.appending(path: "secrets.json"))
    #expect(try QAIsolation.seedServerPort(in: folder) { 60001 } == 60001)
    try Data(#"{"port": 8080}"#.utf8).write(to: folder.appending(path: "secrets.json"))
    #expect(try QAIsolation.seedServerPort(in: folder) { 60002 } == 60002)
    try FileManager.default.removeItem(at: folder)
  }
}

@MainActor
struct QALifecycleTests {
  @Test
  func aRelaunchKeepsTheArguments() {
    let arguments = ["--qa", "A", "--qa-release", "-AppleLanguages", "(en)"]
    #expect(QALifecycle.relaunchArguments(arguments, language: nil) == arguments)
  }

  @Test
  func aLanguageChosenInSettingsReplacesTheLaunchOne() {
    #expect(
      QALifecycle.relaunchArguments(["--qa", "A", "-AppleLanguages", "(en)"], language: .ukrainian)
        == ["--qa", "A", "-AppleLanguages", "(uk)"]
    )
    #expect(QALifecycle.relaunchArguments(["--qa", "A"], language: .english) == ["--qa", "A", "-AppleLanguages", "(en)"])
    #expect(QALifecycle.relaunchArguments(["-AppleLanguages", "(uk)", "--qa", "A"], language: .system) == ["--qa", "A"])
  }
}

struct QASimulationTests {
  @Test
  func setChangesOnlyKnownKeysWithGoodValues() throws {
    var simulation = QASimulation()
    try simulation.set(["keyboardLockRefuses": "true", "launchAtLogin": "requiresApproval", "frontTitle": "", "chooseApp": "com.apple.Safari"])
    #expect(simulation.keyboardLockRefuses)
    #expect(simulation.keyboardLayout == "ansi")
    try simulation.set(["keyboardLayout": "iso"])
    #expect(simulation.keyboardLayout == "iso")
    #expect(simulation.launchAtLogin == "requiresApproval")
    #expect(simulation.frontTitle == nil)
    #expect(simulation.chooseApp == "com.apple.Safari")
    #expect(simulation.qrCode == "")
    try simulation.set(["qrCode": "https://example.com", "recognizedText": "live"])
    #expect(simulation.qrCode == "https://example.com" && simulation.recognizedText == "live")
    try simulation.set(["qrCode": ""])
    #expect(simulation.qrCode == "")
    try simulation.set(["readDelay": "1.5"])
    #expect(simulation.readDelay == 1.5)
    let delayed = simulation
    #expect(throws: QAError.self) { try simulation.set(["readDelay": "-1"]) }
    #expect(throws: QAError.self) { try simulation.set(["readDelay": "soon"]) }
    #expect(simulation == delayed)
    try simulation.set(["readDelay": "0"])

    let before = simulation
    #expect(throws: QAError.self) { try simulation.set(["keyboardLockRefuses": "yes"]) }
    // Gone: the simulated permissions (`perm`) are the one source of truth.
    for key in ["keyboardAccess", "screenAccess", "notificationsAllowed"] {
      #expect(throws: QAError.self) { try simulation.set([key: "true"]) }
    }
    #expect(throws: QAError.self) { try simulation.set(["screenAccess": "true", "volume": "11"]) }
    #expect(throws: QAError.self) { try simulation.set(["launchAtLogin": "maybe"]) }
    #expect(throws: QAError.self) { try simulation.set(["keyboardLayout": "dvorak"]) }
    #expect(simulation == before)
  }

  @Test
  func missingOrUnreadableKeysFallBackToTheirDefaults() throws {
    let data = Data(#"{"screenAccess": true, "launchAtLogin": 5, "commandRules": [{"match": "claude"}]}"#.utf8)
    let simulation = try JSONDecoder().decode(QASimulation.self, from: data)
    #expect(simulation.screenAccess)
    #expect(simulation.launchAtLogin == "disabled")
    #expect(!simulation.keyboardAccess)
    #expect(simulation.commandRules == [QASimulation.CommandRule(match: "claude", exitCode: 0)])
  }

  @Test
  func shellScriptsNeedATextAndAnExitCode() throws {
    let rule = try QASystem.rule(from: ["match": "command -v claude", "exit": "127", "stderr": "not found", "delay": "0.5"])
    #expect(rule == QASimulation.CommandRule(match: "command -v claude", exitCode: 127, stderr: "not found", delay: 0.5))
    #expect(try QASystem.rule(from: ["match": "x", "exit": "0", "echo": "true"]).echo)
    #expect(throws: QAError.self) { try QASystem.rule(from: ["exit": "1"]) }
    #expect(throws: QAError.self) { try QASystem.rule(from: ["match": "x"]) }
    #expect(throws: QAError.self) { try QASystem.rule(from: ["match": "x", "exit": "one"]) }
    #expect(throws: QAError.self) { try QASystem.rule(from: ["match": "x", "exit": "0", "delay": "-1"]) }
  }

  @Test
  func copiesAreTextLinksFilesOrImages() throws {
    #expect(try QASystem.copy(from: ["text": "hello"]).content == .text("hello"))
    #expect(try QASystem.copy(from: ["link": "https://example.com"]).content == .link(URL(string: "https://example.com")!))
    #expect(try QASystem.copy(from: ["file": "/tmp/a.png"]).content == .files([URL(fileURLWithPath: "/tmp/a.png")]))
    let concealed = try QASystem.copy(from: ["text": "secret", "concealed": "true", "source": "com.apple.Safari"])
    #expect(concealed.isConcealed)
    #expect(concealed.source?.bundleID == "com.apple.Safari")
    #expect(concealed.frontApps == ["com.apple.Safari"])
    #expect(throws: QAError.self) { try QASystem.copy(from: [:]) }
    #expect(throws: QAError.self) { try QASystem.copy(from: ["link": "not a link"]) }
    #expect(throws: QAError.self) { try QASystem.copy(from: ["image": "/Users/someone/Desktop/a.png"]) }
    #expect(throws: QAError.self) { try QASystem.copy(from: ["file": "/Users/someone/Desktop/a.pdf"]) }
  }

  @Test
  func windowFramesAreABundleIdAndRectangles() throws {
    let (bundleID, frames) = try QASystem.frames("com.apple.systempreferences:100,200,800,600;0,0,10.5,10")
    #expect(bundleID == "com.apple.systempreferences")
    #expect(frames == [CGRect(x: 100, y: 200, width: 800, height: 600), CGRect(x: 0, y: 0, width: 10.5, height: 10)])
    #expect(try QASystem.frames("com.apple.Safari:").frames.isEmpty)
    #expect(throws: QAError.self) { try QASystem.frames("com.apple.Safari") }
    #expect(throws: QAError.self) { try QASystem.frames(":1,2,3,4") }
    #expect(throws: QAError.self) { try QASystem.frames("x:1,2,3") }
    #expect(throws: QAError.self) { try QASystem.frames("x:1,2,0,4") }
  }
}

struct QALogTests {
  @Test
  func secretsAreTakenOut() {
    let secrets: Set<String> = ["0123456789abcdef", "pw"]
    let text = "claude mcp add --header \"Authorization: Bearer 0123456789abcdef\" pw"
    #expect(QALog.redact(text, secrets: secrets) == "claude mcp add --header \"Authorization: Bearer ••••\" pw")
  }

  @Test
  func aLongerSecretGoesBeforeAShorterOneInsideIt() {
    #expect(QALog.redact("abcdefgh", secrets: ["abcd", "abcdefgh"]) == "••••")
  }
}

struct ActiveAppClientTests {
  @Test
  func windowListFramesTurnIntoAppKitFrames() {
    let windows: [[String: Any]] = [
      [
        kCGWindowOwnerPID as String: pid_t(42),
        kCGWindowLayer as String: 0,
        kCGWindowBounds as String: ["X": 100, "Y": 50, "Width": 800, "Height": 600],
      ],
      // A menu of the same app, and a window of another app.
      [
        kCGWindowOwnerPID as String: pid_t(42),
        kCGWindowLayer as String: 101,
        kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 10, "Height": 10],
      ],
      [
        kCGWindowOwnerPID as String: pid_t(7),
        kCGWindowLayer as String: 0,
        kCGWindowBounds as String: ["X": 0, "Y": 0, "Width": 10, "Height": 10],
      ],
    ]
    let frames = ActiveAppClient.windowFrames(in: windows, pids: [42], mainDisplayHeight: 982)
    #expect(frames == [CGRect(x: 100, y: 982 - 650, width: 800, height: 600)])
  }
}

/// The simulated clients: nothing reaches past the run's folder. They share the simulation, so one at a time.
@Suite(.serialized)
struct QAClientsTests {
  @Test
  func everySystemClientIsSimulated() throws {
    // Every client Platform declares, by its DependencyValues name, must be set in `useQAClients`.
    let platform = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let clients = platform.appending(path: "Sources/Clients")
    var declared: Set<String> = []
    for file in try FileManager.default.contentsOfDirectory(at: clients, includingPropertiesForKeys: nil) {
      let source = try String(contentsOf: file, encoding: .utf8)
      for line in source.split(separator: "\n") where line.contains("public var") && line.contains("Client {") {
        let name = line.split(separator: " ").drop { $0 != "var" }.dropFirst().first.map { String($0.dropLast()) }
        if let name { declared.insert(name) }
      }
    }
    let qa = try String(contentsOf: platform.appending(path: "Sources/QA/QAClients.swift"), encoding: .utf8)
    #expect(declared.count >= 16)
    for name in declared.sorted() {
      #expect(qa.contains("      \(name) = .qa"), "\(name) is not simulated in QA mode")
    }
  }

  @Test
  func filesOutsideTheRunsFolderAreRefused() async throws {
    let files = FileClient.qa
    let outside = URL(fileURLWithPath: "/System/vortex-qa-test/file.txt")
    #expect(await files.info(outside) == nil)
    #expect(await files.contents(outside.deletingLastPathComponent()) == [])
    await #expect(throws: QAError.self) { try await files.write(Data("x".utf8), outside) }
    await #expect(throws: QAError.self) { _ = try await files.read(outside) }
    await files.remove(outside)
    let inside = FileManager.default.temporaryDirectory.appending(path: "vortex-qa-files-\(UUID().uuidString)/file.txt")
    try await files.write(Data("x".utf8), inside)
    #expect(try await files.read(inside) == Data("x".utf8))
    await files.remove(inside.deletingLastPathComponent())
    #expect(await files.info(inside) == nil)
  }

  @Test
  func theKeychainLivesInMemoryAndItsValuesNeverReachTheLog() async throws {
    let keychain = KeychainClient.qa
    try await keychain.save("io.github.ortexisartem.vortex.qa-test", "token", "s3cr3t-token-value", "label")
    #expect(try await keychain.read("io.github.ortexisartem.vortex.qa-test", "token") == "s3cr3t-token-value")
    #expect(await keychain.accounts("io.github.ortexisartem.vortex.qa-test") == ["token"])
    // Found by its own text: other suites write to the same log meanwhile.
    let event = "logged-\(UUID().uuidString)"
    QALog.record("test", event, ["text": "Bearer s3cr3t-token-value"])
    #expect(QALog.events.value.last { $0.event == event }?.detail["text"] == "Bearer ••••")
    await keychain.delete("io.github.ortexisartem.vortex.qa-test", "token")
    #expect(try await keychain.read("io.github.ortexisartem.vortex.qa-test", "token") == nil)
  }

  @Test
  func shortcutsArePressedByCommandOnlyForTheirListeners() async {
    let presses = HotkeyClient.qa.presses(Hotkey("qa-test-shortcut"))
    let count = LockIsolated(0)
    let listening = Task {
      for await _ in presses {
        count.withValue { $0 += 1 }
        if count.value == 2 { break }
      }
    }
    await Task.yield()
    #expect(await QA.pressHotkey("qa-test-other") == 0)
    #expect(await QA.pressHotkey("qa-test-shortcut") == 1)
    #expect(await QA.pressHotkey("qa-test-shortcut") == 1)
    await listening.value
    #expect(count.value == 2)
  }

  @Test
  func whatVortexWritesNeverComesBackAsACopyAndConcealedStaysHidden() async {
    let pasteboard = PasteboardClient.qa
    let copies = pasteboard.copies()
    let received = LockIsolated<[PasteboardCopy]>([])
    let listening = Task {
      for await copy in copies {
        received.withValue { $0.append(copy) }
        break
      }
    }
    await Task.yield()
    await pasteboard.write(.text("connect command"), true, nil)
    let dump = QASystem.shared.pasteboardDump() as? [String: Any]
    #expect(dump?["content"] as? String == "<concealed>")
    QASystem.shared.copy(PasteboardCopy(content: .text("from Safari")))
    await listening.value
    #expect(received.value.map(\.content) == [.text("from Safari")])
  }

  /// A copy Vortex makes for the user comes back as a copy, as the real pasteboard reads it: from the app it names
  /// (Vortex without one), a lone web address as a link, a secret hidden.
  @Test
  func aCopyForTheUserComesBackAsACopy() async {
    let pasteboard = PasteboardClient.qa
    let copies = pasteboard.copies()
    let received = LockIsolated<[PasteboardCopy]>([])
    let listening = Task {
      for await copy in copies {
        received.withValue { $0.append(copy) }
        if received.value.count == 3 { break }
      }
    }
    await Task.yield()
    await pasteboard.copy(.text("read off the screen"), false, "com.apple.TextEdit")
    let dump = QASystem.shared.pasteboardDump() as? [String: Any]
    #expect(dump?["content"] as? String == "text: read off the screen")
    #expect(dump?["source"] as? String == "com.apple.TextEdit")
    await pasteboard.copy(.text(" https://example.com/docs?id=7 "), false, nil)
    await pasteboard.copy(.text("WIFI:S:Office;T:WPA;P:hunter22;;"), true, "com.apple.Safari")
    #expect((QASystem.shared.pasteboardDump() as? [String: Any])?["content"] as? String == "<concealed>")
    await listening.value
    let copies3 = received.value
    #expect(copies3.map(\.content) == [
      .text("read off the screen"), .link(URL(string: "https://example.com/docs?id=7")!), .text("WIFI:S:Office;T:WPA;P:hunter22;;"),
    ])
    #expect(copies3.map(\.source?.bundleID) == ["com.apple.TextEdit", PasteboardFormat.ownBundleID, "com.apple.Safari"])
    #expect(copies3[0].source?.name == "TextEdit")
    #expect(copies3.map(\.isConcealed) == [false, false, true])
    #expect(copies3[0].frontApps == ["com.apple.TextEdit"])
  }

  /// A read can be made to take its time, so Esc and other things can come while it runs; it stops when cancelled.
  @Test
  func aReadTakesTheSimulatedDelay() async throws {
    defer { QASimulation.update { $0 = QASimulation() } }
    let recognition = TextRecognitionClient.qa
    let picture = QRCodeReadingTests.image(text: "Release notes")
    QASimulation.update { $0.readDelay = 0.3 }
    let start = ContinuousClock.now
    #expect(try await recognition.recognize(picture) == "QA text")
    #expect(try await recognition.readQRCode(picture) == nil)
    #expect(try await recognition.recognizeAsWritten(picture) == "QA text")
    #expect(ContinuousClock.now - start >= .milliseconds(850))
    let cancelled = Task { try await recognition.recognize(picture) }
    cancelled.cancel()
    await #expect(throws: CancellationError.self) { try await cancelled.value }
    let cancelledAsWritten = Task { try await recognition.recognizeAsWritten(picture) }
    cancelledAsWritten.cancel()
    await #expect(throws: CancellationError.self) { try await cancelledAsWritten.value }
  }

  @Test
  func theAppInFrontMovesByCommand() async throws {
    let apps = ActiveAppClient.qa
    let activations = apps.activations()
    let first = Task { await activations.first { _ in true } }
    await Task.yield()
    try await QASystem.shared.app(["activate": "com.apple.systempreferences", "frames": "com.apple.systempreferences:10,20,800,600"])
    #expect(await first.value == "com.apple.systempreferences")
    #expect(await apps.frontmost() == "com.apple.systempreferences")
    #expect(await apps.windowFrames("com.apple.systempreferences") == [CGRect(x: 10, y: 20, width: 800, height: 600)])
    try await QASystem.shared.app(["quit": "com.apple.systempreferences"])
    #expect(await apps.frontmost() == "com.apple.finder")
    #expect(await apps.windowFrames("com.apple.systempreferences") == [])
    await #expect(throws: QAError.self) { try await QASystem.shared.app(["launch": "x"]) }
    QASimulation.update { $0.frontApp = QASimulation().frontApp }
  }

  @Test
  func searchReadsTheSimulatedTextOrWithLiveTheImageItself() async throws {
    defer { QASimulation.update { $0 = QASimulation() } }
    let recognition = TextRecognitionClient.qa
    let notAnImage = Data("not an image".utf8)
    QASimulation.update { $0.recognizedText = "mcp server" }
    #expect(try await recognition.recognizeForSearch(notAnImage) == "mcp server")
    // Only the size is logged, never the text.
    #expect(QALog.events.value.last { $0.event == "recognizeForSearch" }?.detail == ["bytes": "\(notAnImage.count)"])

    // `live` reads with Apple Vision, as plain Vortex does: a real image's text, and anything else throws.
    QASimulation.update { $0.recognizedText = "live" }
    let png = TextRecognitionForSearchTests.png(width: 800, height: 200, size: 48, lines: [("release notes", 48)])
    #expect(try await recognition.recognizeForSearch(png).lowercased().contains("release notes"))
    await #expect(throws: (any Error).self) { try await recognition.recognizeForSearch(notAnImage) }
  }

  /// A picture's text is the simulated text, or with `live` what Apple Vision reads in the picture itself.
  @Test
  func recognitionReadsTheSimulatedTextOrWithLiveThePictureItself() async throws {
    defer { QASimulation.update { $0 = QASimulation() } }
    let recognition = TextRecognitionClient.qa
    let picture = QRCodeReadingTests.image(text: "Release notes")
    QASimulation.update { $0.recognizedText = "mcp server" }
    #expect(try await recognition.recognize(picture) == "mcp server")
    #expect(try await recognition.recognizeAsWritten(picture) == "mcp server")
    // Only the size is logged, never the text.
    #expect(QALog.events.value.last { $0.event == "recognizeAsWritten" }?.detail == ["size": "450×210"])
    QASimulation.update { $0.recognizedText = "live" }
    #expect(try await recognition.recognize(picture).lowercased().contains("release notes"))
    #expect(try await recognition.recognizeAsWritten(picture).lowercased().contains("release notes"))
  }

  /// No QR code by default; the simulated payload on any picture; with `live` what Apple Vision finds in the picture.
  /// Only sizes are logged, never the payload.
  @Test
  func qrCodesAreTheSimulatedPayloadOrWithLiveThePicturesOwn() async throws {
    defer { QASimulation.update { $0 = QASimulation() } }
    let recognition = TextRecognitionClient.qa
    let plain = QRCodeReadingTests.image(text: "No code here")
    #expect(try await recognition.readQRCode(plain) == nil)
    QASimulation.update { $0.qrCode = "https://example.com/menu" }
    #expect(try await recognition.readQRCode(plain) == "https://example.com/menu")
    #expect(QALog.events.value.last { $0.event == "readQRCode" }?.detail == ["size": "450×210"])
    QASimulation.update { $0.qrCode = "live" }
    #expect(try await recognition.readQRCode(plain) == nil)
    #expect(try await recognition.readQRCode(QRCodeReadingTests.image(codes: [("Table 12", 60)])) == "Table 12")
  }

  @Test
  func theKeyboardLockIsNeverATap() async {
    let lock = KeyboardLockClient.qa
    QAPermissions.simulated.set(.accessibility, to: .denied)
    #expect(await !lock.lock())
    QAPermissions.simulated.set(.accessibility, to: .granted)
    #expect(await lock.lock())
    QASimulation.update { $0.keyboardLockRefuses = true }
    #expect(await !lock.lock())
    QASimulation.update { $0 = QASimulation() }
  }

  /// Keys come only from `keyboard key=`, and the layout from the simulation.
  @Test
  @MainActor
  func lockedKeysArePressedByCommandAndTheLayoutIsSimulated() async {
    let lock = KeyboardLockClient.qa
    #expect(lock.layout() == .ansi)
    QASimulation.update { $0.keyboardLayout = "iso" }
    #expect(lock.layout() == .iso)
    QASimulation.update { $0 = QASimulation() }

    let presses = await lock.presses()
    let received = Task {
      var keys: [KeyboardKey] = []
      for await key in presses.prefix(2) { keys.append(key) }
      return keys
    }
    #expect(QA.pressKey(.a) == 1)
    #expect(QA.pressKey(.f1) == 1)
    #expect(await received.value == [.a, .f1])

    // Unlocked, the keys end and nobody listens.
    let ended = await lock.presses()
    await lock.unlock()
    var afterUnlock: [KeyboardKey] = []
    for await key in ended { afterUnlock.append(key) }
    #expect(afterUnlock.isEmpty)
    #expect(QA.pressKey(.a) == 0)
  }
}
