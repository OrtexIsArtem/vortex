import SwiftUI
import VortexCore

/// "History cleared · Undo" after Clear, "Older items removed · Undo" after a shorter Keep history, for a few seconds.
/// The look of Tasks' undo toast.
struct UndoToast: View {
  let reason: ClipboardFeature.PendingRemoval.Reason
  let undo: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      message
        .foregroundStyle(VortexColor.secondaryText)
      Button(action: undo) {
        Text("Undo", bundle: .module)
          .fontWeight(.semibold)
      }
      .buttonStyle(.plain)
      .foregroundStyle(VortexColor.primaryText)
    }
    .font(.system(size: 12.5))
    .padding(.horizontal, 16)
    .frame(height: 34)
    .background(Capsule().fill(VortexColor.raised))
    // Only drawn: laid over «Undo», the outline took its clicks.
    .overlay(Capsule().strokeBorder(VortexColor.line).allowsHitTesting(false))
    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
  }

  private var message: Text {
    switch reason {
    case .cleared: Text("History cleared", bundle: .module)
    case .lifetime: Text("Older items removed", bundle: .module)
    }
  }
}
