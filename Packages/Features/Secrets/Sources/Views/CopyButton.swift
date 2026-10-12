import SwiftUI

/// A button that copies and then says «Скопійовано» for a moment; pressed again, the moment starts over.
struct CopyButton<Style: ButtonStyle>: View {
  private let title: Text
  private let style: Style
  private let minWidth: CGFloat?
  private let action: () -> Void
  @State private var copied = false
  @State private var reset: Task<Void, Never>?

  init(_ title: Text, style: Style, minWidth: CGFloat? = nil, action: @escaping () -> Void) {
    self.title = title
    self.style = style
    self.minWidth = minWidth
    self.action = action
  }

  var body: some View {
    Button {
      action()
      copied = true
      reset?.cancel()
      reset = Task {
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        copied = false
      }
    } label: {
      (copied ? Text("Copied", bundle: .module) : title)
        .frame(minWidth: minWidth)
    }
    .buttonStyle(style)
  }
}
