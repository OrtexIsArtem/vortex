import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The timer's section in Settings › Features: the sound and the flash when time is up.
struct TimerSettingsView: View {
  let store: StoreOf<TimerFeature>

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(title: Text("Sound", bundle: .module), caption: Text("Plays when time is up.", bundle: .module)) {
        Picker(selection: Binding(get: { store.settings.sound }, set: { store.send(.soundChosen($0)) })) {
          Text("No sound", bundle: .module).tag(String?.none)
          Divider()
          ForEach(soundNames, id: \.self) { name in
            Text(verbatim: name).tag(Optional(name))
          }
        } label: {
          Text("Sound", bundle: .module)
        }
        .labelsHidden()
        .fixedSize()
      }

      SettingsRow(
        title: Text("Notch flash", bundle: .module),
        caption: Text("When time is up, the notch flashes in this color until you point at it.", bundle: .module)
      ) {
        HStack(spacing: 12) {
          ColorWell(
            Text("Flash color", bundle: .module),
            color: Binding(get: { store.settings.flashColor }, set: { store.send(.flashColorChanged($0)) })
          )
          Button {
            store.send(.testTapped)
          } label: {
            Text("Test", bundle: .module)
          }
          .buttonStyle(.quietCapsule)
          .help(Text("Plays the sound and the flashes in 3 seconds: close the window to watch the notch, point at it to stop them", bundle: .module))
        }
      }

      PermissionRows(
        TimerModule.permissionNeeds,
        statuses: store.permissionStatuses,
        turnOn: { store.send(.turnOnTapped($0)) },
        restart: { store.send(.restartTapped) }
      )
    }
    .onAppear { store.send(.settingsShown) }
  }

  /// The system sounds, and the chosen one even before they load, so the picker always has its selection.
  private var soundNames: [String] {
    var names = store.sounds
    if let sound = store.settings.sound, !names.contains(sound) { names.insert(sound, at: 0) }
    return names
  }
}
