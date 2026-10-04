import Observation

/// Something of Vortex's in use outside its window: a drag out of it, Quick Look, the folder picker.
/// The shell keeps the window open while any of it lasts.
@MainActor
@Observable
public final class OutsideActivity {
  public static let shared = OutsideActivity()
  private var count = 0

  public var isActive: Bool { count > 0 }

  nonisolated init() {}

  func begin() {
    count += 1
  }

  func end() {
    count = max(0, count - 1)
  }
}
