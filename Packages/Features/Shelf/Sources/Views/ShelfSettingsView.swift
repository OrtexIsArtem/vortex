import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The shelf's section in Settings › Features: folders whose new files land on the shelf, with their file types,
/// and the colors the notch flashes in.
struct ShelfSettingsView: View {
  let store: StoreOf<ShelfFeature>
  @State private var path = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(
        title: Text("Watched folders", bundle: .module),
        caption: Text("New files of the right type land on the shelf once they are fully written, and the notch flashes.", bundle: .module)
      ) {
        Button {
          store.send(.chooseFolderTapped)
        } label: {
          Text("Add folder…", bundle: .module)
        }
        .buttonStyle(.quietCapsule)
      }

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          TextField(text: $path, prompt: Text("Folder, a build file or …/last_builds/*.aab", bundle: .module)) {
            Text("Path to watch", bundle: .module)
          }
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .onSubmit { store.send(.watchPathSubmitted(path)) }
          Button {
            store.send(.watchPathSubmitted(path))
          } label: {
            Text("Watch", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
          .disabled(path.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        if let missing = store.pathNotFound {
          Text("Nothing is at \(missing).", bundle: .module)
            .font(.system(size: 11.5))
            .foregroundStyle(VortexColor.secondaryText)
        }
      }
      .padding(.vertical, 10)
      Hairline()

      ForEach(store.settings.watchedFolders) { watched in
        WatchedFolderRow(watched: watched) { action in store.send(action) }
      }

      FlashColorsSection(store: store)
    }
    .onChange(of: store.settings.watchedFolders.count) { path = "" }
  }
}

/// A watched folder: where it is, which types it takes, and a button to stop watching it.
private struct WatchedFolderRow: View {
  let watched: ShelfSettings.WatchedFolder
  let send: @MainActor (ShelfFeature.Action) -> Void
  @State private var types = ""
  @FocusState private var isEditing: Bool

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Image(systemName: "folder")
          .foregroundStyle(VortexColor.secondaryText)
          .frame(width: 20)
        Text(verbatim: (watched.folder.path as NSString).abbreviatingWithTildeInPath)
          .font(.system(size: 12))
          .lineLimit(1)
          .truncationMode(.head)
          .help(Text(verbatim: watched.folder.path))
        Spacer(minLength: 8)
        TextField(text: $types, prompt: Text("every file", bundle: .module)) {
          Text("File types", bundle: .module)
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .frame(width: 170)
        .focused($isEditing)
        .onSubmit { send(.extensionsChanged(watched.folder, types)) }
        .onChange(of: isEditing) { _, isEditing in
          if !isEditing { send(.extensionsChanged(watched.folder, types)) }
        }
        .help(Text("File types, separated by commas; empty takes every file", bundle: .module))
        Button {
          send(.stopWatchingTapped(watched.folder))
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10.5, weight: .semibold))
            .frame(width: 30, height: 30)
            .background(Circle().fill(VortexColor.raised))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(VortexColor.secondaryText)
        .help(Text("Stop watching", bundle: .module))
        .accessibilityLabel(Text("Stop watching", bundle: .module))
      }
      .frame(minHeight: 44)
      Hairline()
    }
    .onAppear { types = watched.extensions.joined(separator: ", ") }
    .onChange(of: watched.extensions) { _, saved in types = saved.joined(separator: ", ") }
  }
}

/// The colors the notch flashes in for the first, second… new file, and a test that plays them.
private struct FlashColorsSection: View {
  let store: StoreOf<ShelfFeature>

  var body: some View {
    let colors = store.settings.flashColors
    SettingsRow(
      title: Text("Notch flash", bundle: .module),
      caption: Text("New files flash the notch: color 1 for the first new file, color 2 for the second, and so on; after the last color, white. Opening the shelf starts the count over.", bundle: .module)
    ) {
      Button {
        store.send(.testFlashTapped)
      } label: {
        Text("Test", bundle: .module)
      }
      .buttonStyle(.quietCapsule)
      .help(Text("Plays the flashes in 3 seconds: close the window to watch the notch", bundle: .module))
    }

    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 14) {
        ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
          VStack(spacing: 4) {
            ColorWell(
              Text("Color \(index + 1)", bundle: .module),
              color: Binding(get: { color }, set: { store.send(.flashColorChanged(index: index, $0)) })
            )
            Text(index + 1, format: .number)
              .font(.system(size: 11).monospacedDigit())
              .foregroundStyle(VortexColor.tertiaryText)
          }
        }
        HStack(spacing: 4) {
          RoundButton(symbol: "plus", label: Text("Add a color", bundle: .module)) {
            store.send(.flashColorAdded)
          }
          if !colors.isEmpty {
            RoundButton(symbol: "minus", label: Text("Remove the last color", bundle: .module)) {
              store.send(.lastFlashColorRemoved)
            }
          }
        }
        Spacer(minLength: 0)
        if colors != ShelfSettings.defaultFlashColors {
          Button {
            store.send(.flashColorsReset)
          } label: {
            Text("Reset", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
          .help(Text("Back to blue and green", bundle: .module))
        }
      }
      .padding(.vertical, 10)
      Hairline()
    }
  }
}

private struct RoundButton: View {
  let symbol: String
  let label: Text
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 10.5, weight: .semibold))
        .frame(width: 30, height: 30)
        .background(Circle().fill(VortexColor.raised))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(VortexColor.secondaryText)
    .help(label)
    .accessibilityLabel(label)
  }
}
