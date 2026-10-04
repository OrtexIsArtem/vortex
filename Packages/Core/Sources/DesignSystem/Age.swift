import SwiftUI

extension Text {
  /// How long ago, in the short form cards use: "now", "6 min", "2 h", "3 d".
  public init(age date: Date, now: Date) {
    let seconds = max(0, now.timeIntervalSince(date))
    switch seconds {
    case ..<60: self.init("now", bundle: .module)
    case ..<3600: self.init("\(Int(seconds / 60)) min", bundle: .module)
    case ..<86400: self.init("\(Int(seconds / 3600)) h", bundle: .module)
    default: self.init("\(Int(seconds / 86400)) d", bundle: .module)
    }
  }
}
