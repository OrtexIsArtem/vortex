import Testing
import VortexCore

struct NotchEarsTests {
  let timer = NotchIndicator(leading: [.progress(0.7)], trailing: [.text("8:42")], priority: 10)
  let shelf = NotchIndicator(leading: [.symbol("tray")], trailing: [.text("2")], priority: 5)

  @Test
  func noIndicatorsMeansNoEars() {
    #expect(NotchEars(indicators: [:]).isEmpty)
  }

  @Test
  func singleIndicatorSplitsAroundTheNotch() {
    let ears = NotchEars(indicators: ["timer": timer])
    #expect(ears.left == [.progress(0.7)])
    #expect(ears.right == [.text("8:42")])
  }

  @Test
  func twoIndicatorsTakeOneEarEachByPriority() {
    let ears = NotchEars(indicators: ["shelf": shelf, "timer": timer])
    #expect(ears.left == [.progress(0.7), .text("8:42")])
    #expect(ears.right == [.symbol("tray"), .text("2")])
  }

  @Test
  func equalPriorityIsOrderedById() {
    var other = shelf
    other.priority = timer.priority
    let ears = NotchEars(indicators: ["timer": timer, "shelf": other])
    #expect(ears.left == [.symbol("tray"), .text("2")])
  }

  @Test
  func menuBarTextKeepsOnlyText() {
    let ears = NotchEars(indicators: ["shelf": shelf, "timer": timer])
    #expect(ears.menuBarText == "8:42  2")
  }

  @Test
  func flashesOnlyWhenTheNumberGrowsInTheColorAskedFor() {
    var seen: [FeatureID: Int] = [:]
    let blue = ColorValue(hex: 0x5AC8FA)
    let shelf = { (flash: Int) in NotchIndicator(leading: [], trailing: [.text("1")], flash: flash, flashColor: blue) }
    #expect(NotchEars.flash(["shelf": shelf(0)], seen: &seen) == nil)
    #expect(NotchEars.flash(["shelf": shelf(1)], seen: &seen) == blue)
    #expect(NotchEars.flash(["shelf": shelf(1), "timer": shelf(0)], seen: &seen) == nil)
    // Hidden, then back with the same number: no flash.
    #expect(NotchEars.flash([:], seen: &seen) == nil)
    #expect(NotchEars.flash(["shelf": shelf(1)], seen: &seen) == nil)
    #expect(NotchEars.flash(["shelf": shelf(2)], seen: &seen) == blue)
  }

  @Test
  func indicatorsWithoutItemsShowNoEars() {
    let flashOnly = NotchIndicator(leading: [], trailing: [], priority: 20, flash: 3)
    #expect(NotchEars(indicators: ["shelf": flashOnly]).isEmpty)
    let ears = NotchEars(indicators: ["shelf": flashOnly, "timer": timer])
    #expect(ears.left == [.progress(0.7)])
    #expect(ears.right == [.text("8:42")])
  }
}
