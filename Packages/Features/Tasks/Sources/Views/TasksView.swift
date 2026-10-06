import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The Tasks tab: search and New next to the notch, the filters, and the list; a task opens in its place.
public struct TasksView: View {
  @Bindable var store: StoreOf<TasksFeature>
  @Environment(\.notchCutout) private var cutout
  @Environment(\.isWindowOpen) private var isWindowOpen

  public init(store: StoreOf<TasksFeature>) {
    self.store = store
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .frame(height: VortexMetrics.headerHeight)
      if let task = store.openTask {
        TaskDetailView(task: task, store: store)
          .transition(.opacity)
      } else {
        TaskFilters(store: store)
          .padding(.horizontal, 10)
          .padding(.bottom, 10)
        TaskList(store: store)
      }
    }
    .overlay(alignment: .bottom) {
      if store.undoableID != nil {
        UndoToast { store.send(.undoTapped) }
          .padding(.bottom, 14)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.snappy(duration: 0.22), value: store.undoableID)
    .animation(.snappy(duration: 0.2), value: store.openTaskID)
    .task(id: isWindowOpen) {
      if isWindowOpen { store.send(.tabShown) }
    }
  }

  /// The title left of the notch; search and New right of it.
  @ViewBuilder
  private var header: some View {
    let title = Text("Tasks", bundle: .module)
      .font(.system(size: 13, weight: .semibold))
      .padding(.leading, 10)
    let tools = HStack(spacing: 6) {
      SearchField(query: $store.query.sending(\.queryChanged))
      Button {
        store.send(.captureRequested)
      } label: {
        Image(systemName: "plus")
          .font(.system(size: 13, weight: .semibold))
          .frame(width: 30, height: 30)
          .background(Circle().fill(VortexColor.raised))
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .help(Text("New task from the screen", bundle: .module))
      .accessibilityLabel(Text("New task from the screen", bundle: .module))
    }
    if let cutout {
      HStack(spacing: 0) {
        title
          .frame(width: max(cutout.minX - 12, 0), alignment: .leading)
        Color.clear
          .frame(width: cutout.width + 24)
        tools
          .padding(.trailing, 12)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    } else {
      HStack {
        title
        Spacer()
        tools
          .padding(.trailing, 12)
      }
    }
  }
}

private struct SearchField: View {
  @Binding var query: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 11))
        .foregroundStyle(VortexColor.tertiaryText)
      TextField(text: $query) {
        Text("Search", bundle: .module)
      }
      .textFieldStyle(.plain)
      .font(.system(size: 12.5))
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .font(.system(size: 11))
            .foregroundStyle(VortexColor.tertiaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Clear search", bundle: .module))
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 30)
    .background(Capsule().fill(VortexColor.raised))
  }
}

/// Status, priority and period, one row.
private struct TaskFilters: View {
  let store: StoreOf<TasksFeature>

  var body: some View {
    HStack(spacing: 8) {
      SegmentedPicker(selection: binding(\.status), options: TaskFilter.Status.allCases) { status in
        switch status {
        case .active: Text("Active", bundle: .module)
        case .done: Text("Done", bundle: .module)
        }
      }
      .frame(width: 150)
      SegmentedPicker(
        selection: binding(\.priority),
        options: [nil, TaskItem.Priority.high, .medium, .low]
      ) { priority in
        if let priority {
          PriorityBars(priority: priority)
            .help(priority.name)
            .accessibilityLabel(priority.name)
        } else {
          Text("All", bundle: .module)
        }
      }
      .frame(width: 150)
      SegmentedPicker(selection: binding(\.period), options: TaskFilter.Period.allCases) { period in
        switch period {
        case .today: Text("Today", bundle: .module)
        case .yesterday: Text("Yesterday", bundle: .module)
        case .week: Text("7 days", bundle: .module)
        case .all: Text("All", bundle: .module)
        }
      }
    }
    .font(.system(size: 11.5))
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<TaskFilter, Value>) -> Binding<Value> {
    Binding(
      get: { store.filter[keyPath: keyPath] },
      set: { value in
        var filter = store.filter
        filter[keyPath: keyPath] = value
        store.send(.filterChanged(filter))
      }
    )
  }
}

private struct TaskList: View {
  let store: StoreOf<TasksFeature>

  var body: some View {
    let tasks = store.state.visibleTasks(now: .now, calendar: .current)
    Group {
      if !store.isLoaded {
        Color.clear
      } else if store.tasks.isEmpty {
        EmptyTasks()
      } else if tasks.isEmpty {
        emptyMessage
          .font(.system(size: 12.5))
          .foregroundStyle(VortexColor.tertiaryText)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(.bottom, 40)
      } else {
        ScrollView {
          LazyVStack(spacing: 2) {
            ForEach(tasks) { task in
              TaskRow(task: task, store: store)
            }
          }
          .padding(.horizontal, 6)
          .padding(.bottom, 60)
        }
        .scrollIndicators(.never)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// Nothing to show: nothing matches the search or narrowed filters, or the status simply has no tasks.
  private var emptyMessage: Text {
    let filter = store.filter
    guard store.query.isEmpty, filter.priority == nil, filter.period == .all else {
      return Text("Nothing found", bundle: .module)
    }
    return filter.status == .active ? Text("No active tasks", bundle: .module) : Text("No done tasks yet", bundle: .module)
  }
}

/// What to do when there are no tasks yet.
private struct EmptyTasks: View {
  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "viewfinder")
        .font(.system(size: 22, weight: .light))
        .foregroundStyle(VortexColor.tertiaryText)
      Text("No tasks yet", bundle: .module)
        .font(.system(size: 13, weight: .medium))
      Text("Press + or your shortcut, frame what matters on the screen and press Return.", bundle: .module)
        .font(.system(size: 12))
        .foregroundStyle(VortexColor.tertiaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 300)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.bottom, 40)
  }
}

/// One task in the list: done mark, picture, title and source, priority and time.
private struct TaskRow: View {
  let task: TaskItem
  let store: StoreOf<TasksFeature>
  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 12) {
      DoneMark(isDone: task.isDone) { store.send(.doneTapped(task.id)) }
      FileThumbnail(url: task.cropURL, size: CGSize(width: 64, height: 44)) {
        VortexColor.thumbnail
      }
      .frame(width: 64, height: 44)
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: task.title)
          .font(.system(size: 13, weight: .medium))
          .lineLimit(1)
          .strikethrough(task.isDone, color: VortexColor.tertiaryText)
          .foregroundStyle(task.isDone ? VortexColor.secondaryText : VortexColor.primaryText)
        SourceLine(source: task.source, date: nil)
      }
      Spacer(minLength: 8)
      PriorityBars(priority: task.priority)
        .foregroundStyle(task.priority == .high ? VortexColor.primaryText : VortexColor.secondaryText)
        .help(task.priority.name)
      TaskDate(date: task.createdAt)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .frame(minWidth: 44, alignment: .trailing)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isHovered ? VortexColor.raised : .clear))
    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .onHover { isHovered = $0 }
    .onTapGesture { store.send(.taskTapped(task.id)) }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }
}

/// A round mark: empty while the task is active, checked once it is done.
struct DoneMark: View {
  let isDone: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .strokeBorder(isDone ? Color.clear : VortexColor.tertiaryText, lineWidth: 1.5)
          .background(Circle().fill(isDone ? VortexColor.accent : .clear))
        if isDone {
          Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(VortexColor.onAccent)
        }
      }
      .frame(width: 18, height: 18)
      .frame(width: 30, height: 30)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(isDone ? Text("Mark as active", bundle: .module) : Text("Mark as done", bundle: .module))
    .accessibilityLabel(isDone ? Text("Mark as active", bundle: .module) : Text("Mark as done", bundle: .module))
  }
}

/// "Task done · Undo" for a few seconds after a task is marked done.
private struct UndoToast: View {
  let undo: () -> Void

  var body: some View {
    HStack(spacing: 14) {
      Text("Task done", bundle: .module)
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
    .overlay(Capsule().strokeBorder(VortexColor.line))
    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
  }
}
