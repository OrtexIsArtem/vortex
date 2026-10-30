import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The Tasks section in Settings › Features: the shortcut, and a row while Screen Recording isn't working.
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

      PermissionRows(
        TasksModule.permissionNeeds,
        statuses: store.permissionStatuses,
        turnOn: { store.send(.turnOnTapped($0)) },
        restart: { store.send(.restartTapped) }
      )

      Text("Done tasks are deleted with their screenshots 30 days after they were done.", bundle: .module)
        .font(.system(size: 11.5))
        .foregroundStyle(VortexColor.tertiaryText)
        .padding(.top, 12)
    }
    .onAppear { store.send(.settingsShown) }
  }
}
