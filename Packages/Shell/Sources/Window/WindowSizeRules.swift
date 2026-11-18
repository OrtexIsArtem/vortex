/// How the window behaves around a change of its size.
enum WindowSizeRules {
  enum Resize: Sendable, Equatable {
    case grow
    case shrink
  }

  /// A window that changed size may leave a still pointer outside it: that is no leave. After a resize the pointer
  /// counts as leaving only once it has moved.
  static func closesOnPointerLeave(after resize: Resize?, pointerMoved: Bool) -> Bool {
    resize == nil || pointerMoved
  }
}
