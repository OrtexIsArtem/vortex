import CoreGraphics
import Testing
import VortexPlatform

@testable import FeatureTimer

struct DrumTests {
  let drum = DrumGeometry(width: 120, spacing: 6)

  @Test
  func underTheMarkTheTicksStandTheirSpacingApartAndCrowdTowardsTheEdges() throws {
    let center = try #require(drum.spot(of: 25, value: 25))
    #expect(center.x == 60)
    #expect(center.facing == 1)
    let next = try #require(drum.spot(of: 26, value: 25))
    #expect(abs(next.x - 66) < 0.05)
    let nearEdge = try #require(drum.spot(of: 39, value: 25))
    let beforeIt = try #require(drum.spot(of: 38, value: 25))
    #expect(nearEdge.x - beforeIt.x < 1.5)
    #expect(nearEdge.facing < 0.2)
    // Round the back.
    #expect(drum.spot(of: 41, value: 25) == nil)
    #expect(drum.reach == 15)
  }

  @Test
  func aClickTurnsTheTickUnderThePointerToTheMark() throws {
    #expect(drum.minute(atX: 60, value: 25) == 25)
    for offset in [-12, -5, -1, 1, 5, 12] {
      let spot = try #require(drum.spot(of: Double(25 + offset), value: 25))
      #expect(drum.minute(atX: spot.x, value: 25) == 25 + offset)
    }
    // Past the edge, the furthest tick that shows.
    #expect(drum.minute(atX: 500, value: 25) <= 25 + drum.reach)
  }

  @Test
  func aTrackpadTurnsAMinutePerSpacingFollowingTheFingers() {
    var steps = ScrollSteps()
    func turn(x: CGFloat = 0, y: CGFloat = 0, begins: Bool = false) -> Int {
      steps.minutes(for: ScrollDelta(x: x, y: y, isPrecise: true, beginsGesture: begins), points: 6)
    }
    // Fingers to the left: the drum moves left and later minutes come under the mark.
    #expect(turn(x: -4, begins: true) == 0)
    #expect(turn(x: -4) == 1)
    #expect(turn(x: -13, y: 1) == 2)
    // Up adds time too, with the 3 pt left over; right and down take it away.
    #expect(turn(y: -3) == 1)
    #expect(turn(y: 30) == -5)
  }

  @Test
  func everySwipeStartsAfresh() {
    var steps = ScrollSteps()
    func turn(x: CGFloat, begins: Bool = false) -> Int {
      steps.minutes(for: ScrollDelta(x: x, y: 0, isPrecise: true, beginsGesture: begins), points: 6)
    }
    #expect(turn(x: -5.9, begins: true) == 0)
    // A new touch drops what the last swipe left over.
    #expect(turn(x: -0.2, begins: true) == 0)
    #expect(turn(x: -5) == 0)
    // Turning back starts from nothing, not from what was left over the other way.
    #expect(turn(x: 6) == -1)
  }

  @Test
  func afterTheFingersLiftTheDrumCoastsHalfAsFar() {
    var steps = ScrollSteps()
    #expect(steps.minutes(for: ScrollDelta(x: -12, y: 0, isPrecise: true, beginsGesture: true), points: 6) == 2)
    #expect(steps.minutes(for: ScrollDelta(x: -12, y: 0, isPrecise: true, isMomentum: true), points: 6) == 1)
    #expect(steps.minutes(for: ScrollDelta(x: -6, y: 0, isPrecise: true, isMomentum: true), points: 6) == 0)
    #expect(steps.minutes(for: ScrollDelta(x: -6, y: 0, isPrecise: true, isMomentum: true), points: 6) == 1)
  }

  @Test
  func aMouseWheelTurnsAMinutePerNotchWhateverItsSpeed() {
    var steps = ScrollSteps()
    func turn(_ y: CGFloat) -> Int {
      steps.minutes(for: ScrollDelta(x: 0, y: y, isPrecise: false), points: 6)
    }
    #expect(turn(-1) == 1)
    #expect(turn(-4.5) == 1)
    #expect(turn(2) == -1)
    #expect(turn(0) == 0)
  }
}
