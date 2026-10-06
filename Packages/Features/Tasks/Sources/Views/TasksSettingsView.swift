import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The Tasks section in Settings › Features: the shortcut, and whether Vortex may record the screen.
struct TasksSettingsView: View {
  let store: StoreOf<TasksFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(
        title: Text("New task", bundle: .module),
        caption: Text("Freezes the screen to frame what the task is about.", bundle: .module)
      ) {
        HotkeyRecorder(.captureTask, label: Text("New task", bundle: .module))
      }

      SettingsRow(
        title: Text("Screen Recording", bundle: .module),
        caption: store.hasScreenAccess
          ? Text("Allowed: tasks get screenshots and window titles.", bundle: .module)
          : Text("Needed for screenshots and window titles. After allowing it, open Vortex again.", bundle: .module)
      ) {
        if !store.hasScreenAccess {
          Button {
            store.send(.openScreenSettingsTapped)
          } label: {
            Text("Open System Settings", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
        }
      }

      Text("Done tasks are deleted with their screenshots 30 days after they were done.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.top, 12)
    }
    .onAppear { store.send(.settingsShown) }
  }
}
