import CoreGraphics
import Testing

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
    // Fingers to the left: the drum moves left and later minutes come under the mark.
    #expect(steps.minutes(x: -4, y: 0, isPrecise: true, points: 6) == 0)
    #expect(steps.minutes(x: -4, y: 0, isPrecise: true, points: 6) == 1)
    #expect(steps.minutes(x: -13, y: 1, isPrecise: true, points: 6) == 2)
    // Up adds time too; right and down take it away.
    var vertical = ScrollSteps()
    #expect(vertical.minutes(x: 0, y: -6, isPrecise: true, points: 6) == 1)
    #expect(vertical.minutes(x: 0, y: 30, isPrecise: true, points: 6) == -5)
    #expect(vertical.minutes(x: 3, y: 0, isPrecise: true, points: 6) == 0)
  }

  @Test
  func aMouseWheelTurnsAMinutePerNotchWhateverItsSpeed() {
    var steps = ScrollSteps()
    #expect(steps.minutes(x: 0, y: -1, isPrecise: false, points: 6) == 1)
    #expect(steps.minutes(x: 0, y: -4.5, isPrecise: false, points: 6) == 1)
    #expect(steps.minutes(x: 0, y: 2, isPrecise: false, points: 6) == -1)
    #expect(steps.minutes(x: 0, y: 0, isPrecise: false, points: 6) == 0)
  }
}
