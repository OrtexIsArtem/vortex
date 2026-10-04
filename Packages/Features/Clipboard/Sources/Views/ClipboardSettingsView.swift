import ComposableArchitecture
import SwiftUI
import VortexCore
import VortexPlatform

/// The clipboard's section in Settings › Features: apps whose copies are not kept.
struct ClipboardSettingsView: View {
  let store: StoreOf<ClipboardFeature>
  @Environment(\.isWindowOpen) private var isWindowOpen

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      SettingsRow(
        title: Text("Ignored apps", bundle: .module),
        caption: Text("Nothing copied in these apps is kept. Passwords marked secret are shown hidden and kept only until Vortex quits.", bundle: .module)
      ) {
        Menu {
          let ignored = Set(store.settings.ignoredApps.map(\.bundleID))
          ForEach(store.runningApps.filter { !ignored.contains($0.bundleID) }, id: \.bundleID) { app in
            Button(app.name) {
              store.send(.ignoreAppTapped(app))
            }
          }
          Divider()
          Button {
            store.send(.chooseAppTapped)
          } label: {
            Text("Other…", bundle: .module)
          }
        } label: {
          Text("Add app", bundle: .module)
        }
        .menuStyle(.button)
        .fixedSize()
      }

      ForEach(store.settings.ignoredApps, id: \.bundleID) { app in
        VStack(spacing: 0) {
          HStack(spacing: 12) {
            AppIcon(bundleID: app.bundleID)
              .frame(width: 20, height: 20)
            Text(verbatim: app.name)
            Spacer(minLength: 12)
            Button {
              store.send(.stopIgnoringAppTapped(bundleID: app.bundleID))
            } label: {
              Text("Remove", bundle: .module)
            }
            .buttonStyle(.quietCapsule)
          }
          .frame(minHeight: 44)
          Hairline()
        }
      }
    }
    .task(id: isWindowOpen) {
      if isWindowOpen { store.send(.settingsShown) }
    }
  }
}
