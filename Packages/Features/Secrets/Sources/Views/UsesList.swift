import SwiftUI
import VortexCore

/// The log: when Claude used which keys for what, newest first, and how it ended.
struct UsesList: View {
  let uses: [KeyUse]

  var body: some View {
    Group {
      if uses.isEmpty {
        Text("Nothing in the log yet", bundle: .module)
          .font(.system(size: 12.5))
          .foregroundStyle(VortexColor.tertiaryText)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.bottom, 40)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(uses) { use in
              UseRow(use: use)
            }
          }
          .padding(.horizontal, 6)
          .padding(.bottom, 40)
        }
        .scrollIndicators(.never)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct UseRow: View {
  let use: KeyUse

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(use.outcome == .ran && use.exitCode == 0 ? VortexColor.secondaryText : VortexColor.primaryText)
        .frame(width: 20, height: 20)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(verbatim: use.keys.joined(separator: ", "))
            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
          Text(verbatim: "·")
          outcome
          Spacer(minLength: 8)
          Text(use.at, format: .dateTime.day().month(.abbreviated).hour().minute())
            .monospacedDigit()
        }
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        Text(verbatim: use.command)
          .font(.system(size: 11.5, design: .monospaced))
          .foregroundStyle(VortexColor.secondaryText)
          .lineLimit(2)
          .textSelection(.enabled)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
  }

  private var symbol: String {
    switch use.outcome {
    case .ran: use.exitCode == 0 ? "checkmark" : "exclamationmark"
    case .timedOut: "clock"
    case .denied: "hand.raised"
    case .unanswered: "questionmark"
    case .failed: "xmark"
    }
  }

  private var outcome: Text {
    switch use.outcome {
    case .ran: Text("\(use.client), exit code \(use.exitCode ?? 0)", bundle: .module)
    case .timedOut: Text("\(use.client), stopped: out of time", bundle: .module)
    case .denied: Text("\(use.client), denied", bundle: .module)
    case .unanswered: Text("\(use.client), not answered", bundle: .module)
    case .failed: Text("\(use.client), could not run", bundle: .module)
    }
  }
}
