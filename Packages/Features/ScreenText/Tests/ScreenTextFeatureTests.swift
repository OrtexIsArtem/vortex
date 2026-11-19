import ComposableArchitecture
import CoreGraphics
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureScreenText

/// A white screen of 40 × 20 points at 2 pixels per point.
func testScreenshot() -> Screenshot {
  let context = CGContext(
    data: nil, width: 80, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.setFillColor(CGColor(gray: 1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
  return Screenshot(image: ScreenImage(cgImage: context.makeImage()!, scale: 2), notch: nil, displayID: 1)
}

/// What the pasteboard was given for the user.
struct Copied: Equatable {
  var content: PasteboardContent
  var isConcealed: Bool
  var sourceApp: String?
}

@MainActor
struct ScreenTextFeatureTests {
  let clock = TestClock()
  let now = LockIsolated(Date(timeIntervalSinceReferenceDate: 800_000_000))
  let copies = LockIsolated<[Copied]>([])
  /// The pages Screen Text asked the shell for.
  let pages = LockIsolated<[Permission]>([])
  let screenshots = LockIsolated(0)
  /// The sizes of the pictures read, in points: what was framed.
  let readSizes = LockIsolated<[CGSize]>([])
  let recognized = LockIsolated("Fix the pay button\nsecond line")
  let qrCode = LockIsolated<String?>(nil)
  let refreshes = LockIsolated(0)
  let relaunches = LockIsolated(0)
  /// macOS as the tests set it: Screen Recording granted unless a test says otherwise.
  let simulated: SimulatedPermissions = {
    let simulated = SimulatedPermissions()
    simulated.set(.screenRecording, to: .granted)
    return simulated
  }()

  /// The shell has read the statuses, Screen Recording granted, and nothing shows in the notch.
  init() {
    readStatuses(simulated.statuses)
    @Shared(.appBlocked) var appBlocked
    $appBlocked.withLock { $0 = false }
    @Shared(.notchIndicators) var indicators
    $indicators.withLock { $0 = [:] }
  }

  func makeStore(_ state: ScreenTextFeature.State = ScreenTextFeature.State()) -> TestStoreOf<ScreenTextFeature> {
    let store = TestStore(initialState: state) {
      ScreenTextFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.date = DateGenerator { [now] in now.value }
      $0.uuid = .incrementing
      $0.activeAppClient.frontmost = { "ru.keepcoder.Telegram" }
      $0.screenCaptureClient.captureScreenUnderPointer = { [screenshots] in
        screenshots.withValue { $0 += 1 }
        return testScreenshot()
      }
      $0.textRecognitionClient.readQRCode = { [qrCode, readSizes] image in
        readSizes.withValue { $0.append(image.size) }
        return qrCode.value
      }
      $0.textRecognitionClient.recognize = { [recognized] _ in recognized.value }
      $0.pasteboardClient.copy = { [copies] content, isConcealed, source in
        copies.withValue { $0.append(Copied(content: content, isConcealed: isConcealed, sourceApp: source)) }
      }
      $0.pasteboardClient.write = { _, _, _ in Issue.record("Screen Text copies for the user, never as Vortex's own write") }
      $0.permissionPage.open = { [pages] permission in pages.withValue { $0.append(permission) } }
      $0.permissionsClient = .simulated(simulated)
      $0.permissionsClient.refresh = { [simulated, refreshes] in
        refreshes.withValue { $0 += 1 }
        simulated.refresh()
      }
      $0.systemClient.relaunch = { [relaunches] in relaunches.withValue { $0 += 1 } }
    }
    store.exhaustivity = .off
    return store
  }

  /// Sets what the shell read from the simulated macOS, as `@Shared(.permissionStatuses)` (nil: no read yet).
  func readStatuses(_ statuses: [Permission: PermissionStatus]?) {
    @Shared(.permissionStatuses) var shared
    $shared.withLock { $0 = statuses ?? [:] }
  }

  /// What the notch shows of Screen Text now.
  var indicator: NotchIndicator? {
    @Shared(.notchIndicators) var indicators
    return indicators[ScreenTextFeature.id]
  }

  /// Starts the feature and freezes the screen, as the shortcut or the utility action does.
  func freeze(_ store: TestStoreOf<ScreenTextFeature>) async {
    await store.send(.captureRequested)
    await store.receive(\.captureTaken)
    #expect(store.state.capture != nil)
  }

  /// Frames an area and lets go, then waits for what was read.
  func frame(_ store: TestStoreOf<ScreenTextFeature>, _ rect: CGRect = CGRect(x: 2, y: 2, width: 20, height: 10)) async {
    await store.send(.frameChanged(rect))
    await store.send(.frameEnded(rect))
    await store.receive(\.read)
  }

  // MARK: - What is copied

  @Test
  func aFrameOfTextIsCopiedLineByLineFromTheAppInFrontAndTheNotchCountsTheLines() async {
    let store = makeStore()
    await store.send(.start)
    await freeze(store)
    #expect(store.state.capture?.frontApp == "ru.keepcoder.Telegram")
    await store.send(.frameChanged(CGRect(x: 30, y: 15, width: -20, height: -10)))
    #expect(store.state.capture?.frame == CGRect(x: 30, y: 15, width: -20, height: -10))
    await store.send(.frameEnded(CGRect(x: 30, y: 15, width: -20, height: -10)))
    #expect(store.state.phase.isReading)
    await store.receive(\.read)
    #expect(store.state.phase == .idle)
    // Only the framed part is read, the frame drawn backwards as well.
    #expect(readSizes.value == [CGSize(width: 20, height: 10)])
    #expect(copies.value == [Copied(content: .text("Fix the pay button\nsecond line"), isConcealed: false, sourceApp: "ru.keepcoder.Telegram")])
    #expect(store.state.message == .copiedLines(2))
    #expect(indicator?.leading.count == 1 && indicator?.trailing.count == 1)

    // About 1.5 s, then the notch is as it was.
    await clock.advance(by: .milliseconds(1_499))
    #expect(indicator != nil)
    await clock.advance(by: .milliseconds(1))
    await store.receive(\.messageExpired)
    #expect(store.state.message == nil)
    #expect(indicator == nil)
    await store.send(.stop)
  }

  /// Blank lines and spaces around them go; one line is one line.
  @Test
  func blankLinesAreLeftOutAndOneLineIsCounted() async {
    recognized.setValue("  Only line  \n\n   \n")
    let store = makeStore()
    await store.send(.start)
    await freeze(store)
    await frame(store)
    #expect(copies.value.map(\.content) == [.text("Only line")])
    #expect(store.state.message == .copiedLines(1))
    await store.send(.stop)
  }

  /// A QR code comes first: a link is copied as the code spells it, and the notch names its host.
  @Test
  func aQRCodeWithALinkIsCopiedAsItIsAndTheNotchNamesTheHost() async {
    qrCode.setValue("HTTPS://www.Example.com:8443/docs?id=7")
    recognized.setValue("Scan to open")
    let store = makeStore()
    await store.send(.start)
    await freeze(store)
    await frame(store)
    #expect(copies.value == [Copied(content: .text("HTTPS://www.Example.com:8443/docs?id=7"), isConcealed: false, sourceApp: "ru.keepcoder.Telegram")])
    #expect(store.state.message == .copiedLink(host: "example.com"))
    await store.send(.stop)
  }

  /// Anything else in a QR code is copied as text; a Wi-Fi password or a one-time code's secret is copied hidden from
  /// clipboard histories, and the notch never shows it.
  @Test
  func aQRCodeWithOtherContentIsCopiedAndASecretOneHidden() async {
    let store = makeStore()
    await store.send(.start)
    for (payload, isSecret) in [
      ("BEGIN:VCARD\nFN:Artem\nEND:VCARD", false),
      ("example.com", false),
      ("WIFI:S:Office;T:WPA;P:hunter22;;", true),
      ("otpauth://totp/Vortex:me?secret=JBSWY3DPEHPK3PXP", true),
    ] {
      qrCode.setValue(payload)
      await freeze(store)
      await frame(store)
      #expect(copies.value.last == Copied(content: .text(payload), isConcealed: isSecret, sourceApp: "ru.keepcoder.Telegram"))
      #expect(store.state.message == .copiedCode)
    }
    await store.send(.stop)
  }

  /// Nothing found: the notch says so and the pasteboard stays as it was.
  @Test
  func nothingFoundLeavesThePasteboardAlone() async {
    recognized.setValue(" \n ")
    let store = makeStore()
    await store.send(.start)
    await freeze(store)
    await frame(store)
    #expect(copies.value.isEmpty)
    #expect(store.state.message == .nothingFound)
    #expect(indicator?.trailing.isEmpty == true)
    await clock.advance(by: .milliseconds(1_500))
    await store.receive(\.messageExpired)
    #expect(indicator == nil)
    await store.send(.stop)
  }

  /// A new message takes the place of the one showing and gets its own time.
  @Test
  func aNewMessageReplacesTheOneShowingWithItsOwnTime() async {
    let store = makeStore()
    await store.send(.start)
    await freeze(store)
    await frame(store)
    #expect(store.state.lastMessage?.shownAt == now.value)
    await clock.advance(by: .milliseconds(800))
    now.withValue { $0 += 0.8 }
    recognized.setValue("")
    await freeze(store)
    await frame(store)
    #expect(store.state.message == .nothingFound)
    await clock.advance(by: .milliseconds(1_000))
    #expect(store.state.message == .nothingFound)
    await clock.advance(by: .milliseconds(500))
    await store.receive(\.messageExpired)
    #expect(store.state.message == nil)
    #expect(store.state.lastMessage == ShownMessage(message: .nothingFound, shownAt: now.value, hiddenAt: now.value))
    await store.send(.stop)
  }

  /// The message shows over Timer's and the shelf's ears, but not over Keys' waiting approval.
  @Test
  func theMessageOutranksTimerAndShelfButNotKeys() {
    let indicator = ScreenTextFeature.indicator(.copiedLines(2))
    #expect(indicator.priority > 10 && indicator.priority < 20)
  }

  /// The host the notch names: without "www.", in lower case, and cut in the middle past 24 characters.
  @Test
  func theHostIsTheCodesOwnAndShortenedForTheNotch() {
    #expect(ScreenTextFeature.webHost("https://example.com/docs?id=7") == "example.com")
    #expect(ScreenTextFeature.webHost("HTTPS://EXAMPLE.COM/ABC") == "example.com")
    #expect(ScreenTextFeature.webHost("https://user:pass@приклад.укр:443/шлях") == "приклад.укр")
    #expect(ScreenTextFeature.webHost("http://[::1]:8080/") == "[::1]")
    #expect(ScreenTextFeature.webHost("example.com") == nil)
    #expect(ScreenTextFeature.webHost("mailto:team@example.com") == nil)
    #expect(ScreenTextFeature.webHost("otpauth://totp/Vortex:me?secret=X") == nil)
    #expect(ScreenTextFeature.webHost("https:///nothing") == nil)
    #expect(ScreenTextFeature.webHost("https://example.com and more") == nil)
    #expect(ScreenTextFeature.shownHost("www.example.com") == "example.com")
    let long = ScreenTextFeature.shownHost("a-very-long-subdomain.with-many-parts.example-company.co.uk")
    #expect(long.count == 24 && long.hasPrefix("a-very-long") && long.hasSuffix("mpany.co.uk") && long.contains("…"))
  }

  // MARK: - Esc and small frames

  /// Esc before the drag, during it and while the frame is read: the frozen screen goes, nothing is copied or said.
  @Test
  func escCancelsAtEveryStep() async {
    let store = makeStore()
    await store.send(.start)
    await freeze(store)
    await store.send(.cancelTapped)
    #expect(store.state.phase == .idle)

    await freeze(store)
    await store.send(.frameChanged(CGRect(x: 2, y: 2, width: 20, height: 10)))
    await store.send(.cancelTapped)
    #expect(store.state.phase == .idle)
    // The mouse let go after Esc: nothing to read.
    await store.send(.frameEnded(CGRect(x: 2, y: 2, width: 20, height: 10)))
    #expect(readSizes.value.isEmpty)

    // A read that waits until it is let go.
    let reads = AsyncStream.makeStream(of: Void.self)
    store.dependencies.textRecognitionClient.readQRCode = { _ in
      for await _ in reads.stream { break }
      return "https://example.com"
    }
    await freeze(store)
    await store.send(.frameEnded(CGRect(x: 2, y: 2, width: 20, height: 10)))
    #expect(store.state.phase.isReading)
    await store.send(.cancelTapped)
    #expect(store.state.phase == .idle)
    reads.continuation.yield()
    await store.finish()
    #expect(copies.value.isEmpty)
    #expect(store.state.message == nil)
    #expect(indicator == nil)
    await store.send(.stop)
  }

  /// A frame of a few points, as a click makes, ends the capture quietly: nothing read, said or copied.
  @Test
  func aTinyFrameCancelsQuietly() async {
    let store = makeStore()
    await store.send(.start)
    for tiny in [CGRect(x: 5, y: 5, width: 0, height: 0), CGRect(x: 5, y: 5, width: 7, height: 30), CGRect(x: 5, y: 5, width: 30, height: 7)] {
      await freeze(store)
      await store.send(.frameEnded(tiny))
      #expect(store.state.phase == .idle)
    }
    // A frame off the screen frames nothing either.
    await freeze(store)
    await store.send(.frameEnded(CGRect(x: 50, y: 5, width: 20, height: 10)))
    #expect(store.state.phase == .idle)
    await store.finish()
    #expect(readSizes.value.isEmpty && copies.value.isEmpty && store.state.message == nil)
    await store.send(.stop)
  }

  /// A press while the screen is being taken, framed or read does nothing.
  @Test
  func aPressWhileCapturingDoesNothing() async {
    let store = makeStore()
    await store.send(.start)
    await freeze(store)
    await store.send(.captureRequested)
    await store.send(.frameEnded(CGRect(x: 2, y: 2, width: 20, height: 10)))
    await store.receive(\.read)
    #expect(screenshots.value == 1)
    await store.send(.stop)
  }

  /// A capture that can't take the screen, as while another capture's frozen screen shows, ends quietly.
  @Test
  func aRefusedCaptureEndsQuietly() async {
    let store = makeStore()
    store.dependencies.screenCaptureClient.captureScreenUnderPointer = { throw ScreenCaptureError.frozenScreenShown }
    await store.send(.start)
    await store.send(.captureRequested)
    await store.receive(\.captureFailed)
    #expect(store.state.phase == .idle)
    await store.send(.stop)
  }

  // MARK: - Starting and stopping

  /// Stopping, as removing the feature does, ends a capture and takes the message away, so none comes back later.
  @Test
  func stoppingEndsTheCaptureAndTakesTheMessageAway() async {
    let store = makeStore()
    await store.send(.start)
    await freeze(store)
    await frame(store)
    #expect(indicator != nil)
    await freeze(store)
    await store.send(.stop)
    #expect(store.state.phase == .idle)
    #expect(store.state.message == nil)
    #expect(indicator == nil)
    await store.send(.start)
    await clock.advance(by: .seconds(2))
    #expect(indicator == nil)
    await store.send(.captureRequested)
    #expect(store.state.isEnabled)
    await store.send(.stop)
  }

  /// A feature that doesn't run captures nothing.
  @Test
  func nothingIsCapturedWhileItDoesntRun() async {
    let store = makeStore()
    await store.send(.captureRequested)
    await store.finish()
    #expect(screenshots.value == 0)
  }

  // MARK: - Permissions

  /// Screen Recording off, or granted only from the next launch: the shell's page, never macOS's prompt, nothing taken.
  @Test
  func withScreenRecordingOffItOpensThePageAndTakesNothing() async {
    let store = makeStore()
    await store.send(.start)
    for status in [PermissionStatus.notGranted, .grantedAfterRestart] {
      readStatuses([.screenRecording: status])
      await store.send(.captureRequested).finish()
    }
    #expect(pages.value == [.screenRecording, .screenRecording])
    #expect(screenshots.value == 0)
    #expect(store.state.phase == .idle)
    #expect(simulated.state.events.isEmpty)
    await store.send(.stop)
  }

  /// While Vortex is blocked, a press opens the page, and the shell shows its blocking page.
  @Test
  func whileBlockedAPressOpensThePage() async {
    @Shared(.appBlocked) var appBlocked
    $appBlocked.withLock { $0 = true }
    let store = makeStore()
    await store.send(.start)
    await store.send(.captureRequested).finish()
    #expect(pages.value == [.screenRecording])
    #expect(screenshots.value == 0)
    await store.send(.stop)
  }

  /// Before the shell's first read a press waits for it, then decides.
  @Test
  func beforeTheFirstReadAPressWaitsForIt() async {
    readStatuses(nil)
    let store = makeStore()
    await store.send(.start)
    await store.send(.captureRequested)
    #expect(screenshots.value == 0)
    readStatuses(simulated.statuses)
    await store.receive(\.captureRequested)
    await store.receive(\.captureTaken)
    #expect(screenshots.value == 1)
    #expect(pages.value.isEmpty)
    await store.send(.stop)
  }

  /// The settings: "Turn on" opens the page, "Restart Vortex" relaunches, and the section reads the statuses again.
  @Test
  func theSettingsRowOpensThePageRestartsAndReadsAgain() async {
    let store = makeStore()
    await store.send(.settingsShown).finish()
    #expect(refreshes.value == 1)
    await store.send(.turnOnTapped(.screenRecording)).finish()
    #expect(pages.value == [.screenRecording])
    await store.send(.restartTapped).finish()
    #expect(relaunches.value == 1)
    #expect(simulated.state.events.isEmpty)
  }
}
