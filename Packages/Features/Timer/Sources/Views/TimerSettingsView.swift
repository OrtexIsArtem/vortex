import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The timer's section in Settings › Features: presets, the sound and the flash when time is up.
struct TimerSettingsView: View {
  let store: StoreOf<TimerFeature>
  @State private var presets = ""
  @FocusState private var isEditing: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(
        title: Text("Presets", bundle: .module),
        caption: Text("Minutes, separated by commas. Up to six: on Home they stand next to the notch.", bundle: .module)
      ) {
        TextField(text: $presets, prompt: Text(verbatim: "5, 10, 15, 25, 45, 60")) {
          Text("Presets", bundle: .module)
        }
        .labelsHidden()
        .textFieldStyle(.roundedBorder)
        .frame(width: 190)
        .focused($isEditing)
        .onSubmit { commitPresets() }
        .onChange(of: isEditing) { _, isEditing in
          if !isEditing { commitPresets() }
        }
      }

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
        caption: Text("When time is up, the notch flashes three times in this color.", bundle: .module)
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
          .help(Text("Plays the sound and the flashes in 3 seconds: close the window to watch the notch", bundle: .module))
        }
      }
    }
    .onAppear {
      presets = store.settings.presetsText
      store.send(.settingsShown)
    }
    // An edit still pending when the section goes away (a tab switch) is kept, not lost.
    .onDisappear { commitPresets() }
    // The presets changed from outside the field.
    .onChange(of: store.settings.presets) { presets = store.settings.presetsText }
  }

  /// Saves what was typed, then shows the list as saved: sorted, without what is invalid or past the sixth, or the
  /// defaults when nothing valid was typed. Watching the saved presets is not enough for this: it stays silent when
  /// the cleaned-up list equals the saved one, and the field would keep the typed text.
  private func commitPresets() {
    store.send(.presetsSubmitted(presets))
    // The send has applied the change by now.
    presets = store.settings.presetsText
  }

  /// The system sounds, and the chosen one even before they load, so the picker always has its selection.
  private var soundNames: [String] {
    var names = store.sounds
    if let sound = store.settings.sound, !names.contains(sound) { names.insert(sound, at: 0) }
    return names
  }
}
