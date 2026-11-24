import Foundation
import Testing

extension Trait where Self == ConditionTrait {
  /// A test that has Apple Vision read a picture. It runs on a Mac, and CI (`CI` set) skips it: on CI's virtual Macs
  /// Vision has only the CPU ("On-device compilation within a VM only supports CPU"), so its reads take a minute or
  /// more, hold back a run of every suite at once until other tests' time limits go by, and come out otherwise
  /// (`query Selector` for `querySelector` at 13 pt). `make test` and the pre-push hook run it on your Mac.
  static var liveVision: Self {
    .enabled(if: ProcessInfo.processInfo.environment["CI"] == nil, "Vision on CI's virtual Macs has only the CPU")
  }
}
