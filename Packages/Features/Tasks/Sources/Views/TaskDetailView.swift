import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// One task, open in the tab: its picture, which opens the whole screen, the title and priority to change in place,
/// where it came from, and done.
struct TaskDetailView: View {
  let task: TaskItem
  let store: StoreOf<TasksFeature>
  @FocusState private var isTitleFocused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        Button {
          store.send(.backTapped)
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "chevron.left")
              .font(.system(size: 11, weight: .semibold))
            Text("Tasks", bundle: .module)
          }
          .padding(.horizontal, 8)
          .frame(height: 28)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VortexColor.secondaryText)
        Spacer()
        Text(verbatim: "#\(task.number)")
          .font(.system(size: 11.5).monospacedDigit())
          .foregroundStyle(VortexColor.tertiaryText)
        Button {
          store.send(.deleteTapped(task.id))
        } label: {
          Image(systemName: "trash")
            .font(.system(size: 12))
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VortexColor.tertiaryText)
        .help(Text("Delete the task", bundle: .module))
        .accessibilityLabel(Text("Delete the task", bundle: .module))
      }

      HStack(alignment: .top, spacing: 18) {
        picture
        fields
      }
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// The framed part, as large as the room allows; a click shows the whole screen.
  private var picture: some View {
    let box = CGSize(width: 290, height: 230)
    let scale = min(1, box.width / max(task.cropWidth, 1), box.height / max(task.cropHeight, 1))
    let size = CGSize(width: task.cropWidth * scale, height: task.cropHeight * scale)
    return VStack(alignment: .leading, spacing: 8) {
      Button {
        store.send(.screenTapped(task.id))
      } label: {
        // At its own proportions, so the thumbnail fills it without cutting anything off.
        FileThumbnail(url: task.cropURL, size: size) {
          VortexColor.thumbnail
        }
        .frame(width: size.width, height: size.height)
          // A small radius: the framed text often reaches the very corners.
          .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(VortexColor.line))
      }
      .buttonStyle(.plain)
      .help(Text("Show the whole screen", bundle: .module))
      Text("Click to see the whole screen", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
    }
    .frame(width: box.width, alignment: .leading)
  }

  private var fields: some View {
    VStack(alignment: .leading, spacing: 14) {
      TextField(
        text: Binding(get: { task.title }, set: { store.send(.titleChanged(task.id, $0)) }),
        axis: .vertical
      ) {
        Text("Name", bundle: .module)
      }
      .textFieldStyle(.plain)
      .font(.system(size: 17, weight: .semibold))
      .lineLimit(1...3)
      .focused($isTitleFocused)
      .onSubmit { store.send(.titleCommitted(task.id)) }
      .onChange(of: isTitleFocused) { _, isFocused in
        if !isFocused { store.send(.titleCommitted(task.id)) }
      }

      PriorityPicker(selection: Binding(get: { task.priority }, set: { store.send(.priorityChanged(task.id, $0)) }))
        .font(.system(size: 12))

      VStack(alignment: .leading, spacing: 4) {
        SourceLine(source: task.source, date: task.createdAt)
        if let title = task.source.windowTitle {
          Text(verbatim: title)
            .font(.system(size: 11.5))
            .foregroundStyle(VortexColor.tertiaryText)
            .lineLimit(2)
        }
        if let url = task.source.url {
          Text(verbatim: url.absoluteString)
            .font(.system(size: 11.5))
            .foregroundStyle(VortexColor.tertiaryText)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }

      HStack(spacing: 8) {
        if task.source.url != nil || task.source.app != nil {
          Button {
            store.send(.openSourceTapped(task.id))
          } label: {
            Text("Open the source", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
        }
        Button {
          store.send(.doneTapped(task.id))
        } label: {
          HStack(spacing: 6) {
            Image(systemName: task.isDone ? "arrow.uturn.backward" : "checkmark")
              .font(.system(size: 10, weight: .bold))
            task.isDone ? Text("Back to active", bundle: .module) : Text("Mark done", bundle: .module)
          }
        }
        .buttonStyle(.primaryCapsule)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
