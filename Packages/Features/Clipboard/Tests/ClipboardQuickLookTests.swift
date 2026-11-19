import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// The eye shows an item in Quick Look: an image as its PNG, files as they are, a text or a link whole, through a text
/// file in Vortex's temporary folder. Never a secret.
extension ClipboardFeatureTests {
  /// A loaded history of these items, watching nothing: what Quick Look is asked for is all its effects do.
  func quickLookStore(_ items: [ClipboardItem], unavailable: Set<ClipboardItem.ID> = []) -> TestStoreOf<ClipboardFeature> {
    var state = ClipboardFeature.State()
    state.items = IdentifiedArray(uniqueElements: items)
    state.isLoaded = true
    state.unavailable = unavailable
    return makeStore(state)
  }

  func text(in file: URL) -> String? {
    fileContents.value[file].map { String(decoding: $0, as: UTF8.self) }
  }

  @Test
  func theEyeShowsAnImageAsItsPNGAndFilesAsTheyAre() async throws {
    let image = ClipboardItem(
      id: uuid(1), content: .image(fileName: "Image.png"), source: Self.terminal, copiedAt: now.value, fingerprint: "image:1"
    )
    let ipa = URL(fileURLWithPath: "/tmp/a.ipa")
    let apk = URL(fileURLWithPath: "/tmp/b.apk")
    let files = ClipboardItem(
      id: uuid(2), content: .files([ipa, apk]), source: Self.terminal, copiedAt: now.value, fingerprint: "files:2"
    )
    let store = quickLookStore([image, files])

    await store.send(.quickLookTapped(image.id)) { $0.hasShownQuickLook = true }
    await store.finish()
    await store.send(.quickLookTapped(files.id))
    await store.finish()
    let png = try #require(image.imageURL)
    #expect(quickLooked.value == [[png], [ipa, apk]])
    // They are shown where they are: nothing is written for them.
    #expect(savedFiles.value.isEmpty)
  }

  @Test
  func aTextShowsWholeThroughATextFileInVortexsTemporaryFolder() async throws {
    // Longer than memory keeps of a saved text: the whole of it is in the database only.
    let whole = "SELECT * FROM orders\n" + String(repeating: "Київ, ґанок — 😀 ", count: 400)
    var long = item(whole, id: 1, copiedAt: now.value)
    try saveRows([long])
    long.content = .text(try #require(ClipboardItem.preview(of: whole)))
    long.isTruncated = true
    let short = item("not a secret", id: 2, copiedAt: now.value)
    let store = quickLookStore([long, short])

    await store.send(.quickLookTapped(long.id)) { $0.hasShownQuickLook = true }
    await store.finish()
    let file = try #require(quickLooked.value.last?.first)
    #expect(quickLooked.value == [[file]])
    #expect(file.pathExtension == "txt")
    #expect(file.path.hasPrefix(ClipboardItem.quickLookFolder.path + "/"))
    #expect(text(in: file) == whole)

    await store.send(.quickLookTapped(short.id))
    await store.finish()
    let shortFile = try #require(quickLooked.value.last?.first)
    #expect(shortFile != file)
    #expect(text(in: shortFile) == "not a secret")
  }

  @Test
  func aLongTextReadForADragIsShownFromMemory() async throws {
    let whole = String(repeating: "release notes ", count: 400)
    var long = item(whole, id: 1, copiedAt: now.value)
    long.content = .text(try #require(ClipboardItem.preview(of: whole)))
    long.isTruncated = true
    var state = ClipboardFeature.State()
    state.items = [long]
    state.isLoaded = true
    // The pointer came over its card: its whole text was read, and no row is needed.
    state.wholeText = ClipboardFeature.WholeText(id: long.id, text: whole)
    let store = makeStore(state)

    await store.send(.quickLookTapped(long.id)) { $0.hasShownQuickLook = true }
    await store.finish()
    let file = try #require(quickLooked.value.first?.first)
    #expect(text(in: file) == whole)
  }

  @Test
  func aLinkShowsItsAddressAsItsCardReadsIt() async throws {
    let address = URL(string: "https://uk.wikipedia.org/wiki/%D0%9A%D0%B8%D1%97%D0%B2?q=a%20b")!
    let link = ClipboardItem(
      id: uuid(1), content: .link(address), source: Self.terminal, copiedAt: now.value,
      fingerprint: ClipboardCopy.fingerprint(of: .link(address))
    )
    let store = quickLookStore([link])

    await store.send(.quickLookTapped(link.id)) { $0.hasShownQuickLook = true }
    await store.finish()
    let file = try #require(quickLooked.value.first?.first)
    #expect(text(in: file) == "https://uk.wikipedia.org/wiki/Київ?q=a%20b")
  }

  /// The eye only shows Quick Look: of any kind, an item it shows isn't copied, so it doesn't go to the top or show
  /// "Copied".
  @Test
  func theEyeNeverCopiesAnItem() async throws {
    let text = item("SELECT 1", id: 1, copiedAt: now.value)
    let link = ClipboardItem(
      id: uuid(2), content: .link(URL(string: "https://example.com")!), source: Self.terminal, copiedAt: now.value - 1,
      fingerprint: "link:2"
    )
    let image = ClipboardItem(
      id: uuid(3), content: .image(fileName: "Image.png"), source: Self.terminal, copiedAt: now.value - 2, fingerprint: "image:3"
    )
    let files = ClipboardItem(
      id: uuid(4), content: .files([URL(fileURLWithPath: "/tmp/a.ipa")]), source: Self.terminal, copiedAt: now.value - 3,
      fingerprint: "files:4"
    )
    let store = quickLookStore([text, link, image, files])

    // The oldest first: a copy would take each to the top.
    await store.send(.quickLookTapped(files.id)) { $0.hasShownQuickLook = true }
    for item in [image, link, text] {
      await store.send(.quickLookTapped(item.id))
    }
    await store.finish()
    #expect(quickLooked.value.count == 4)
    #expect(written.value.isEmpty)
    #expect(store.state.items.map(\.id) == [text, link, image, files].map(\.id))
    #expect(store.state.justCopied == nil)
  }

  @Test
  func theEyeOfTheSameItemAgainAsksForTheSameFileWhichClosesQuickLook() async throws {
    let short = item("SELECT 1", id: 1, copiedAt: now.value)
    let store = quickLookStore([short])

    await store.send(.quickLookTapped(short.id)) { $0.hasShownQuickLook = true }
    await store.finish()
    await store.send(.quickLookTapped(short.id))
    await store.finish()
    let file = try #require(quickLooked.value.first?.first)
    // `QuickLookClient.toggle` closes the panel when it already shows these files.
    #expect(quickLooked.value == [[file], [file]])
  }

  @Test
  func aTextFileIsNamedLikeACopiedImage() throws {
    let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 14, minute: 3, second: 12)))
    let text = ClipboardItem(id: uuid(1), content: .text("a"), source: nil, copiedAt: date, fingerprint: "text:1")
    let link = ClipboardItem(
      id: uuid(2), content: .link(URL(string: "https://example.com")!), source: nil, copiedAt: date, fingerprint: "link:2"
    )
    #expect(text.quickLookTextURL?.lastPathComponent == "Text 2026-10-04 at 14.03.12.txt")
    #expect(link.quickLookTextURL?.lastPathComponent == "Link 2026-10-04 at 14.03.12.txt")
    // One folder per item, so two copied in the same second never share a file.
    #expect(text.quickLookTextURL?.deletingLastPathComponent().lastPathComponent == uuid(1).uuidString)
    let image = ClipboardItem(id: uuid(3), content: .image(fileName: "Image.png"), source: nil, copiedAt: date, fingerprint: "image:3")
    #expect(image.quickLookTextURL == nil)
  }

  @Test
  func secretsAndItemsNotFoundHaveNoEye() async throws {
    var secret = item("hunter2", id: 1, copiedAt: now.value)
    secret.isConcealed = true
    let gone = ClipboardItem(
      id: uuid(2), content: .files([URL(fileURLWithPath: "/tmp/gone.zip")]), source: Self.terminal, copiedAt: now.value,
      fingerprint: "files:2"
    )
    let link = URL(string: "https://example.com/reset?token=abc")!
    let kinds: [ClipboardItem.Content] = [.text("a"), .link(link), .image(fileName: "Image.png"), .files([link])]
    for content in kinds {
      var kind = ClipboardItem(id: uuid(9), content: content, source: nil, copiedAt: now.value, fingerprint: "x")
      #expect(kind.opensInQuickLook(isUnavailable: false))
      #expect(!kind.opensInQuickLook(isUnavailable: true))
      kind.isConcealed = true
      #expect(!kind.opensInQuickLook(isUnavailable: false))
    }
    let store = quickLookStore([secret, gone], unavailable: [gone.id])

    // Shown or hidden, a secret never goes to Quick Look, which would show it in plain.
    await store.send(.revealTapped(secret.id)) { $0.revealed = [secret.id] }
    await store.send(.quickLookTapped(secret.id))
    await store.send(.quickLookTapped(gone.id))
    await store.send(.spacePressed(over: secret.id))
    await store.finish()
    #expect(quickLooked.value.isEmpty)
    #expect(savedFiles.value.isEmpty)
  }

  @Test
  func filesGoneSinceTheLastCheckAreMarkedNotFoundInsteadOfShown() async {
    let ipa = URL(fileURLWithPath: "/tmp/a.ipa")
    let files = ClipboardItem(
      id: uuid(1), content: .files([ipa]), source: Self.terminal, copiedAt: now.value, fingerprint: "files:1"
    )
    let store = quickLookStore([files])
    missingFiles.setValue([ipa])

    await store.send(.quickLookTapped(files.id)) { $0.hasShownQuickLook = true }
    await store.receive(\.filesChecked) { $0.unavailable = [files.id] }
    #expect(quickLooked.value.isEmpty)
  }

  @Test
  func quickLookClosesWhenTheTabHidesAndItsTextsGo() async {
    let short = item("SELECT 1", id: 1, copiedAt: now.value)
    let store = quickLookStore([short])

    // Nothing of the clipboard's was shown: Quick Look, which may be showing the shelf's files on Home, stays.
    await store.send(.tabHidden)
    await store.finish()
    #expect(quickLookClosed.value == 0)
    #expect(removedFiles.value.isEmpty)

    await store.send(.quickLookTapped(short.id)) { $0.hasShownQuickLook = true }
    await store.finish()
    await store.send(.tabHidden) { $0.hasShownQuickLook = false }
    await store.finish()
    #expect(quickLookClosed.value == 1)
    #expect(removedFiles.value == [ClipboardItem.quickLookFolder])
  }

  @Test
  func spaceShowsTheCardUnderThePointerAndAnywhereElseClosesQuickLook() async {
    let short = item("SELECT 1", id: 1, copiedAt: now.value)
    let store = quickLookStore([short])

    // Over no card, with nothing of the clipboard's in Quick Look: nothing to close.
    await store.send(.spacePressed(over: nil))
    await store.finish()
    #expect(quickLookClosed.value == 0)

    await store.send(.spacePressed(over: short.id)) { $0.hasShownQuickLook = true }
    await store.finish()
    #expect(quickLooked.value.count == 1)
    await store.send(.spacePressed(over: nil))
    await store.finish()
    #expect(quickLookClosed.value == 1)
  }
}
