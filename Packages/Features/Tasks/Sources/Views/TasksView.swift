import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The Tasks tab: search and New next to the notch, the filters, and the list; a task opens in its place.
public struct TasksView: View {
  @Bindable var store: StoreOf<TasksFeature>
  @Environment(\.notchCutout) private var cutout
  @Environment(\.isWindowOpen) private var isWindowOpen
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// Rows marked done on their way into «Виконані».
  @State private var flights: [DoneFlight] = []
  /// Tasks whose row is crumpling or flying: their row in the list stays hidden until the ball lands. Kept here, by task,
  /// rather than in the row, whose state can outlive the task's move to «Виконані».
  @State private var thrown: Set<TaskItem.ID> = []
  /// The middle of «Виконані», where they land.
  @State private var doneTarget: CGPoint?
  /// Counts the landings, so «Виконані» bumps at each.
  @State private var landings = 0

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
        TaskFilters(store: store, landings: landings) { doneTarget = $0 }
          .padding(.horizontal, 10)
          .padding(.bottom, 10)
        TaskList(store: store, thrown: thrown, onDone: throwToDone)
      }
      // Under the list rather than over it: laid over the scrolling list, the toast never got the click. In «Виконані»
      // the place holds «Очистити список», which the toast takes once it is pressed.
      if let undoable = store.undoable {
        UndoToast(undoable: undoable) { store.send(.undoTapped, animation: .snappy(duration: 0.22)) }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      } else if store.openTask == nil, store.filter.status == .done, store.state.showsAny(now: .now, calendar: .current) {
        ClearListButton { store.send(.clearDoneTapped, animation: .snappy(duration: 0.22)) }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .transition(.opacity)
      }
    }
    .coordinateSpace(.named(DoneFlight.coordinateSpace))
    .overlay {
      DoneFlights(flights: flights) { flight in
        flights.removeAll { $0.id == flight.id }
        thrown.remove(flight.task.id)
        landings += 1
      }
    }
    .animation(.snappy(duration: 0.22), value: store.undoable)
    .animation(.snappy(duration: 0.2), value: store.openTaskID)
    .task(id: isWindowOpen) {
      if isWindowOpen { store.send(.tabShown) }
    }
  }

  /// A row marked done crumples and flies into «Виконані», unless motion is reduced; false when it doesn't.
  private func throwToDone(_ task: TaskItem, row: CGRect) -> Bool {
    guard !reduceMotion, let doneTarget, row.width > 0, !thrown.contains(task.id) else { return false }
    thrown.insert(task.id)
    flights.append(DoneFlight(task: task, row: row, target: doneTarget))
    return true
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
          .overlay(alignment: .topTrailing) {
            // Screen Recording is off: a click opens its page instead of capturing (S22.1, S23).
            if store.showsScreenRecordingWarning {
              WarningMark(.screenRecording, size: 9)
                .offset(x: 3, y: -2)
            }
          }
      }
      .buttonStyle(.plain)
      .help(
        store.showsScreenRecordingWarning
          ? Text(Permission.screenRecording.offLabel) : Text("New task from the screen", bundle: .module)
      )
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
  /// Each new value bumps «Виконані»: a task marked done has just landed in it.
  let landings: Int
  /// Where «Виконані» is, in the tab's coordinate space.
  let onDoneTarget: (CGPoint) -> Void
  /// «Виконані» is bumped by a landing. A plain animated scale: a keyframe animator here kept the undo toast from
  /// taking clicks.
  @State private var isBumped = false

  var body: some View {
    HStack(spacing: 8) {
      SegmentedPicker(selection: binding(\.status), options: TaskFilter.Status.allCases) { status in
        switch status {
        case .active:
          Text("Active", bundle: .module)
        case .done:
          Text("Done", bundle: .module)
            .scaleEffect(isBumped ? 1.22 : 1)
        }
      }
      .frame(width: 150)
      // Two equal segments: «Виконані» is the right one.
      .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DoneFlight.coordinateSpace)) } action: { frame in
        onDoneTarget(CGPoint(x: frame.minX + frame.width * 0.75, y: frame.midY))
      }
      .onChange(of: landings) {
        withAnimation(.easeOut(duration: 0.1)) {
          isBumped = true
        } completion: {
          withAnimation(.bouncy(duration: 0.4)) { isBumped = false }
        }
      }
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
  let thrown: Set<TaskItem.ID>
  let onDone: (TaskItem, _ row: CGRect) -> Bool

  var body: some View {
    // Today and Yesterday move on at midnight, also while the list stays on screen.
    TimelineView(.everyMinute) { context in
      content(now: context.date)
    }
  }

  @ViewBuilder
  private func content(now: Date) -> some View {
    let tasks = store.state.visibleTasks(now: now, calendar: .current)
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
              TaskRow(task: task, now: now, store: store, isThrown: thrown.contains(task.id), onDone: onDone)
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
  let now: Date
  let store: StoreOf<TasksFeature>
  /// Crumpling or flying over the list: the row keeps its place, unseen, until the task leaves the list.
  let isThrown: Bool
  /// The task is being marked done: its row, in the tab's coordinate space, takes off for «Виконані»; false when it
  /// stays put (motion reduced).
  let onDone: (TaskItem, _ row: CGRect) -> Bool
  @State private var isHovered = false
  @State private var frame = CGRect.zero

  var body: some View {
    Button {
      store.send(.taskTapped(task.id))
    } label: {
      HStack(spacing: 12) {
        // Room for the done mark, which lies over the row.
        Color.clear
          .frame(width: 30, height: 30)
        FileThumbnail(url: task.cropURL, size: CGSize(width: 64, height: 44)) {
          VortexColor.thumbnail
        }
        .frame(width: 64, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        VStack(alignment: .leading, spacing: 3) {
          Text(verbatim: task.displayTitle)
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
        TaskDate(date: task.createdAt, now: now)
          .font(.system(size: 11.5))
          .foregroundStyle(VortexColor.tertiaryText)
          .frame(minWidth: 44, alignment: .trailing)
          // The bin takes its place.
          .opacity(isHovered ? 0 : 1)
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isHovered ? VortexColor.raised : .clear))
      .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    .buttonStyle(.plain)
    // A button of its own over the row: a click on it marks the task and never opens it.
    .overlay(alignment: .leading) {
      DoneMark(isDone: task.isDone) {
        guard !isThrown else { return }
        guard !task.isDone, onDone(task, frame) else {
          store.send(.doneTapped(task.id))
          return
        }
        Task {
          try? await Task.sleep(for: DoneFlight.crumple)
          store.send(.doneTapped(task.id))
        }
      }
      .padding(.leading, 10)
    }
    .overlay(alignment: .trailing) {
      if isHovered, !isThrown {
        Button {
          store.send(.deleteTapped(task.id), animation: .snappy(duration: 0.22))
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 12))
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VortexColor.secondaryText)
        .help(Text("Delete the task", bundle: .module))
        .accessibilityLabel(Text("Delete the task", bundle: .module))
        .padding(.trailing, 10)
      }
    }
    .accessibilityAction(named: Text("Delete the task", bundle: .module)) {
      store.send(.deleteTapped(task.id), animation: .snappy(duration: 0.22))
    }
    // Hidden only while it is still active (crumpling, or fading out of the list): in «Виконані» it shows at once.
    .opacity(isThrown && !task.isDone ? 0 : 1)
    .onHover { isHovered = $0 }
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(DoneFlight.coordinateSpace)) } action: { frame = $0 }
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

/// «Очистити список» under the done tasks: deletes the ones the list shows.
private struct ClearListButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: "trash")
          .font(.system(size: 11))
        Text("Clear the list", bundle: .module)
      }
    }
    .buttonStyle(QuietCapsuleButtonStyle(height: 34, fontSize: 12.5))
    .help(Text("Delete the done tasks shown", bundle: .module))
  }
}

/// "Task done · Undo" for a few seconds after a task is marked done, "Task deleted · Undo" after it is deleted.
private struct UndoToast: View {
  let undoable: TasksFeature.Undoable
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
    // Only drawn: laid over «Скасувати», the outline took its clicks.
    .overlay(Capsule().strokeBorder(VortexColor.line).allowsHitTesting(false))
    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
  }

  private var message: Text {
    switch undoable {
    case .done: Text("Task done", bundle: .module)
    case let .deleted(tasks) where tasks.count == 1: Text("Task deleted", bundle: .module)
    case .deleted: Text("Done tasks deleted", bundle: .module)
    }
  }
}
