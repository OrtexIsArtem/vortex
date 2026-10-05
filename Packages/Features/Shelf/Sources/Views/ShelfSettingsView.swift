import ComposableArchitecture
import SwiftUI
import VortexCore

/// The shelf's section in Settings › Features: folders whose new files land on the shelf, with their file types.
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
          Text("Choose…", bundle: .module)
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
