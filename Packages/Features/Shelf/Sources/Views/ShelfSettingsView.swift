import ComposableArchitecture
import SwiftUI
import VortexCore

/// The shelf's section in Settings › Features: the watched folder and the file types it passes on.
struct ShelfSettingsView: View {
  let store: StoreOf<ShelfFeature>
  @State private var extensions = ""
  @FocusState private var isEditingExtensions: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(
        title: Text("Watched folder", bundle: .module),
        caption: Text("New files in it land on the shelf once they are fully written, and the notch flashes.", bundle: .module)
      ) {
        HStack(spacing: 8) {
          if let folder = store.settings.watchedFolder {
            Text(verbatim: (folder.path as NSString).abbreviatingWithTildeInPath)
              .font(.system(size: 12))
              .foregroundStyle(VortexColor.secondaryText)
              .lineLimit(1)
              .truncationMode(.head)
              .frame(maxWidth: 180, alignment: .trailing)
              .help(Text(verbatim: folder.path))
            Button {
              store.send(.chooseFolderTapped)
            } label: {
              Text("Change…", bundle: .module)
            }
            .buttonStyle(.quietCapsule)
            Button {
              store.send(.stopWatchingTapped)
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
          } else {
            Button {
              store.send(.chooseFolderTapped)
            } label: {
              Text("Choose…", bundle: .module)
            }
            .buttonStyle(.quietCapsule)
          }
        }
      }

      if store.settings.watchedFolder != nil {
        SettingsRow(
          title: Text("File types", bundle: .module),
          caption: Text("Extensions separated by commas; leave empty to take every file.", bundle: .module)
        ) {
          TextField(text: $extensions, prompt: Text(verbatim: ShelfSettings.defaultExtensions.joined(separator: ", "))) {
            Text("File types", bundle: .module)
          }
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .frame(width: 180)
          .focused($isEditingExtensions)
          .onSubmit { store.send(.extensionsChanged(extensions)) }
          .onChange(of: isEditingExtensions) { _, isEditing in
            if !isEditing { store.send(.extensionsChanged(extensions)) }
          }
        }
      }
    }
    .onAppear { extensions = store.settings.watchedExtensions.joined(separator: ", ") }
    .onChange(of: store.settings.watchedExtensions) { _, saved in
      extensions = saved.joined(separator: ", ")
    }
  }
}
