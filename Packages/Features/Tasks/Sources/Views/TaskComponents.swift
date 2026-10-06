import SwiftUI
import VortexCore
import VortexPlatform

extension TaskItem.Priority {
  var name: Text {
    switch self {
    case .low: Text("Low", bundle: .module)
    case .medium: Text("Medium", bundle: .module)
    case .high: Text("High", bundle: .module)
    }
  }
}

/// Three bars of rising height, as many lit as the priority is high.
struct PriorityBars: View {
  let priority: TaskItem.Priority

  var body: some View {
    HStack(alignment: .bottom, spacing: 1.5) {
      ForEach(0..<3) { bar in
        RoundedRectangle(cornerRadius: 0.75)
          .fill(bar <= priority.rawValue ? AnyShapeStyle(.foreground) : AnyShapeStyle(VortexColor.track))
          .frame(width: 2.5, height: 4 + CGFloat(bar) * 3)
      }
    }
    .frame(height: 10, alignment: .bottom)
    .accessibilityHidden(true)
  }
}

/// The app's icon and name, with its window title or the page's site, and when the task was taken.
struct SourceLine: View {
  let source: FrontWindow
  let date: Date?

  var body: some View {
    HStack(spacing: 6) {
      if let app = source.app {
        AppIcon(bundleID: app.bundleID)
          .frame(width: 14, height: 14)
      }
      Text(verbatim: Self.summary(of: source) ?? "")
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundStyle(VortexColor.secondaryText)
      Spacer(minLength: 8)
      if let date {
        TaskDate(date: date)
          .foregroundStyle(VortexColor.tertiaryText)
      }
    }
    .font(.system(size: 12))
  }

  /// "Telegram · mobile-team"; for a browser the site rather than the page title.
  static func summary(of source: FrontWindow) -> String? {
    let detail = source.url?.host() ?? source.windowTitle
    return [source.app?.name, detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty
  }
}

/// "14:21" today, "Yesterday", or "6 Oct".
struct TaskDate: View {
  let date: Date

  var body: some View {
    let calendar = Calendar.current
    Group {
      if calendar.isDateInToday(date) {
        Text(date, format: .dateTime.hour().minute())
      } else if calendar.isDateInYesterday(date) {
        Text("Yesterday", bundle: .module)
      } else {
        Text(date, format: .dateTime.day().month(.abbreviated))
      }
    }
    .monospacedDigit()
  }
}

extension String {
  var nilIfEmpty: String? { isEmpty ? nil : self }
}
