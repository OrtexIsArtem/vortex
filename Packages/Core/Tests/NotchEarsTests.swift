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
  func anAlarmStaysUnseenUntilSeenAndANewNumberStartsAnother() {
    var seen: [FeatureID: Int] = [:]
    let orange = ColorValue(hex: 0xFF9F43)
    let timer = { (alarm: Int?) in NotchIndicator(leading: [], trailing: [], flashColor: orange, alarm: alarm) }
    #expect(NotchEars.unseenAlarm(["timer": timer(nil)], seen: seen) == nil)
    #expect(NotchEars.unseenAlarm(["timer": timer(1)], seen: seen) == orange)
    // Asked again, it is still unseen: nothing but seeing it ends it.
    #expect(NotchEars.unseenAlarm(["timer": timer(1)], seen: seen) == orange)
    NotchEars.seeAlarms(["timer": timer(1)], seen: &seen)
    #expect(NotchEars.unseenAlarm(["timer": timer(1)], seen: seen) == nil)
    #expect(NotchEars.unseenAlarm(["timer": timer(2)], seen: seen) == orange)
    // Ended by the feature before anyone saw it.
    #expect(NotchEars.unseenAlarm(["timer": timer(nil)], seen: seen) == nil)
    // A feature that counts from the start again still rings.
    NotchEars.seeAlarms(["timer": timer(2)], seen: &seen)
    #expect(NotchEars.unseenAlarm(["timer": timer(1)], seen: seen) == orange)
  }

  @Test
  func indicatorsWithoutItemsShowNoEars() {
    let flashOnly = NotchIndicator(leading: [], trailing: [], priority: 20, flash: 3)
    #expect(NotchEars(indicators: ["shelf": flashOnly]).isEmpty)
    let ears = NotchEars(indicators: ["shelf": flashOnly, "timer": timer])
    #expect(ears.left == [.progress(0.7)])
    #expect(ears.right == [.text("8:42")])
  }

  @Test
  func earsKnowTheirFeatures() {
    let timer = NotchIndicator(leading: [.progress(0.5)], trailing: [.text("8:42")], priority: 10)
    let shelf = NotchIndicator(leading: [.symbol("tray.full")], trailing: [.text("2")])
    let one = NotchEars(indicators: ["timer": timer])
    #expect(one.leftFeature == "timer")
    #expect(one.rightFeature == "timer")
    let two = NotchEars(indicators: ["timer": timer, "shelf": shelf])
    #expect(two.leftFeature == "timer")
    #expect(two.rightFeature == "shelf")
    #expect(NotchEars().leftFeature == nil)
  }

  @Test
  func aPointOnAnEarBelongsToItsFeature() {
    let ears = NotchEars(left: [.text("8:42")], right: [.text("2")], leftFeature: "timer", rightFeature: "shelf")
    // 300 pt wide with a 180 pt cutout in the middle: 60 pt on each side.
    #expect(ears.feature(atX: 30, width: 300, notchWidth: 180) == "timer")
    #expect(ears.feature(atX: 150, width: 300, notchWidth: 180) == nil)
    #expect(ears.feature(atX: 280, width: 300, notchWidth: 180) == "shelf")
  }
}
