import SwiftUI

extension View {
  /// The pointer hits this button's label `outset` past what it draws, while it looks the same: a small control's
  /// target grown toward 44 pt (`VortexMetrics.hitTarget`), only into room no other control's target takes. macOS hits
  /// a button only inside its own frame, so the label's frame grows; the button gives the growth back to the layout with
  /// `.padding(outset.inward)`, so nothing moves.
  func hitTarget(_ outset: EdgeInsets) -> some View {
    padding(outset).contentShape(Rectangle())
  }
}

extension EdgeInsets {
  /// The same insets turned inward: what a grown target gives back to the layout.
  var inward: EdgeInsets {
    EdgeInsets(top: -top, leading: -leading, bottom: -bottom, trailing: -trailing)
  }
}

/// `style`, its button hit `outset` past what the style draws (`View.hitTarget(_:)`).
struct OutsetButtonStyle<Style: ButtonStyle>: ButtonStyle {
  let style: Style
  let outset: EdgeInsets

  func makeBody(configuration: Configuration) -> some View {
    style.makeBody(configuration: configuration).hitTarget(outset)
  }
}
