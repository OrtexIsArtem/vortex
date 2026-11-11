import ComposableArchitecture
import Foundation
import Testing
import VortexCore
import VortexPlatform

@testable import FeatureClipboard

/// Links read as Safari's address bar shows them, and copy as they were.
extension ClipboardFeatureTests {
  @Test
  func linksShowLettersBeyondASCIIDecoded() {
    #expect(LinkAddress.readable("/%D0%BF%D1%80%D0%B8%D0%B2%D1%96%D1%82") == "/привіт")
    #expect(LinkAddress.readable("/%d0%bf") == "/п")
    #expect(LinkAddress.readable("a%D0%B1c") == "aбc")
    #expect(LinkAddress.readable("/%F0%9F%98%80") == "/😀")
    #expect(
      LinkAddress.readable("https://uk.wikipedia.org/wiki/%D0%9A%D0%B8%D1%97%D0%B2?q=%D0%B0%20b")
        == "https://uk.wikipedia.org/wiki/Київ?q=а%20b"
    )
  }

  @Test
  func escapesThatWouldChangeTheAddressOrDontFormALetterStayAsTheyAre() {
    // ASCII written plainly would read differently: a space, a slash inside a name, a percent sign.
    #expect(LinkAddress.readable("/a%20b/c%2Fd%25") == "/a%20b/c%2Fd%25")
    // Invalid escapes: the raw text.
    #expect(LinkAddress.readable("/%D0") == "/%D0")
    #expect(LinkAddress.readable("/%ff%FF") == "/%ff%FF")
    #expect(LinkAddress.readable("/%ZZ%") == "/%ZZ%")
    #expect(LinkAddress.readable("/%D0%BF%FF") == "/п%FF")
    #expect(LinkAddress.readable("/%C0%AF") == "/%C0%AF")
    // Invisible or direction-changing characters would hide what the address is.
    #expect(LinkAddress.readable("/%E2%80%AEtxt") == "/%E2%80%AEtxt")
    #expect(LinkAddress.readable("/a%C2%A0b") == "/a%C2%A0b")
  }

  @Test
  func aCardShowsItsLinksPathDecoded() {
    let url = URL(string: "https://example.com/%D0%BF%D1%80%D0%B8%D0%B2%D1%96%D1%82?q=%D0%B0")!
    #expect(ClipboardCard.pathAndQuery(of: url) == "/привіт?q=а")
  }

  @Test
  func aLinkShownDecodedIsCopiedAsItWas() async throws {
    let link = URL(string: "https://example.com/%D0%BF%D1%80%D0%B8%D0%B2%D1%96%D1%82")!
    let store = makeStore()
    store.exhaustivity = .off
    await start(store)
    copy(.link(link))
    await store.receive(\.copied)
    await store.send(.itemTapped(uuid(0)))
    await store.receive(\.copiedAgain)
    #expect(written.value == [.link(link)])
    #expect(written.value.first.map { if case let .link(url) = $0 { url.absoluteString } else { "" } } == link.absoluteString)
    await finishCopiedMark(store)
    await store.send(.stop)
  }
}
